# ReconDylib — 侦察版注入库
#
# 纯观测：不改任何业务行为，只把运行时真实数据落盘。
# 依赖 src/ 的 compat 头与 symbol-rebind 库，不复制。

TARGET   := ReconDylib.dylib
BUILDDIR := build
OBJ      := $(BUILDDIR)/obj
IOS_MIN  := 14.0
ARCH     := arm64

# 复用绕过版的基础设施
SRC_ROOT := ../src
COMPAT   := $(SRC_ROOT)/compat
REBIND   := $(SRC_ROOT)/lib/symbol-rebind.c

SRCS := \
  01-shared.m \
  02-capture.m \
  03-trace.m \
  04-ui.m \
  05-stealth.m \
  06-guard.m \
  07-bootstrap.m

OBJS := $(patsubst %.m,$(OBJ)/%.o,$(SRCS)) $(OBJ)/symbol-rebind.o

# 侦察版用 ARC：包装回调 block 捕获对象必须自动持有，否则野指针
CFLAGS_COMMON := -fblocks -fobjc-arc -Wall -Wextra -Wno-unused-parameter \
                 -Wno-deprecated-declarations \
                 -I. -I$(SRC_ROOT) -I$(SRC_ROOT)/lib -I$(COMPAT)

CFLAGS_IOS  := -arch $(ARCH) -miphoneos-version-min=$(IOS_MIN) $(CFLAGS_COMMON)
LDFLAGS_IOS := -dynamiclib -arch $(ARCH) -miphoneos-version-min=$(IOS_MIN) \
               -framework Foundation -framework UIKit -lobjc -lSystem \
               -Wl,-no_fixup_chains \
               -install_name @executable_path/Frameworks/$(TARGET)

CFLAGS_CROSS  := -target $(ARCH)-apple-ios$(IOS_MIN) -DSB_SYNTAX_ONLY $(CFLAGS_COMMON)
LDFLAGS_CROSS := -dylib -arch $(ARCH) -platform_version ios $(IOS_MIN) $(IOS_MIN) \
                 -no_fixup_chains \
                 -install_name @executable_path/Frameworks/$(TARGET) \
                 -undefined dynamic_lookup

.PHONY: all ios cross check verify clean help

all: cross

help:
	@echo "make ios     真机构建（需 Xcode）"
	@echo "make cross   交叉构建（无 SDK）"
	@echo "make check   语法校验"
	@echo "make verify  产物校验"
	@echo "make clean   清理"

ios:
	xcrun -sdk iphoneos clang $(CFLAGS_IOS) \
	  $(SRCS) $(REBIND) $(LDFLAGS_IOS) -o $(TARGET)
	@file $(TARGET)

cross: $(OBJS)
	@mkdir -p $(BUILDDIR)
	ld64.lld $(LDFLAGS_CROSS) -o $(BUILDDIR)/linked.dylib $(OBJS)
	cp $(BUILDDIR)/linked.dylib $(TARGET)
	python3 $(SRC_ROOT)/tools/inject-load-dylibs.py $(TARGET)
	@file $(TARGET)

$(OBJ)/%.o: %.m
	@mkdir -p $(dir $@)
	clang -c $(CFLAGS_CROSS) $< -o $@

$(OBJ)/symbol-rebind.o: $(REBIND)
	@mkdir -p $(dir $@)
	clang -c $(CFLAGS_CROSS) -isystem $$(dirname $$(clang -print-resource-dir))/include $< -o $@

check:
	@for f in $(SRCS); do \
	  printf "%-20s " $$f; \
	  clang -fsyntax-only $(CFLAGS_CROSS) -x objective-c $$f && echo OK || exit 1; \
	done
	@echo "语法校验全部通过"

verify:
	python3 $(SRC_ROOT)/tools/verify-binary.py $(TARGET)

clean:
	rm -rf $(BUILDDIR) $(TARGET)
