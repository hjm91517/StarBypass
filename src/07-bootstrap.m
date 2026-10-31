// 07-bootstrap.m — 装配层：把各模块装起来
//
// 本文件不实现任何业务逻辑，只负责按依赖顺序调用各层的安装函数。
// 依赖方向：本层 → 02..06 → 01，单向，不反向。

#import "01-shared.h"

// 各层装入口（由对应模块导出）
extern void SB_installDiagnose(void);
extern void SB_installNetwork(void);
extern void SB_installLicense(void);
extern void SB_installDetection(void);
extern void SB_installGuard(void);

// 立即装：不依赖 UI 的部分
static void SB_bootOnce(void) {
    SBLog(@"=== StarBypass 启动 build=%s ===", SB_CFG_BUILD_ID);
    SBLog(@"主卡密 %s，任意卡密通过=%d，改写失败文案=%d",
          SB_masterCardC(),
          (int)SB_acceptAny(),
          (int)SB_overrideFailureText());

    // 顺序有讲究：
    //   防护先装，后面任何异常都不至于崩
    //   检测层只碰符号，先装
    //   网络层要在请求发出前就位
    //   授权层最后装，此时类应已加载
    SB_installGuard();
    SB_installDetection();
    SB_installNetwork();
    SB_installLicense();
    SB_installDiagnose();
}

__attribute__((constructor))
static void SB_init(void) {
    SB_asyncMain(^{
        SB_bootOnce();

        // UI 起来后补挂一次：目标类可能在构造期还没加载
        SB_afterSec(SB_CFG_REHOOK_DELAY, ^{
            SBLog(@"=== 补挂 hook ===");
            SB_installLicense();
            SB_installDiagnose();
            SB_persistAuthorized(nil, nil);
            SBLog(@"=== 装配完成 ===");
        });
    });
}
