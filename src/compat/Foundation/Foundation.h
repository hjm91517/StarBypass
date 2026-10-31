#ifndef SB_COMPAT_FOUNDATION_H
#define SB_COMPAT_FOUNDATION_H
#ifdef SB_SYNTAX_ONLY

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdarg.h>

typedef signed char BOOL;
#define YES ((BOOL)1)
#define NO  ((BOOL)0)
#define nil ((id)0)
#define Nil ((Class)0)

typedef long NSInteger;
typedef unsigned long NSUInteger;
typedef double NSTimeInterval;
typedef NSUInteger NSStringEncoding;
typedef struct { NSUInteger location, length; } NSRange;
static inline NSRange NSMakeRange(NSUInteger l, NSUInteger n) { NSRange r; r.location=l; r.length=n; return r; }

#define NSUTF8StringEncoding 4
#define NSJSONWritingPrettyPrinted 1
#define NSEC_PER_SEC 1000000000ull

typedef struct { NSUInteger __x; } dispatch_once_t;
typedef void *dispatch_queue_t;
typedef uint64_t dispatch_time_t;
#define DISPATCH_TIME_NOW 0ull
extern void dispatch_once(dispatch_once_t *, void (^)(void));
extern void dispatch_async(dispatch_queue_t, void (^)(void));
extern void dispatch_after(dispatch_time_t, dispatch_queue_t, void (^)(void));
extern dispatch_queue_t dispatch_get_main_queue(void);
extern dispatch_time_t dispatch_time(dispatch_time_t, int64_t);

typedef const void *CFTypeRef;
typedef const struct __CFString *CFStringRef;
typedef const struct __CFDictionary *CFDictionaryRef;
typedef const struct __CFAllocator *CFAllocatorRef;
extern const void *CFRetain(const void *);
extern void CFRelease(const void *);

extern int printf(const char *, ...);
extern char *strcasestr(const char *, const char *);

@class NSDate, NSString, NSNumber, NSArray, NSDictionary, NSMutableDictionary, NSSet;
@class NSData, NSError, NSException, NSURL;

@protocol NSObject
- (BOOL)respondsToSelector:(SEL)s;
- (BOOL)isKindOfClass:(Class)c;
- (id)performSelector:(SEL)s;
@end

__attribute__((objc_root_class))
@interface NSObject <NSObject>
+ (instancetype)alloc;
+ (Class)class;
- (instancetype)init;
- (Class)class;
- (BOOL)respondsToSelector:(SEL)s;
- (BOOL)isKindOfClass:(Class)c;
- (id)performSelector:(SEL)s;
- (NSString *)description;
@end

@interface NSException : NSObject
- (NSString *)name;
- (NSString *)reason;
@end
extern void NSSetUncaughtExceptionHandler(void (*)(NSException *));

@interface NSNumber : NSObject
+ (NSNumber *)numberWithBool:(BOOL)b;
+ (NSNumber *)numberWithInt:(int)i;
- (id)stringValue;
@end

@interface NSString : NSObject
+ (instancetype)stringWithUTF8String:(const char *)s;
+ (instancetype)stringWithFormat:(NSString *)f, ...;
- (instancetype)initWithFormat:(NSString *)f arguments:(va_list)ap;
- (instancetype)initWithData:(NSData *)d encoding:(NSUInteger)enc;
- (NSString *)stringByAppendingPathComponent:(NSString *)c;
- (NSString *)lowercaseString;
- (NSString *)stringByAppendingString:(NSString *)a;
- (NSString *)substringToIndex:(NSUInteger)i;
- (NSString *)substringFromIndex:(NSUInteger)i;
- (NSString *)uppercaseString;
- (NSString *)stringByTrimmingCharactersInSet:(id)set;
- (NSString *)stringByRemovingPercentEncoding;
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)a withString:(NSString *)b;
- (NSString *)lastPathComponent;
- (NSString *)stringByDeletingPathExtension;
- (id)stringValue;
- (const char *)UTF8String;
- (NSUInteger)length;
- (BOOL)isEqualToString:(NSString *)s;
- (BOOL)hasPrefix:(NSString *)p;
- (BOOL)hasSuffix:(NSString *)p;
- (BOOL)containsString:(NSString *)s;
- (NSArray *)componentsSeparatedByString:(NSString *)sep;
- (NSData *)dataUsingEncoding:(NSUInteger)enc;
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)a encoding:(NSUInteger)e error:(id *)err;
@end

@interface NSMutableString : NSString
+ (instancetype)string;
+ (instancetype)stringWithCapacity:(NSUInteger)c;
- (void)appendFormat:(NSString *)f, ...;
- (void)appendString:(NSString *)s;
- (void)deleteCharactersInRange:(NSRange)r;
- (NSString *)copy;
@end

@interface NSData : NSObject
@property (readonly) const void *bytes;
@property (readonly) NSUInteger length;
- (instancetype)initWithBytes:(const void *)b length:(NSUInteger)l;
- (instancetype)initWithData:(NSData *)d;
- (instancetype)initWithBase64EncodedString:(NSString *)s options:(NSUInteger)o;
- (NSString *)base64EncodedStringWithOptions:(NSUInteger)o;
- (NSData *)subdataWithRange:(NSRange)r;
@end

@interface NSArray : NSObject
+ (instancetype)array;
+ (instancetype)arrayWithObject:(id)o;
+ (instancetype)arrayWithObjects:(const id [])objects count:(NSUInteger)cnt;
- (NSUInteger)count;
- (id)objectAtIndex:(NSUInteger)i;
- (id)objectAtIndexedSubscript:(NSUInteger)i;
- (id)objectForKeyedSubscript:(id)k;
- (id)firstObject;
- (id)lastObject;
- (BOOL)containsObject:(id)o;
- (NSUInteger)countByEnumeratingWithState:(void *)st objects:(id *)b count:(NSUInteger)len;
- (NSString *)componentsJoinedByString:(NSString *)sep;
- (NSArray *)subarrayWithRange:(NSRange)r;
- (id)mutableCopy;
- (id)copy;
@end

@interface NSMutableArray : NSArray
- (NSMutableArray *)mutableCopy;
- (void)addObject:(id)o;
- (void)removeObject:(id)o;
- (void)removeAllObjects;
@end

@interface NSDictionary : NSObject
+ (instancetype)dictionary;
+ (instancetype)dictionaryWithObjects:(const id [])objects forKeys:(const id [])keys count:(NSUInteger)cnt;
- (id)objectForKey:(id)k;
- (id)objectForKeyedSubscript:(id)k;
- (NSUInteger)count;
- (NSArray *)allKeys;
- (NSArray *)allValues;
@end

@interface NSMutableDictionary : NSDictionary
+ (instancetype)dictionary;
- (void)setObject:(id)o forKey:(id)k;
- (void)setObject:(id)o forKeyedSubscript:(id)k;
- (void)removeObjectForKey:(id)k;
- (void)removeAllObjects;
@end

@interface NSSet : NSObject
@end

@interface NSCharacterSet : NSObject
+ (instancetype)whitespaceAndNewlineCharacterSet;
+ (instancetype)characterSetWithCharactersInString:(NSString *)s;
@end

@interface NSJSONSerialization : NSObject
+ (id)JSONObjectWithData:(NSData *)d options:(NSUInteger)o error:(NSError **)e;
+ (NSData *)dataWithJSONObject:(id)obj options:(NSUInteger)o error:(NSError **)e;
@end

@interface NSError : NSObject
- (NSInteger)code;
- (NSString *)localizedDescription;
@end

@interface NSURL : NSObject
+ (instancetype)URLWithString:(NSString *)s;
- (NSString *)absoluteString;
+ (instancetype)fileURLWithPath:(NSString *)p;
- (NSString *)path;
@end

@interface NSURLRequest : NSObject
+ (instancetype)requestWithURL:(NSURL *)u;
- (NSURL *)URL;
- (NSDictionary *)allHTTPHeaderFields;
- (NSData *)HTTPBody;
- (NSString *)HTTPMethod;
- (void)setHTTPBody:(NSData *)d;
- (void)setHTTPMethod:(NSString *)m;
- (void)setValue:(NSString *)v forHTTPHeaderField:(NSString *)f;
- (NSString *)valueForHTTPHeaderField:(NSString *)f;
- (void)setTimeoutInterval:(double)t;
@end

@interface NSMutableURLRequest : NSURLRequest
@end

@interface NSURLResponse : NSObject
- (NSURL *)URL;
- (NSInteger)statusCode;
- (NSDictionary *)allHeaderFields;
@end

@interface NSHTTPURLResponse : NSURLResponse
- (instancetype)initWithURL:(NSURL *)u
                 statusCode:(NSInteger)code
                HTTPVersion:(NSString *)v
               headerFields:(NSDictionary *)h;
@end

@interface NSURLSessionTask : NSObject
- (NSURLRequest *)originalRequest;
- (NSURLRequest *)currentRequest;
- (void)resume;
- (void)cancel;
@end

@interface NSURLSessionDataTask : NSURLSessionTask
@end

typedef NSInteger NSURLSessionResponseDisposition;

@interface NSURLSession : NSObject
+ (instancetype)sharedSession;
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)r
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))h;
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)u
                        completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))h;
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)r;
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)u;
@end

typedef NSUInteger NSURLCacheStoragePolicy;
#define NSURLCacheStorageNotAllowed 0
@class NSURLProtocol;
@protocol NSURLProtocolClient <NSObject>
- (void)URLProtocol:(NSURLProtocol *)p didReceiveResponse:(NSURLResponse *)r cacheStoragePolicy:(NSURLCacheStoragePolicy)policy;
- (void)URLProtocol:(NSURLProtocol *)p didLoadData:(NSData *)d;
- (void)URLProtocolDidFinishLoading:(NSURLProtocol *)p;
- (void)URLProtocol:(NSURLProtocol *)p didFailWithError:(NSError *)e;
@end
@interface NSURLProtocol : NSObject
+ (BOOL)canInitWithRequest:(NSURLRequest *)r;
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r;
+ (void)registerClass:(Class)c;
+ (id)propertyForKey:(NSString *)k inRequest:(NSURLRequest *)r;
+ (BOOL)setProperty:(id)v forKey:(NSString *)k inRequest:(NSMutableURLRequest *)r;
- (NSURLRequest *)request;
- (id<NSURLProtocolClient>)client;
- (instancetype)initWithRequest:(NSURLRequest *)r cachedResponse:(id)c client:(id<NSURLProtocolClient>)cl;
- (void)startLoading;
- (void)stopLoading;
@end
@interface NSURLSessionConfiguration : NSObject
+ (instancetype)defaultSessionConfiguration;
+ (instancetype)ephemeralSessionConfiguration;
- (NSArray *)protocolClasses;
- (void)setProtocolClasses:(NSArray *)a;
- (void)setTimeoutIntervalForRequest:(double)t;
@end
@interface NSTimer : NSObject
+ (NSTimer *)scheduledTimerWithTimeInterval:(double)t
                                   target:(id)target
                                 selector:(SEL)sel
                                 userInfo:(id)info
                                  repeats:(BOOL)r;
- (void)invalidate;
@end
@interface NSThread : NSObject
+ (NSThread *)currentThread;
- (NSArray *)callStackSymbols;
@end
@interface NSUserDefaults : NSObject
+ (instancetype)standardUserDefaults;
- (void)setBool:(BOOL)v forKey:(NSString *)k;
- (BOOL)boolForKey:(NSString *)k;
- (void)setObject:(id)o forKey:(NSString *)k;
- (id)objectForKey:(NSString *)k;
- (BOOL)synchronize;
- (void)setInteger:(NSInteger)v forKey:(NSString *)k;
- (NSInteger)integerForKey:(NSString *)k;
@end

extern void NSLog(NSString *fmt, ...);
extern NSString *NSStringFromClass(Class c);
extern NSString *NSStringFromSelector(SEL s);

#endif
@interface NSBundle : NSObject
+ (NSBundle *)mainBundle;
- (NSDictionary *)infoDictionary;
@end
@interface NSDate : NSObject
+ (NSDate *)date;
@end
@interface NSDateFormatter : NSObject
- (void)setDateFormat:(NSString *)f;
- (NSString *)stringFromDate:(NSDate *)d;
@end

@interface NSFileManager : NSObject
+ (NSFileManager *)defaultManager;
- (BOOL)createDirectoryAtPath:(NSString *)p
  withIntermediateDirectories:(BOOL)c
                   attributes:(NSDictionary *)a
                        error:(id *)e;
@end
extern NSString *NSTemporaryDirectory(void);
extern NSString *NSHomeDirectory(void);
extern NSString *NSRunLoopCommonModes;
#endif
