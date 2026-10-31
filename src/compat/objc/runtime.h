// compat/objc/runtime.h — 语法校验用最小 runtime 声明
#ifndef SB_COMPAT_OBJC_RUNTIME_H
#define SB_COMPAT_OBJC_RUNTIME_H

#include <stdint.h>

@class NSString;

typedef struct objc_class *Class;
typedef struct objc_object { Class isa; } *id;
typedef struct objc_selector *SEL;
typedef struct objc_method *Method;

typedef void (*IMP)(void);

extern Class objc_getClass(const char *name);
extern Class object_getClass(id obj);
extern Class NSClassFromString(NSString *name);
extern SEL NSSelectorFromString(NSString *name);
extern SEL sel_registerName(const char *name);
extern const char *sel_getName(SEL sel);

extern Method class_getInstanceMethod(Class cls, SEL sel);
extern Method class_getClassMethod(Class cls, SEL sel);
extern Method *class_copyMethodList(Class cls, unsigned int *outCount);
extern IMP method_getImplementation(Method m);
extern SEL method_getName(Method m);
extern const char *method_getTypeEncoding(Method m);

extern IMP class_replaceMethod(Class cls, SEL sel, IMP imp, const char *types);
extern BOOL class_respondsToSelector(Class cls, SEL sel);
extern BOOL class_addMethod(Class cls, SEL sel, IMP imp, const char *types);

extern IMP imp_implementationWithBlock(id block);
extern id objc_msgSend(id self, SEL op, ...);

#endif
