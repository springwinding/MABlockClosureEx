
#import <Foundation/Foundation.h>

#import "MABlockClosure.h"


#if TARGET_OS_IPHONE
#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>
#import<objc/runtime.h>
#define NSStringFromRect(r) NSStringFromCGRect(r)
#endif

@interface MyObject : NSObject
- (CGRect)stringParam:(NSString *)str rectParam:(CGRect)rect charParam:(char)charValue intParam:(int)intValue pointParam:(CGPoint)point voidParam:(void *)voidP  endParam:(NSString *)end;
@end

@implementation MyObject
- (CGRect)stringParam:(NSString *)str rectParam:(CGRect)rect charParam:(char)charValue intParam:(int)intValue pointParam:(CGPoint)point voidParam:(void *)voidP  endParam:(NSString *)end{
    return CGRectMake(12, 13, 14, 15);
}
@end

int main(int argc, char **argv)
{
    [NSAutoreleasePool new];
    
    
    Method method = class_getInstanceMethod(MyObject.class, @selector(stringParam:rectParam:charParam:intParam:pointParam:voidParam:endParam:));
    NSString *typeDescription = @((char *)method_getTypeEncoding(method));
    MABlockClosure *closure = [[MABlockClosure alloc] initWithSignature: typeDescription];
    class_replaceMethod(MyObject.class, @selector(stringParam:rectParam:charParam:intParam:pointParam:voidParam:endParam:), [closure fptr], [typeDescription UTF8String]);
    MyObject *object = [MyObject new];
    void *poiner = malloc(10);
   CGRect returnRect = [object stringParam:@"test1" rectParam:CGRectMake(12, 33, 54, 76)  charParam:'c' intParam:1986 pointParam:CGPointMake(-20, 25) voidParam:poiner endParam:@"hello world"];
    NSLog(@"returnRect 的值是%@",NSStringFromRect(returnRect));
    
    id block = ^(int x, int y) { return x + y; };
    closure = [[MABlockClosure alloc] initWithBlock: block];
    int ret = ((int (*)(int, int))[closure fptr])(5, 10);
    NSLog(@"%d", ret);
    
    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
    [runLoop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
    [runLoop run];
}
