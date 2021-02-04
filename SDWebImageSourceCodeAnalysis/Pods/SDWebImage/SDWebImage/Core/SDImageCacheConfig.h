/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>
#import "SDWebImageCompat.h"

// 以什么方式来计算图片的过期时间
typedef NS_ENUM(NSUInteger, SDImageCacheConfigExpireType)
{
    // 图片最近访问的时间
    SDImageCacheConfigExpireTypeAccessDate,

    // 默认：图片最近修改的时间
    SDImageCacheConfigExpireTypeModificationDate,

    // 图片的创建时间
    SDImageCacheConfigExpireTypeCreationDate,
    
    /**
     * When the image cache is created, modified, renamed, file attribute updated (like permission, xattr)  it will update this value
     */
    SDImageCacheConfigExpireTypeChangeDate,
};

// 缓存策略配置对象
@interface SDImageCacheConfig : NSObject <NSCopying>

// 默认缓存策略配置
@property (nonatomic, class, readonly, nonnull) SDImageCacheConfig *defaultCacheConfig;

// 是否应该取消iCloud备份，默认是YES
@property (assign, nonatomic) BOOL shouldDisableiCloud;

// 是否使用内存缓存，默认是YES
@property (assign, nonatomic) BOOL shouldCacheImagesInMemory;

// 是否开启SDMemoryCache内部维护的一张图片弱引用表
// 开启的好处是当收到内存警告，SDMemoryCache会移除图片的缓存
@property (assign, nonatomic) BOOL shouldUseWeakMemoryCache;

// 在进入应用程序时是否删除过期的磁盘数据
@property (assign, nonatomic) BOOL shouldRemoveExpiredDataWhenEnterBackground;

// 硬盘图片读取的配置选项
@property (assign, nonatomic) NSDataReadingOptions diskCacheReadingOptions;

// 把图片存入硬盘的配置选项，默认NSDataWritingAtomic原子操作
@property (assign, nonatomic) NSDataWritingOptions diskCacheWritingOptions;

// 图片最大的缓存时间，默认1星期
// 在清除缓存的时候会先把缓存时间过期的图片清理掉再清除图片到总缓存大小在最大占用空间一半以下
@property (assign, nonatomic) NSTimeInterval maxDiskAge;

// 能够占用的最大磁盘空间
@property (assign, nonatomic) NSUInteger maxDiskSize;

// 能够占用的最大内存空间
@property (assign, nonatomic) NSUInteger maxMemoryCost;

// 缓存能够保存的key-value个数的最大数量
@property (assign, nonatomic) NSUInteger maxMemoryCount;

// 硬盘缓存图片过期时间的计算方式，默认是最近修改的时间
@property (assign, nonatomic) SDImageCacheConfigExpireType diskCacheExpireType;

// 存储图片到硬盘的文件管理者
@property (strong, nonatomic, nullable) NSFileManager *fileManager;

/**
 * The custom memory cache class. Provided class instance must conform to `SDMemoryCache` protocol to allow usage.
 * Defaults to built-in `SDMemoryCache` class.
 * @note This value does not support dynamic changes. Which means further modification on this value after cache initialized has no effect.
 */
@property (assign, nonatomic, nonnull) Class memoryCacheClass;

/**
 * The custom disk cache class. Provided class instance must conform to `SDDiskCache` protocol to allow usage.
 * Defaults to built-in `SDDiskCache` class.
 * @note This value does not support dynamic changes. Which means further modification on this value after cache initialized has no effect.
 */
@property (assign ,nonatomic, nonnull) Class diskCacheClass;

@end
