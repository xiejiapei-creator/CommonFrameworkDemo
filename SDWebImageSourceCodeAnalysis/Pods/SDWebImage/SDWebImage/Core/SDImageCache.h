/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>
#import "SDWebImageCompat.h"
#import "SDWebImageDefine.h"
#import "SDImageCacheConfig.h"
#import "SDImageCacheDefine.h"
#import "SDMemoryCache.h"
#import "SDDiskCache.h"

// 缓存图片的方式
typedef NS_OPTIONS(NSUInteger, SDImageCacheOptions)
{
    // 当内存有图片，查询内存缓存
    SDImageCacheQueryMemoryData = 1 << 0,

    // 同步的方式来获取内存缓存(默认异步)
    SDImageCacheQueryMemoryDataSync = 1 << 1,

    // 同步的方式来获取硬盘缓存(默认异步)
    SDImageCacheQueryDiskDataSync = 1 << 2,

    // 缩小大图(>60M)
    SDImageCacheScaleDownLargeImages = 1 << 3,

    // 避免解码图片
    SDImageCacheAvoidDecodeImage = 1 << 4,

    SDImageCacheDecodeFirstFrameOnly = 1 << 5,
    SDImageCachePreloadAllFrames = 1 << 6,
    SDImageCacheMatchAnimatedImageClass = 1 << 7,
};

@interface SDImageCache : NSObject

#pragma mark - Properties

// 缓存策略配置对象
@property (nonatomic, copy, nonnull, readonly) SDImageCacheConfig *config;

// 使用SDMemoryCache(继承自NSCache)来实现内存缓存
@property (nonatomic, strong, readonly, nonnull) id<SDMemoryCache> memoryCache;

// 使用SDDiskCache来实现磁盘缓存
@property (nonatomic, strong, readonly, nonnull) id<SDDiskCache> diskCache;

// 获取图片默认的磁盘缓存路径
@property (nonatomic, copy, nonnull, readonly) NSString *diskCachePath;

@property (nonatomic, copy, nullable) SDImageCacheAdditionalCachePathBlock additionalCachePathBlock;

#pragma mark - Singleton and initialization

// 暴露的单例对象
@property (nonatomic, class, readonly, nonnull) SDImageCache *sharedImageCache;

// 默认的磁盘缓存目录
@property (nonatomic, class, readwrite, null_resettable) NSString *defaultDiskCacheDirectory;

// 指定命名空间，图片存到对应的沙盒目录中
- (nonnull instancetype)initWithNamespace:(nonnull NSString *)ns;

// 指定命名空间和沙盒目录
- (nonnull instancetype)initWithNamespace:(nonnull NSString *)ns
                       diskCacheDirectory:(nullable NSString *)directory;

// 指定命名空间、沙盒目录、缓存策略配置
- (nonnull instancetype)initWithNamespace:(nonnull NSString *)ns
                       diskCacheDirectory:(nullable NSString *)directory
                                   config:(nullable SDImageCacheConfig *)config NS_DESIGNATED_INITIALIZER;

#pragma mark - Cache paths

// 指定key，获取图片的缓存路径
- (nullable NSString *)cachePathForKey:(nullable NSString *)key;

#pragma mark - Store Ops

- (void)storeImage:(nullable UIImage *)image
            forKey:(nullable NSString *)key
        completion:(nullable SDWebImageNoParamsBlock)completionBlock;

// 异步缓存图片到内存和磁盘
- (void)storeImage:(nullable UIImage *)image
            forKey:(nullable NSString *)key
            toDisk:(BOOL)toDisk
        completion:(nullable SDWebImageNoParamsBlock)completionBlock;

- (void)storeImage:(nullable UIImage *)image
         imageData:(nullable NSData *)imageData
            forKey:(nullable NSString *)key
            toDisk:(BOOL)toDisk
        completion:(nullable SDWebImageNoParamsBlock)completionBlock;

// 把图片二进制数据存入内存
- (void)storeImageToMemory:(nullable UIImage*)image
                    forKey:(nullable NSString *)key;

// 把图片二进制数据存入硬盘
- (void)storeImageDataToDisk:(nullable NSData *)imageData
                      forKey:(nullable NSString *)key;


#pragma mark - Contains and Check Ops

// 异步的方式查询硬盘中是否有key对应的缓存图片
- (void)diskImageExistsWithKey:(nullable NSString *)key completion:(nullable SDImageCacheCheckCompletionBlock)completionBlock;

// 同步的方式查询硬盘中是否有key对应的缓存图片
- (BOOL)diskImageDataExistsWithKey:(nullable NSString *)key;

#pragma mark - Query and Retrieve Ops

// 同步的方式获取硬盘缓存的图片二进制数据
- (nullable NSData *)diskImageDataForKey:(nullable NSString *)key;

// 异步的方式来获取硬盘缓存的图片二进制数据
- (void)diskImageDataQueryForKey:(nullable NSString *)key completion:(nullable SDImageCacheQueryDataCompletionBlock)completionBlock;

// 异步的方式来获取硬盘缓存的图片
- (nullable NSOperation *)queryCacheOperationForKey:(nullable NSString *)key done:(nullable SDImageCacheQueryCompletionBlock)doneBlock;

// 异步的方式来获取硬盘缓存的图片
- (nullable NSOperation *)queryCacheOperationForKey:(nullable NSString *)key options:(SDImageCacheOptions)options done:(nullable SDImageCacheQueryCompletionBlock)doneBlock;

- (nullable NSOperation *)queryCacheOperationForKey:(nullable NSString *)key options:(SDImageCacheOptions)options context:(nullable SDWebImageContext *)context done:(nullable SDImageCacheQueryCompletionBlock)doneBlock;

- (nullable NSOperation *)queryCacheOperationForKey:(nullable NSString *)key options:(SDImageCacheOptions)options context:(nullable SDWebImageContext *)context cacheType:(SDImageCacheType)queryCacheType done:(nullable SDImageCacheQueryCompletionBlock)doneBlock;

// 同步的方式来获取内存缓存的图片
- (nullable UIImage *)imageFromMemoryCacheForKey:(nullable NSString *)key;

// 同步的方式获取硬盘缓存的图片
- (nullable UIImage *)imageFromDiskCacheForKey:(nullable NSString *)key;

// 同步的方式，先查询内存中有没有缓存的图片，如果没有再查询硬盘中有没有缓存的图片
- (nullable UIImage *)imageFromCacheForKey:(nullable NSString *)key;

- (nullable UIImage *)imageFromDiskCacheForKey:(nullable NSString *)key options:(SDImageCacheOptions)options context:(nullable SDWebImageContext *)context;

- (nullable UIImage *)imageFromCacheForKey:(nullable NSString *)key options:(SDImageCacheOptions)options context:(nullable SDWebImageContext *)context;

#pragma mark - Remove Ops

// 异步的方式移除缓存中的图片，包括内存和硬盘
- (void)removeImageForKey:(nullable NSString *)key withCompletion:(nullable SDWebImageNoParamsBlock)completion;

// 异步的方式移除缓存中的图片，包括内存和硬盘(可选，fromDisk为YES移除硬盘缓存)
- (void)removeImageForKey:(nullable NSString *)key fromDisk:(BOOL)fromDisk withCompletion:(nullable SDWebImageNoParamsBlock)completion;

// 移除内存中的图片
- (void)removeImageFromMemoryForKey:(nullable NSString *)key;

// 移除磁盘中的图片
- (void)removeImageFromDiskForKey:(nullable NSString *)key;

#pragma mark - Cache clean Ops

// 清除内存缓存
- (void)clearMemory;

// 异步方式清除硬盘缓存
- (void)clearDiskOnCompletion:(nullable SDWebImageNoParamsBlock)completion;

// 异步方式清除过期的图片
- (void)deleteOldFilesWithCompletionBlock:(nullable SDWebImageNoParamsBlock)completionBlock;

#pragma mark - Cache Info

// 同步方式计算缓存目录的大小
- (NSUInteger)totalDiskSize;

// 同步方式计算缓存的图片数量
- (NSUInteger)totalDiskCount;

// 异步的方式获取缓存图片数量和大小
- (void)calculateSizeWithCompletionBlock:(nullable SDImageCacheCalculateSizeBlock)completionBlock;

@end

@interface SDImageCache (SDImageCache) <SDImageCache>

@end
