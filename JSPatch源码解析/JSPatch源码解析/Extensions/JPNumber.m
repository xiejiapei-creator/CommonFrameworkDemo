//
//  JPNumber.m
//  JSPatchDemo
//
//  Created by pucheng on 16/7/5.
//  Copyright © 2016年 pucheng. All rights reserved.
//

#import "JPNumber.h"
#import <objc/runtime.h>

@implementation JPNumber

+ (void)main:(JSContext *)context {
    
    // for subclass of NSNumber, e.g. NSDecimalNumber
    context[@"OCNumber"] = ^ id (NSString *clsName, NSString *selName, JSValue *arguments) {
        // JS 把要调用的类名/方法名/对象传给 OC后
        Class cls = NSClassFromString(clsName);
        SEL sel = NSSelectorFromString(selName);
        if (!cls || !sel) return nil;
        
        Method m = class_getClassMethod(cls, sel);
        if (!m) return nil;
        
        // view.setAlpha(0.5)  JS传递给OC的是一个 NSNumber
        // OC 需要通过要调用OC方法的 NSMethodSignature 来得知这里参数要的是一个 float 类型值
        NSMethodSignature *methodSignature = [cls methodSignatureForSelector:sel];
        // OC 调用类/对象相应的方法是通过 NSInvocation 实现
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
        [invocation setTarget:cls];
        [invocation setSelector:sel];
        
        
        id argumentsObj = [self formatJSToOC: arguments];
        NSUInteger numberOfArguments = methodSignature.numberOfArguments;
        
        // 遍历参数。处理了 int/float/bool 等数值类型，并对 CGRect/CGRange 等类型进行了特殊转换处理
        for (NSUInteger i = 2; i < numberOfArguments; i++) {
            const char *argumentType = [methodSignature getArgumentTypeAtIndex:i];
            id valObj = argumentsObj[i-2];
            switch (argumentType[0] == 'r' ? argumentType[1] : argumentType[0]) {
                    
                #define JP_OCNumber_CASE(_typeString, _type, _selector) \
                    case _typeString: { \
                        _type value = [valObj _selector];  \
                        [invocation setArgument:&value atIndex:i];  \
                        break;  \
                    }
                    
                    JP_OCNumber_CASE('c', char, charValue)
                    JP_OCNumber_CASE('C', unsigned char, unsignedCharValue)
                    JP_OCNumber_CASE('s', short, shortValue)
                    JP_OCNumber_CASE('S', unsigned short, unsignedShortValue)
                    JP_OCNumber_CASE('i', int, intValue)
                    JP_OCNumber_CASE('I', unsigned int, unsignedIntValue)
                    JP_OCNumber_CASE('l', long, longValue)
                    JP_OCNumber_CASE('L', unsigned long, unsignedLongValue)
                    JP_OCNumber_CASE('q', long long, longLongValue)
                    JP_OCNumber_CASE('Q', unsigned long long, unsignedLongLongValue)
                    JP_OCNumber_CASE('f', float, floatValue)
                    JP_OCNumber_CASE('d', double, doubleValue)
                    JP_OCNumber_CASE('B', BOOL, boolValue)
                default:
                    [invocation setArgument:&valObj atIndex:i];
            }
        }
        // 把 NSNumber 转为 float 值再作为参数进行 OC 方法调用
        [invocation invoke];
        
        // 根据返回值类型取出返回值，包装为对象传回给 JS
        void *result;
        [invocation getReturnValue:&result];
        id returnValue = (__bridge id)result;
        /**
         * must be boxed in JPBoxing.
         * Otherwise when calling functions in JS, the number valued 0 which is considered as null will call a class function rather than a instance function in JSPatch.js
         */
        JPBoxing *box = [[JPBoxing alloc] init];
        box.obj = returnValue;
        return  @{@"__obj": box, @"__clsName": clsName};
    };
    
    context[@"toOCNumber"] = ^ id (JSValue *value) {
        id obj = [value toObject];
        if (!obj || ![obj isKindOfClass:[NSNumber class]]) {
            return nil;
        }
        JPBoxing *box = [[JPBoxing alloc] init];
        box.obj = obj;
        return  @{@"__obj": box, @"__clsName": NSStringFromClass([obj class])};
    };
    
    context[@"toJSNumber"] = ^ NSNumber *(JSValue *value) {
        NSDictionary *dict = [value toDictionary];
        if (dict) {
            return [(JPBoxing *)dict[@"__obj"] unbox];
        }
        return 0;
    };
}

@end
