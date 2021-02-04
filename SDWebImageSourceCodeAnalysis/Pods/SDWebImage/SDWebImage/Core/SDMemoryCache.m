/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDMemoryCache.h"
#import "SDImageCacheConfig.h"
#import "UIImage+MemoryCacheCost.h"
#import "SDInternalMacros.h"

static void * SDMemoryCacheContext = &SDMemoryCacheContext;

@interface SDMemoryCache <KeyType, ObjectType> () {
#if SD_UIKIT
    // 多线程锁保证多线程环境下weakCache数据安全
    SD_LOCK_DECLARE(_weakCacheLock);
#endif
}

@property (nonatomic, strong, nullable) SDImageCacheConfig *config;
#if SD_UIKIT
// 弱引用表
@property (nonatomic, strong, nonnull) NSMapTable<KeyType, ObjectType> *weakCache;
#endif
@end

@implementation SDMemoryCache

- (void)dealloc {
    [_config removeObserver:self forKeyPath:NSStringFromSelector(@selector(maxMemoryCost)) context:SDMemoryCacheContext];
    [_config removeObserver:self forKeyPath:NSStringFromSelector(@selector(maxMemoryCount)) context:SDMemoryCacheContext];
#if SD_UIKIT
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
#endif
    self.delegate = nil;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _config = [[SDImageCacheConfig alloc] init];
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithConfig:(SDImageCacheConfig *)config
{
    self = [super init];
    if (self)
    {
        _config = config;
        [self commonInit];
    }
    return self;
}

- (void)commonInit
{
    SDImageCacheConfig *config = self.config;
    self.totalCostLimit = config.maxMemoryCost;
    self.countLimit = config.maxMemoryCount;

    [config addObserver:self forKeyPath:NSStringFromSelector(@selector(maxMemoryCost)) options:0 context:SDMemoryCacheContext];
    [config addObserver:self forKeyPath:NSStringFromSelector(@selector(maxMemoryCount)) options:0 context:SDMemoryCacheContext];

#if SD_UIKIT
    // 初始化弱引用表
    // 当收到内存警告，内存缓存虽然被清理，但是有些图片已经被其他对象强引用着，这时weakCache维持这些图片的弱引用，如果需要获取这些图片就不用去硬盘获取了
    //NSPointerFunctionsWeakMemory，对值进行弱引用，不会对引用计数+1
    self.weakCache = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsWeakMemory capacity:0];
    SD_LOCK_INIT(_weakCacheLock);

    // 监听内存警告通知
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didReceiveMemoryWarning:)
                                                 name:UIApplicationDidReceiveMemoryWarningNotification
                                               object:nil];
#endif
}

#if SD_UIKIT
// 当收到内存警告通知，移除内存中缓存的图片
- (void)didReceiveMemoryWarning:(NSNotification *)notification
{
    // 仅仅移除内存中缓存的图片，仍然保留weakCache，维持对被强引用着的图片的访问
    [super removeAllObjects];
}

// SDMemoryCache继承自NSCache
// NSCache可以设置totalCostLimit来限制缓存的总成本消耗
// 所以我们在添加缓存的时候需要通过cost来指定缓存对象消耗的成本
// SDImageCache用图片的像素点（宽*高*缩放比例）来计算图片的消耗成本
- (void)setObject:(id)obj forKey:(id)key cost:(NSUInteger)g
{
    [super setObject:obj forKey:key cost:g];
    
    if (!self.config.shouldUseWeakMemoryCache)
    {
        return;
    }
    
    if (key && obj)
    {
        // 存入弱引用表
        SD_LOCK(_weakCacheLock);
        [self.weakCache setObject:obj forKey:key];
        SD_UNLOCK(_weakCacheLock);
    }
}

- (id)objectForKey:(id)key
{
    id obj = [super objectForKey:key];
    if (!self.config.shouldUseWeakMemoryCache)
    {
        return obj;
    }
    if (key && !obj)
    {
        // 检查弱引用表
        SD_LOCK(_weakCacheLock);
        obj = [self.weakCache objectForKey:key];
        SD_UNLOCK(_weakCacheLock);
        if (obj)
        {
            // 把通过弱引用表获取的图片添加到内存缓存中
            NSUInteger cost = 0;
            if ([obj isKindOfClass:[UIImage class]]) {
                cost = [(UIImage *)obj sd_memoryCost];
            }
            [super setObject:obj forKey:key cost:cost];
        }
    }
    return obj;
}

- (void)removeObjectForKey:(id)key {
    [super removeObjectForKey:key];
    if (!self.config.shouldUseWeakMemoryCache) {
        return;
    }
    if (key) {
        // Remove weak cache
        SD_LOCK(_weakCacheLock);
        [self.weakCache removeObjectForKey:key];
        SD_UNLOCK(_weakCacheLock);
    }
}

- (void)removeAllObjects {
    [super removeAllObjects];
    if (!self.config.shouldUseWeakMemoryCache) {
        return;
    }
    // Manually remove should also remove weak cache
    SD_LOCK(_weakCacheLock);
    [self.weakCache removeAllObjects];
    SD_UNLOCK(_weakCacheLock);
}
#endif

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (context == SDMemoryCacheContext) {
        if ([keyPath isEqualToString:NSStringFromSelector(@selector(maxMemoryCost))]) {
            self.totalCostLimit = self.config.maxMemoryCost;
        } else if ([keyPath isEqualToString:NSStringFromSelector(@selector(maxMemoryCount))]) {
            self.countLimit = self.config.maxMemoryCount;
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

@end




 
