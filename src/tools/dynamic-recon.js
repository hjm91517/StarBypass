// dynamic-recon.js — 运行时动态逆向探查
//
// 目的：静态分析已确认二进制里没有明文文案和 URL（全部运行时解密），
//       因此真实接口、真实回包、真实失败文案来源只能动态取得。
//
// 用法：
//   frida -U -f com.shadow.h5ggapp -l dynamic-recon.js
//   # 或已有进程：frida -U -n h5ggapp -l dynamic-recon.js
//
// 产出四类证据：
//   [P1] 环境与类是否存在
//   [P2] 授权类全部方法清单 + 返回值观测
//   [P3] 真实网络请求 URL / body / 真实回包
//   [P4] 失败文案来源（带调用栈）
//
// 注意：默认对卡密等敏感值做脱敏（REDACT=true 可关闭）。

'use strict';

const CONFIG = {
  AUTH_CLASS: 'KQ7mV2xN9R',
  MENU_CLASS: 'STARSMenuView',
  REDACT: true,          // 脱敏卡密/设备号
  MAX_EVENTS: 200,       // 事件上限，防日志爆量
  LOG_BODY_LIMIT: 4096,  // body 最长打印
};

let eventCount = 0;
const seenSelectors = new Set();

function log(tag, msg) {
  console.log(`[${tag}] ${msg}`);
}

function budgetOk() {
  if (eventCount >= CONFIG.MAX_EVENTS) return false;
  eventCount++;
  return true;
}

function redact(s) {
  if (!s) return s;
  s = String(s);
  if (!CONFIG.REDACT) return s;
  // 长串只留首尾，短串整体遮蔽
  if (s.length <= 8) return '*'.repeat(s.length);
  return s.slice(0, 3) + '***' + s.slice(-3);
}

function safeStr(obj) {
  try {
    if (obj === null || obj === undefined) return String(obj);
    return obj.toString();
  } catch (e) {
    return '<unreadable>';
  }
}

// ─────────────────────────────────────────────
// P1 环境
// ─────────────────────────────────────────────
function phaseEnv() {
  const hasObjC = typeof ObjC !== 'undefined' && ObjC.available;
  log('P1', `objc=${hasObjC} platform=${Process.platform} arch=${Process.arch}`);
  if (!hasObjC) {
    log('P1', 'Objective-C 运行时不可用，终止');
    return false;
  }

  for (const name of [CONFIG.AUTH_CLASS, CONFIG.MENU_CLASS]) {
    const cls = ObjC.classes[name];
    log('P1', `类 ${name}: ${cls ? '存在' : '不存在'}`);
  }

  // 检查我们自己的 dylib 是否加载
  const mods = Process.enumerateModules().filter(m => m.name.includes('StarBypass'));
  if (mods.length) {
    mods.forEach(m => log('P1', `StarBypass 已加载 base=${m.base} size=${m.size}`));
  } else {
    log('P1', 'StarBypass 未加载（本脚本可独立工作）');
  }
  return true;
}

// ─────────────────────────────────────────────
// P2 授权类方法清单 + 返回值
// ─────────────────────────────────────────────
function phaseMethods() {
  const cls = ObjC.classes[CONFIG.AUTH_CLASS];
  if (!cls) {
    log('P2', `${CONFIG.AUTH_CLASS} 不存在，跳过`);
    return;
  }

  const methods = cls.$ownMethods;
  log('P2', `方法总数 ${methods.length}`);

  for (const sig of methods) {
    // sig 形如 "- qM6tX1bW" 或 "- v28@0:8@16"
    const isClass = sig.startsWith('+');
    const name = sig.split(' ')[1] || sig;
    log('P2', `${isClass ? '+' : '-'}[${CONFIG.AUTH_CLASS} ${name}]`);

    try {
      const impl = cls[isClass ? name : name];
      if (!impl || typeof impl !== 'object') continue;

      // 只观测无参数、无返回对象风险的方法，避免破坏时序
      impl.implementation = ObjC.implement(impl, function (handle, selector) {
        const r = impl(handle, selector);
        if (budgetOk()) {
          log('P2', `调用 ${name} → ${safeStr(r)}`);
        }
        return r;
      });
    } catch (e) {
      // 带参方法需要精确签名，跳过（交给 dylib 的接管层）
    }
  }
}

// ─────────────────────────────────────────────
// P3 网络：真实请求与回包
// ─────────────────────────────────────────────
function phaseNetwork() {
  const NSURLSession = ObjC.classes.NSURLSession;
  if (!NSURLSession) {
    log('P3', 'NSURLSession 不存在');
    return;
  }

  const sel = 'dataTaskWithRequest:completionHandler:';
  const method = NSURLSession['- ' + sel];
  if (!method) {
    log('P3', `未找到 -${sel}`);
    return;
  }

  const orig = method.implementation;
  method.implementation = ObjC.implement(method, function (handle, selector, request, handler) {
    try {
      const url = request.URL().absoluteString().toString();
      const httpMethod = request.HTTPMethod() ? request.HTTPMethod().toString() : '?';
      const body = request.HTTPBody();
      let bodyStr = '<nil>';
      if (body) {
        const ns = ObjC.classes.NSString.alloc()
          .initWithData_encoding_(body, 4); // NSUTF8StringEncoding
        bodyStr = ns ? ns.toString() : `<${body.length()} bytes>`;
        if (bodyStr.length > CONFIG.LOG_BODY_LIMIT) {
          bodyStr = bodyStr.slice(0, CONFIG.LOG_BODY_LIMIT) + '...';
        }
      }
      if (budgetOk()) {
        log('P3', `→ ${httpMethod} ${url}`);
        log('P3', `   body: ${bodyStr}`);
      }

      // 包装 handler 观察真实回包
      const wrapped = new ObjC.Block({
        retType: 'void',
        argTypes: ['object', 'object', 'object'],
        implementation: function (data, response, error) {
          try {
            if (error) {
              log('P3', `   ← 错误 ${error.localizedDescription()}`);
            } else if (data) {
              const ns = ObjC.classes.NSString.alloc().initWithData_encoding_(data, 4);
              if (ns) {
                let txt = ns.toString();
                if (txt.length > CONFIG.LOG_BODY_LIMIT) {
                  txt = txt.slice(0, CONFIG.LOG_BODY_LIMIT) + '...';
                }
                log('P3', `   ← 真实回包: ${txt}`);
              }
            }
          } catch (e) {
            log('P3', `   ← 解析异常 ${e}`);
          }
          if (handler) handler(data, response, error);
        },
      });

      return orig(handle, selector, request, wrapped);
    } catch (e) {
      log('P3', `hook 异常 ${e}`);
      return orig(handle, selector, request, handler);
    }
  });

  log('P3', `已挂 -${sel}`);
}

// ─────────────────────────────────────────────
// P4 失败文案来源
// ─────────────────────────────────────────────
const FAIL_WORDS = ['不存在', '失败', '错误', '无效', '过期', '未授权', '未激活', '请输入正确'];

function phaseTextOrigin() {
  const UILabel = ObjC.classes.UILabel;
  if (!UILabel) {
    log('P4', 'UILabel 不存在');
    return;
  }

  const method = UILabel['- setText:'];
  if (!method) return;

  const orig = method.implementation;
  method.implementation = ObjC.implement(method, function (handle, selector, text) {
    try {
      const s = text ? text.toString() : '';
      if (s && FAIL_WORDS.some(w => s.indexOf(w) >= 0)) {
        log('P4', `=== 失败文案出现: "${s}" ===`);
        // 调用栈定位产生方
        const bt = Thread.backtrace(this.context, Backtracer.ACCURATE)
          .map(DebugSymbol.fromAddress).slice(0, 12);
        bt.forEach((s2, i) => log('P4', `   #${i} ${s2}`));
      }
    } catch (e) { }
    return orig(handle, selector, text);
  });

  log('P4', '已挂 -[UILabel setText:]');
}

// ─────────────────────────────────────────────
// 启动
// ─────────────────────────────────────────────
function main() {
  log('RECON', '=== 动态逆向开始 ===');
  if (!phaseEnv()) return;

  // 类可能延迟加载，稍等再挂
  setTimeout(() => {
    phaseMethods();
    phaseNetwork();
    phaseTextOrigin();
    log('RECON', '=== 挂载完成，请触发一次卡密验证 ===');
    log('RECON', '重点看 [P3] 真实 URL/body/回包，[P4] 失败文案的调用栈');
  }, 1500);
}

main();
