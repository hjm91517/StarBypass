# StarBypass — FlashBytePro 注入库
#
# 分层（编号即依赖顺序，下层不引用上层）：
#   00-config.h      配置，唯一调参入口
#   01-shared        公共基础层
#   02-diagnose      诊断层
#   03-network       网络层
#   04-license       授权层
#   05-detection     对抗层
#   06-guard         稳定层
#   07-bootstrap     装配层（仅组装，不实现逻辑）
#   lib/             独立库，无 ObjC 依赖

TARGET   := StarBypass.dylib
BUILDDIR := build
OBJ      := $(BUILDDIR)/obj
IOS_MIN  := 14.0
ARCH     := arm64

SRCS := \
  01-shared.m \
  02-diagnose.m \
  03-network.m \
  04-license.m \
  05-detection.m \
  06-guard.m \
  07-bootstrap.m \
  lib/symbol-rebind.c

OBJS := $(patsubst %.m,$(OBJ)/%.o,$(patsubst %.c,$(OBJ)/%.o,$(SRCS)))

CFLAGS_COMMON := -fblocks -fno-objc-arc -Wall -Wextra -Wno-unused-parameter \
                 -Wno-deprecated-declarations -I. -Ilib

# ── 真机构建：需要 macOS + Xcode ──
CFLAGS_IOS  := -arch $(ARCH) -miphoneos-version-min=$(IOS_MIN) $(CFLAGS_COMMON)
LDFLAGS_IOS := -dynamiclib -arch $(ARCH) -miphoneos-version-min=$(IOS_MIN) \
               -framework Foundation -framework UIKit -lobjc -lSystem \
               -Wl,-no_fixup_chains \
               -install_name @executable_path/Frameworks/$(TARGET)

# ── 交叉构建：无 SDK 时用 compat 头 + ld64.lld ──
CFLAGS_CROSS  := -target $(ARCH)-apple-ios$(IOS_MIN) -DSB_SYNTAX_ONLY \
                 $(CFLAGS_COMMON) -Icompat
LDFLAGS_CROSS := -dylib -arch $(ARCH) -platform_version ios $(IOS_MIN) $(IOS_MIN) \
                 -no_fixup_chains \
                 -install_name @executable_path/Frameworks/$(TARGET) \
                 -undefined dynamic_lookup

.PHONY: all ios cross check verify contracts clean help

all: cross

help:
	@echo "make ios     真机构建（需 Xcode）"
	@echo "make cross   交叉构建（无 SDK，产出可用 dylib）"
	@echo "make check   仅语法校验"
	@echo "make verify  校验产物结构"
	@echo "make contracts 校验契约一致性"
	@echo "make clean   清理"

# 真机
ios:
	xcrun -sdk iphoneos clang $(CFLAGS_IOS) \
	  $(SRCS) $(LDFLAGS_IOS) -o $(TARGET)
	@file $(TARGET)

# 交叉构建
cross: $(OBJS)
	@mkdir -p $(BUILDDIR)
	ld64.lld $(LDFLAGS_CROSS) -o $(BUILDDIR)/linked.dylib $(OBJS)
	cp $(BUILDDIR)/linked.dylib $(TARGET)
	python3 tools/inject-load-dylibs.py $(TARGET)
	@file $(TARGET)

$(OBJ)/%.o: %.m
	@mkdir -p $(dir $@)
	clang -c $(CFLAGS_CROSS) $< -o $@

$(OBJ)/%.o: %.c
	@mkdir -p $(dir $@)
	clang -c $(CFLAGS_CROSS) -isystem $$(dirname $$(clang -print-resource-dir))/include $< -o $@

# 语法校验
check:
	@for f in $(filter %.m,$(SRCS)); do \
	  printf "%-24s " $$f; \
	  clang -fsyntax-only $(CFLAGS_CROSS) -x objective-c $$f && echo OK || exit 1; \
	done
	@for f in $(filter %.c,$(SRCS)); do \
	  printf "%-24s " $$f; \
	  clang -fsyntax-only $(CFLAGS_CROSS) \
	    -isystem $$(dirname $$(clang -print-resource-dir))/include $$f && echo OK || exit 1; \
	done
	@echo "语法校验全部通过"

# 契约一致性：声明与实现、装配覆盖、配置使用、依赖方向
contracts:
	python3 ../docs/verify-contracts.py

# 产物校验
verify:
	python3 tools/verify-binary.py $(TARGET)

clean:
	rm -rf $(BUILDDIR) $(TARGET)
