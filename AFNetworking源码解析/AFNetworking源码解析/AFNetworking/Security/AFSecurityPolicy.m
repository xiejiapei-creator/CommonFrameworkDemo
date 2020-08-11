// AFSecurityPolicy.m
// Copyright (c) 2011–2016 Alamofire Software Foundation ( http://alamofire.org/ )
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "AFSecurityPolicy.h"

#import <AssertMacros.h>

// 将key转为data
#if !TARGET_OS_IOS && !TARGET_OS_WATCH && !TARGET_OS_TV
static NSData * AFSecKeyGetData(SecKeyRef key) {
    CFDataRef data = NULL;

    __Require_noErr_Quiet(SecItemExport(key, kSecFormatUnknown, kSecItemPemArmour, NULL, &data), _out);

    return (__bridge_transfer NSData *)data;

_out:
    if (data) {
        CFRelease(data);
    }

    return nil;
}
#endif
//这个方法是比较两个key是否相等，如果是ios/watch/tv直接使用isEqual方法判断二者地址就可进行比较
//判断两个公钥是否相同
static BOOL AFSecKeyIsEqualToKey(SecKeyRef key1, SecKeyRef key2) {
#if TARGET_OS_IOS || TARGET_OS_WATCH || TARGET_OS_TV
    //iOS 判断二者地址
    return [(__bridge id)key1 isEqual:(__bridge id)key2];
#else
    return [AFSecKeyGetData(key1) isEqual:AFSecKeyGetData(key2)];
#endif
}
// 此函数没什么特别要提及的，和AFPublicKeyTrustChainForServerTrust实现的原理基本一致
// 区别仅仅在该函数是返回单个证书的公钥（所以传入的参数是一个证书），而AFPublicKeyTrustChainForServerTrust返回的是serverTrust的证书链中所有证书公钥
static id AFPublicKeyForCertificate(NSData *certificate) {
    id allowedPublicKey = nil;
    SecCertificateRef allowedCertificate;
    SecCertificateRef allowedCertificates[1];
    CFArrayRef tempCertificates = nil;
    SecPolicyRef policy = nil;
    SecTrustRef allowedTrust = nil;
    SecTrustResultType result;
    // 1. 根据二进制的certificate生成SecCertificateRef类型的证书
    // NSData *certificate 通过CoreFoundation (__bridge CFDataRef)转换成 CFDataRef
    allowedCertificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificate);
    // 2.如果allowedCertificate为空，则执行标记_out后边的代码
    __Require_Quiet(allowedCertificate != NULL, _out);

    
    allowedCertificates[0] = allowedCertificate;
    tempCertificates = CFArrayCreate(NULL, (const void **)allowedCertificates, 1, NULL);
// 新建policy为X.509
    policy = SecPolicyCreateBasicX509();
    // 创建SecTrustRef对象，如果出错就跳到_out标记处
    __Require_noErr_Quiet(SecTrustCreateWithCertificates(tempCertificates, policy, &allowedTrust), _out);
    // 校验证书是否可信任的过程，这个不是异步的。
    __Require_noErr_Quiet(SecTrustEvaluate(allowedTrust, &result), _out);
    // 在SecTrustRef对象中取出公钥
    allowedPublicKey = (__bridge_transfer id)SecTrustCopyPublicKey(allowedTrust);

_out:
    if (allowedTrust) {
        CFRelease(allowedTrust);
    }

    if (policy) {
        CFRelease(policy);
    }

    if (tempCertificates) {
        CFRelease(tempCertificates);
    }

    if (allowedCertificate) {
        CFRelease(allowedCertificate);
    }

    
    /*
     ① NSData *certificate -> CFDataRef -> (SecCertificateCreateWithData) -> SecCertificateRef allowedCertificate
     
     ②判断SecCertificateRef allowedCertificate 是不是空，如果为空，直接跳转到后边的代码
     
     ③SecTrustCreateWithCertificates(allowedCertificate, policy, &allowedTrust) -> 生成SecTrustRef allowedTrust
     
     ④SecTrustEvaluate(allowedTrust, &result) 校验证书
     
     ⑤(__bridge_transfer id)SecTrustCopyPublicKey(allowedTrust) -> 得到公钥id allowedPublicKey
     */
    return allowedPublicKey;
}
// 判断serverTrust是否有效，即返回的服务器是否是可信任的
static BOOL AFServerTrustIsValid(SecTrustRef serverTrust) {
    //默认无效
    BOOL isValid = NO;
    //用来装验证结果，枚举
    SecTrustResultType result;
    
    //__Require_noErr_Quiet 用来判断前者是0还是非0，如果0则表示没错，就跳到后面的表达式所在位置去执行，否则表示有错就继续往下执行
    //SecTrustEvaluate系统用于评估证书是否可信的函数，去系统根目录找，然后把结果赋值给result。评估结果匹配，返回0，否则出错返回非0
    __Require_noErr_Quiet(SecTrustEvaluate(serverTrust, &result), _out);

    /* 比如有些弹窗，用户点击了信任
     1.评估得到了用户认可，显示地决定信任该证书，result 成功是 kSecTrustResultProceed 失败是kSecTrustResultDeny
     2.系统隐式地信任这个证书，result 成功是 kSecTrustResultUnspecified 失败是kSecTrustResultRecoverableTrustFailure
     */
    // 只有两种结果能设置为有效，isValid = 1
    isValid = (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);
    
    //out函数块，如果为SecTrustEvaluate，返回非0，则评估出错，则isValid为NO
_out:
    return isValid;
}
//获取证书链
//获取服务器返回的所有证书
static NSArray * AFCertificateTrustChainForServerTrust(SecTrustRef serverTrust) {
    //使用SecTrustGetCertificateCount函数获取到serverTrust中需要评估的证书链中的证书数目，并保存到certificateCount中
    CFIndex certificateCount = SecTrustGetCertificateCount(serverTrust);
    
    //创建数组
    //根据SecTrustRef中的信息得到count
    NSMutableArray *trustChain = [NSMutableArray arrayWithCapacity:(NSUInteger)certificateCount];
    
    //使用SecTrustGetCertificateAtIndex函数获取到证书链中的每个证书，并添加到trustChain中，最后返回trustChain
    for (CFIndex i = 0; i < certificateCount; i++) {
        //取到对应的SecCertificateRef
        SecCertificateRef certificate = SecTrustGetCertificateAtIndex(serverTrust, i);
        //转为data
        [trustChain addObject:(__bridge_transfer NSData *)SecCertificateCopyData(certificate)];
    }

    return [NSArray arrayWithArray:trustChain];
}
// 取出所有证书中的公钥
// 从serverTrust中取出服务器端传过来的所有可用的证书，并依次得到相应的公钥
static NSArray * AFPublicKeyTrustChainForServerTrust(SecTrustRef serverTrust) {
    //接下来的一小段代码和上面AFCertificateTrustChainForServerTrust函数的作用基本一致，都是为了获取到serverTrust中证书链上的所有证书，并依次遍历，取出公钥
    
    //安全策略
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    //取到count
    CFIndex certificateCount = SecTrustGetCertificateCount(serverTrust);
    
    NSMutableArray *trustChain = [NSMutableArray arrayWithCapacity:(NSUInteger)certificateCount];
    //遍历serverTrust里证书的证书链
    for (CFIndex i = 0; i < certificateCount; i++) {
        //从证书链取证书
        SecCertificateRef certificate = SecTrustGetCertificateAtIndex(serverTrust, i);
        //数组
        SecCertificateRef someCertificates[] = {certificate};
        //CF数组
        CFArrayRef certificates = CFArrayCreate(NULL, (const void **)someCertificates, 1, NULL);
        
        //到了取出公钥的步骤了
        
        //根据给定的certificates和policy来生成一个trust对象
        //不成功就跳到_out
        SecTrustRef trust;
        __Require_noErr_Quiet(SecTrustCreateWithCertificates(certificates, policy, &trust), _out);

        //使用SecTrustEvaluate来评估上面构建的trust
        //评估失败跳到 _out
        SecTrustResultType result;
        __Require_noErr_Quiet(SecTrustEvaluate(trust, &result), _out);
        
        //如果该trust符合X.509证书格式，那么先使用SecTrustCopyPublicKey获取到trust的公钥，再将此公钥添加到trustChain中
        [trustChain addObject:(__bridge_transfer id)SecTrustCopyPublicKey(trust)];

    _out:
        //释放资源
        if (trust) {
            CFRelease(trust);
        }

        if (certificates) {
            CFRelease(certificates);
        }

        continue;
    }
    CFRelease(policy);
    
    // 返回对应的一组公钥
    return [NSArray arrayWithArray:trustChain];
}

#pragma mark -

@interface AFSecurityPolicy()
// SSL验证模式
@property (readwrite, nonatomic, assign) AFSSLPinningMode SSLPinningMode;
// 公钥集合
@property (readwrite, nonatomic, strong) NSSet *pinnedPublicKeys;
@end

@implementation AFSecurityPolicy
// 获取bundle下的所有证书集合
+ (NSSet *)certificatesInBundle:(NSBundle *)bundle {
    // bundle下 所有的cer文件
    NSArray *paths = [bundle pathsForResourcesOfType:@"cer" inDirectory:@"."];

    NSMutableSet *certificates = [NSMutableSet setWithCapacity:[paths count]];
    for (NSString *path in paths) {
        // 得到data
        NSData *certificateData = [NSData dataWithContentsOfFile:path];
        // 加入到集合中
        [certificates addObject:certificateData];
    }

    return [NSSet setWithSet:certificates];
}
// zip
// 获得APP下的所有证书
+ (NSSet *)defaultPinnedCertificates {
    static NSSet *_defaultPinnedCertificates = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 得到当前的app bundle
        NSBundle *bundle = [NSBundle bundleForClass:[self class]];
        // 调用上面的方法
        _defaultPinnedCertificates = [self certificatesInBundle:bundle];
    });

    return _defaultPinnedCertificates;
}
// 创建默认的实例
+ (instancetype)defaultPolicy {
    AFSecurityPolicy *securityPolicy = [[self alloc] init];
    securityPolicy.SSLPinningMode = AFSSLPinningModeNone;// CA

    return securityPolicy;
}
// 根据指定的SSL验证模式创建实例
+ (instancetype)policyWithPinningMode:(AFSSLPinningMode)pinningMode {
    return [self policyWithPinningMode:pinningMode withPinnedCertificates:[self defaultPinnedCertificates]];
}
// 根据SSL验证模式和指定的证书集合创建实例
+ (instancetype)policyWithPinningMode:(AFSSLPinningMode)pinningMode withPinnedCertificates:(NSSet *)pinnedCertificates {
    AFSecurityPolicy *securityPolicy = [[self alloc] init];
    securityPolicy.SSLPinningMode = pinningMode;
    // 设置证书集合 如果是默认的 已经通过[self defaultPinnedCertificates]得到了
    [securityPolicy setPinnedCertificates:pinnedCertificates];

    return securityPolicy;
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    // 默认验证证书中的域名
    self.validatesDomainName = YES;

    return self;
}
// 此函数设置securityPolicy中的pinnedCertificates属性
// 注意还将对应的self.pinnedPublicKeys属性也设置了，该属性表示的是对应证书的公钥（与pinnedCertificates中的证书是一一对应的）
- (void)setPinnedCertificates:(NSSet *)pinnedCertificates {
    _pinnedCertificates = pinnedCertificates;
    
    //获取对应公钥集合
    if (self.pinnedCertificates) {
        //创建公钥集合
        NSMutableSet *mutablePinnedPublicKeys = [NSMutableSet setWithCapacity:[self.pinnedCertificates count]];
        
        //从证书中拿到公钥。
        for (NSData *certificate in self.pinnedCertificates) {
            id publicKey = AFPublicKeyForCertificate(certificate);
            if (!publicKey) {
                continue;
            }
            [mutablePinnedPublicKeys addObject:publicKey];
        }
        self.pinnedPublicKeys = [NSSet setWithSet:mutablePinnedPublicKeys];
    } else {
        self.pinnedPublicKeys = nil;
    }
}

#pragma mark -
//验证服务端是否值得信任
/*
 SecTrustRef:其实就是一个容器，装了服务器端需要验证的证书的基本信息、公钥等等，不仅如此，它还可以装一些评估策略，还有客户端的锚点证书，这个客户端的证书，可以用来和服务端的证书去匹配验证的。
 每一个SecTrustRef对象包含多个SecCertificateRef 和 SecPolicyRef。其中 SecCertificateRef 可以使用 DER 进行表示。
 domain:服务器域名，用于域名验证

 */
// 根据severTrust和domain来检查服务器端发来的证书是否可信
// 其中SecTrustRef是一个CoreFoundation类型，用于对服务器端传来的X.509证书评估的
// 而我们都知道，数字证书的签发机构CA，在接收到申请者的资料后进行核对并确定信息的真实有效，然后就会制作一份符合X.509标准的文件。证书中的证书内容包含的持有者信息和公钥等都是由申请者提供的，而数字签名则是CA机构对证书内容进行hash加密后得到的，而这个数字签名就是我们验证证书是否是有可信CA签发的数据。
- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust
                  forDomain:(NSString *)domain
{

    //后两者和allowInvalidCertificates为真的设置矛盾，说明这次验证是不安全的
    //如果有服务器域名、设置了允许信任无效或者过期证书（自签名证书）、需要验证域名、没有提供证书或者不验证证书，返回NO
    //因为要验证域名，所以必须不能是后者两种：AFSSLPinningModeNone或者添加到项目里的证书为0个
    if (domain && self.allowInvalidCertificates && self.validatesDomainName && (self.SSLPinningMode == AFSSLPinningModeNone || [self.pinnedCertificates count] == 0)) {
        
        //如果想要实现自签名的HTTPS访问成功，必须设置pinnedCertificates，且不能使用defaultPolicy
        NSLog(@"In order to val idate a domain name for self signed certificates, you MUST use pinning.");
        //不受信任，返回
        return NO;
    }
    
    //用来装验证策略
    NSMutableArray *policies = [NSMutableArray array];
    //生成验证策略。如果要验证域名，就以域名为参数创建一个策略，否则创建默认的basicX509策略
    if (self.validatesDomainName) {
        //如果需要验证domain，那么就使用SecPolicyCreateSSL函数创建验证策略
        //其中第一个参数为true表示为服务器证书验证创建一个策略，需要验证整个SSL证书链
        //第二个参数传入domain，用于判断整个证书链上叶子节点表示的那个domain是否和此处传入domain一致，即匹配主机名和证书上的主机名
        //1.__bridge:CF和OC对象转化时只涉及对象类型不涉及对象所有权的转化
        //2.__bridge_transfer:常用在讲CF对象转换成OC对象时，将CF对象的所有权交给OC对象，此时ARC就能自动管理该内存
        //3.__bridge_retained:（与__bridge_transfer相反）常用在将OC对象转换成CF对象时，将OC对象的所有权交给CF对象来管理
        [policies addObject:(__bridge_transfer id)SecPolicyCreateSSL(true, (__bridge CFStringRef)domain)];
    } else {
        //如果不需要验证domain，就使用默认的BasicX509验证策略
        [policies addObject:(__bridge_transfer id)SecPolicyCreateBasicX509()];
    }

    // 为serverTrust设置验证策略，用策略对serverTrust进行评估
    SecTrustSetPolicies(serverTrust, (__bridge CFArrayRef)policies);

    //如果是AFSSLPinningModeNone（不做本地证书验证，从客户端系统中的受信任颁发机构 CA 列表中去验证服务端返回的证书）
    if (self.SSLPinningMode == AFSSLPinningModeNone) {
        //不使用ssl pinning 但允许自建证书，直接返回YES；否则进行第二个条件判断，去客户端系统根证书里找是否有匹配的证书，验证serverTrust是否可信，直接返回YES
        return self.allowInvalidCertificates || AFServerTrustIsValid(serverTrust);
    } else if (!AFServerTrustIsValid(serverTrust) && !self.allowInvalidCertificates) {
        //如果验证无效AFServerTrustIsValid，而且allowInvalidCertificates不允许自签，返回NO
        return NO;
    }

    //判断SSLPinningMode
    switch (self.SSLPinningMode) {
        //上一部分已经判断过了，如果执行到这里的话就返回NO
        case AFSSLPinningModeNone:
        default:
            return NO;
        
        //验证证书类型
        //这个模式表示用证书绑定(SSL Pinning)方式验证证书，需要客户端保存有服务端的证书拷贝
        //注意客户端保存的证书存放在self.pinnedCertificates中
        case AFSSLPinningModeCertificate: {
            
            // 全部校验（nsbundle .cer）
            NSMutableArray *pinnedCertificates = [NSMutableArray array];
            
            //把证书data，用系统api转成 SecCertificateRef 类型的数据
            //SecCertificateCreateWithData函数对原先的pinnedCertificates做一些处理，保证返回的证书都是DER编码的X.509证书
            for (NSData *certificateData in self.pinnedCertificates) {
                //cf arc brige：cf对象和oc对象转化 __bridge_transfer：把cf对象转化成oc对象
                //brige retain:oc转成cf对象
                [pinnedCertificates addObject:(__bridge_transfer id)SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateData)];
            }
            
            //将pinnedCertificates设置成需要参与验证的Anchor Certificate锚点证书
            //通过SecTrustSetAnchorCertificates设置了参与校验锚点证书之后
            //假如验证的数字证书是这个锚点证书的子节点，即验证的数字证书是由锚点证书对应CA或子CA签发的，或是该证书本身，则信任该证书
            //具体就是调用SecTrustEvaluate来验证
            //serverTrust是服务器来的验证，有需要被验证的证书
            //把本地证书设置为根证书
            SecTrustSetAnchorCertificates(serverTrust, (__bridge CFArrayRef)pinnedCertificates);
            
            //自签在之前是验证通过不了的，在这一步，把我们自己设置的证书加进去之后，就能验证成功了。
            //再去调用之前的serverTrust去验证该证书是否有效，有可能：经过这个方法过滤后，serverTrust里面的pinnedCertificates被筛选到只有信任的那一个证书
            //评估指定证书和策略的信任度（由系统默认可信或者由用户选择可信）
            if (!AFServerTrustIsValid(serverTrust)) {
                return NO;
            }

            //注意，这个方法和我们之前的锚点证书没关系了，是去从我们需要被验证的服务端证书，去拿证书链。
            //服务器端的证书链，注意此处返回的证书链顺序是从叶节点到根节点
            //所有服务器返回的证书信息
            NSArray *serverCertificates = AFCertificateTrustChainForServerTrust(serverTrust);
            
            //reverseObjectEnumerator逆序遍历
            //服务器端的证书链，注意此处返回的证书链顺序是从叶节点到根节点
            //证书链由两个环节组成—信任锚（CA 证书）环节和已签名证书环节，就是根证书和根据根证书签名派发得到的证书
            for (NSData *trustChainCertificate in [serverCertificates reverseObjectEnumerator]) {
                //如果我们的证书中，有一个和它证书链中的证书匹配的，就返回YES
                //是否本地包含相同的data
                if ([self.pinnedCertificates containsObject:trustChainCertificate]) {
                    return YES;
                }
            }
            //没有匹配的
            return NO;
        }
            
        //公钥验证 AFSSLPinningModePublicKey模式同样是用证书绑定(SSL Pinning)方式验证，客户端要有服务端的证书拷贝
        //只是验证时只验证证书里的公钥，不验证证书的有效期等信息
        //只要公钥是正确的，就能保证通信不会被窃听，因为中间人没有私钥，无法解开通过公钥加密的数据
        case AFSSLPinningModePublicKey: {
            NSUInteger trustedPublicKeyCount = 0;
            
            // 从serverTrust中取出服务器端传过来的所有可用的证书，并依次得到相应的公钥，即从serverTrust获取证书链
            NSArray *publicKeys = AFPublicKeyTrustChainForServerTrust(serverTrust);
            //遍历服务端公钥
            for (id trustChainPublicKey in publicKeys) {
                //遍历本地公钥
                for (id pinnedPublicKey in self.pinnedPublicKeys) {
                    //判断如果相同 trustedPublicKeyCount+1
                    if (AFSecKeyIsEqualToKey((__bridge SecKeyRef)trustChainPublicKey, (__bridge SecKeyRef)pinnedPublicKey)) {
                        trustedPublicKeyCount += 1;
                    }
                }
            }
            // 如果有一个相同的，就返回YES，配对成功
            return trustedPublicKeyCount > 0;
        }
    }
    
    return NO;
}

#pragma mark - NSKeyValueObserving

+ (NSSet *)keyPathsForValuesAffectingPinnedPublicKeys {
    return [NSSet setWithObject:@"pinnedCertificates"];
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)decoder {

    self = [self init];
    if (!self) {
        return nil;
    }

    self.SSLPinningMode = [[decoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(SSLPinningMode))] unsignedIntegerValue];
    self.allowInvalidCertificates = [decoder decodeBoolForKey:NSStringFromSelector(@selector(allowInvalidCertificates))];
    self.validatesDomainName = [decoder decodeBoolForKey:NSStringFromSelector(@selector(validatesDomainName))];
    self.pinnedCertificates = [decoder decodeObjectOfClass:[NSArray class] forKey:NSStringFromSelector(@selector(pinnedCertificates))];

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:[NSNumber numberWithUnsignedInteger:self.SSLPinningMode] forKey:NSStringFromSelector(@selector(SSLPinningMode))];
    [coder encodeBool:self.allowInvalidCertificates forKey:NSStringFromSelector(@selector(allowInvalidCertificates))];
    [coder encodeBool:self.validatesDomainName forKey:NSStringFromSelector(@selector(validatesDomainName))];
    [coder encodeObject:self.pinnedCertificates forKey:NSStringFromSelector(@selector(pinnedCertificates))];
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone {
    AFSecurityPolicy *securityPolicy = [[[self class] allocWithZone:zone] init];
    securityPolicy.SSLPinningMode = self.SSLPinningMode;
    securityPolicy.allowInvalidCertificates = self.allowInvalidCertificates;
    securityPolicy.validatesDomainName = self.validatesDomainName;
    securityPolicy.pinnedCertificates = [self.pinnedCertificates copyWithZone:zone];

    return securityPolicy;
}

@end
