/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDDiskCache.h"
#import "SDImageCacheConfig.h"
#import "SDFileAttributeHelper.h"
#import <CommonCrypto/CommonDigest.h>

static NSString * const SDDiskCacheExtendedAttributeName = @"com.hackemist.SDDiskCache";

@interface SDDiskCache ()

@property (nonatomic, copy) NSString *diskCachePath;
// 存储图片到硬盘的文件管理者
@property (nonatomic, strong, nonnull) NSFileManager *fileManager;

@end

@implementation SDDiskCache

- (instancetype)init {
    NSAssert(NO, @"Use `initWithCachePath:` with the disk cache path");
    return nil;
}

#pragma mark - SDcachePathForKeyDiskCache Protocol
- (instancetype)initWithCachePath:(NSString *)cachePath config:(nonnull SDImageCacheConfig *)config {
    if (self = [super init]) {
        _diskCachePath = cachePath;
        _config = config;
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    if (self.config.fileManager) {
        self.fileManager = self.config.fileManager;
    } else {
        self.fileManager = [NSFileManager new];
    }
}

- (BOOL)containsDataForKey:(NSString *)key {
    NSParameterAssert(key);
    NSString *filePath = [self cachePathForKey:key];
    BOOL exists = [self.fileManager fileExistsAtPath:filePath];
    
    // fallback because of https://github.com/rs/SDWebImage/pull/976 that added the extension to the disk file name
    // checking the key with and without the extension
    if (!exists) {
        exists = [self.fileManager fileExistsAtPath:filePath.stringByDeletingPathExtension];
    }
    
    return exists;
}

- (NSData *)dataForKey:(NSString *)key {
    NSParameterAssert(key);
    NSString *filePath = [self cachePathForKey:key];
    NSData *data = [NSData dataWithContentsOfFile:filePath options:self.config.diskCacheReadingOptions error:nil];
    if (data) {
        return data;
    }
    
    // fallback because of https://github.com/rs/SDWebImage/pull/976 that added the extension to the disk file name
    // checking the key with and without the extension
    data = [NSData dataWithContentsOfFile:filePath.stringByDeletingPathExtension options:self.config.diskCacheReadingOptions error:nil];
    if (data) {
        return data;
    }
    
    return nil;
}

// 把图片资源存入磁盘
- (void)setData:(NSData *)data forKey:(NSString *)key
{
    NSParameterAssert(data);
    NSParameterAssert(key);
    
    // 如果还没有缓存目录，通过fileManager生成缓存目录
    if (![self.fileManager fileExistsAtPath:self.diskCachePath])
    {
        [self.fileManager createDirectoryAtPath:self.diskCachePath withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    
    // 获取key对应的完整缓存路径
    NSString *cachePathForKey = [self cachePathForKey:key];
    // 转换成URL
    NSURL *fileURL = [NSURL fileURLWithPath:cachePathForKey];
    // 把数据存入路径保存到硬盘
    [data writeToURL:fileURL options:self.config.diskCacheWritingOptions error:nil];
    
    // 禁止iCloud备份
    if (self.config.shouldDisableiCloud)
    {
        // 给文件添加到运行存储到iCloud属性
        [fileURL setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    }
}

- (NSData *)extendedDataForKey:(NSString *)key {
    NSParameterAssert(key);
    
    // get cache Path for image key
    NSString *cachePathForKey = [self cachePathForKey:key];
    
    NSData *extendedData = [SDFileAttributeHelper extendedAttribute:SDDiskCacheExtendedAttributeName atPath:cachePathForKey traverseLink:NO error:nil];
    
    return extendedData;
}

- (void)setExtendedData:(NSData *)extendedData forKey:(NSString *)key {
    NSParameterAssert(key);
    // get cache Path for image key
    NSString *cachePathForKey = [self cachePathForKey:key];
    
    if (!extendedData) {
        // Remove
        [SDFileAttributeHelper removeExtendedAttribute:SDDiskCacheExtendedAttributeName atPath:cachePathForKey traverseLink:NO error:nil];
    } else {
        // Override
        [SDFileAttributeHelper setExtendedAttribute:SDDiskCacheExtendedAttributeName value:extendedData atPath:cachePathForKey traverseLink:NO overwrite:YES error:nil];
    }
}

- (void)removeDataForKey:(NSString *)key {
    NSParameterAssert(key);
    NSString *filePath = [self cachePathForKey:key];
    [self.fileManager removeItemAtPath:filePath error:nil];
}

- (void)removeAllData {
    [self.fileManager removeItemAtPath:self.diskCachePath error:nil];
    [self.fileManager createDirectoryAtPath:self.diskCachePath
            withIntermediateDirectories:YES
                             attributes:nil
                                  error:NULL];
}

- (void)removeExpiredData
{
    // 获取磁盘缓存的默认根目录
    NSURL *diskCacheURL = [NSURL fileURLWithPath:self.diskCachePath isDirectory:YES];
    
    // Compute content date key to be used for tests
    NSURLResourceKey cacheContentDateKey = NSURLContentModificationDateKey;
    switch (self.config.diskCacheExpireType)
    {
        case SDImageCacheConfigExpireTypeAccessDate:
            cacheContentDateKey = NSURLContentAccessDateKey;
            break;
        case SDImageCacheConfigExpireTypeModificationDate:
            cacheContentDateKey = NSURLContentModificationDateKey;
            break;
        case SDImageCacheConfigExpireTypeCreationDate:
            cacheContentDateKey = NSURLCreationDateKey;
            break;
        case SDImageCacheConfigExpireTypeChangeDate:
            cacheContentDateKey = NSURLAttributeModificationDateKey;
            break;
        default:
            break;
    }
    
    NSArray<NSString *> *resourceKeys = @[NSURLIsDirectoryKey, cacheContentDateKey, NSURLTotalFileAllocatedSizeKey];
    
    // 创建文件迭代器
    // 第二个参数制定了需要获取的属性集合
    // 第三个参数表示不迭代隐藏文件
    NSDirectoryEnumerator *fileEnumerator = [self.fileManager enumeratorAtURL:diskCacheURL
                                               includingPropertiesForKeys:resourceKeys
                                                                  options:NSDirectoryEnumerationSkipsHiddenFiles
                                                             errorHandler:NULL];
    // 过期时间
    NSDate *expirationDate = (self.config.maxDiskAge < 0) ? nil: [NSDate dateWithTimeIntervalSinceNow:-self.config.maxDiskAge];
    NSMutableDictionary<NSURL *, NSDictionary<NSString *, id> *> *cacheFiles = [NSMutableDictionary dictionary];
    NSUInteger currentCacheSize = 0;
    

    // 删除比指定日期更老的图片
    // 记录文件的大小，以提供给后面删除使用
    NSMutableArray<NSURL *> *urlsToDelete = [[NSMutableArray alloc] init];
    for (NSURL *fileURL in fileEnumerator)
    {
        NSError *error;
        // 获取指定url对应文件
        NSDictionary<NSString *, id> *resourceValues = [fileURL resourceValuesForKeys:resourceKeys error:&error];
        
        // 如果是文件夹则返回
        if (error || !resourceValues || [resourceValues[NSURLIsDirectoryKey] boolValue])
        {
            continue;
        }
        
        // 获取指定url文件对应的修改日期
        NSDate *modifiedDate = resourceValues[cacheContentDateKey];
        // 如果修改日期大于指定日期，则加入要移除的数组里
        if (expirationDate && [[modifiedDate laterDate:expirationDate] isEqualToDate:expirationDate])
        {
            [urlsToDelete addObject:fileURL];
            continue;
        }
        
        // 获取指定的url对应的文件的大小，并且把url与对应大小存入一个字典中
        NSNumber *totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey];
        currentCacheSize += totalAllocatedSize.unsignedIntegerValue;
        cacheFiles[fileURL] = resourceValues;
    }
    
    // 删除所有最后修改日期大于指定日期的所有文件
    for (NSURL *fileURL in urlsToDelete)
    {
        [self.fileManager removeItemAtURL:fileURL error:nil];
    }
    
    // 如果我们当前缓存的大小超过了默认大小，则按照日期删除，直到缓存大小<默认大小的一半
    NSUInteger maxDiskSize = self.config.maxDiskSize;
    if (maxDiskSize > 0 && currentCacheSize > maxDiskSize)
    {
        const NSUInteger desiredCacheSize = maxDiskSize / 2;
        
        // 根据文件创建的时间排序
        NSArray<NSURL *> *sortedFiles = [cacheFiles keysSortedByValueWithOptions:NSSortConcurrent
                                                                 usingComparator:^NSComparisonResult(id obj1, id obj2) {
                                                                     return [obj1[cacheContentDateKey] compare:obj2[cacheContentDateKey]];
                                                                 }];
        
        // 迭代删除缓存，直到缓存大小是默认缓存大小的一半
        for (NSURL *fileURL in sortedFiles)
        {
            if ([self.fileManager removeItemAtURL:fileURL error:nil])
            {
                NSDictionary<NSString *, id> *resourceValues = cacheFiles[fileURL];
                NSNumber *totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey];
                
                // 总的缓存大小减去当前要删除文件的大小
                currentCacheSize -= totalAllocatedSize.unsignedIntegerValue;
                
                if (currentCacheSize < desiredCacheSize)
                {
                    break;
                }
            }
        }
    }
}

- (nullable NSString *)cachePathForKey:(NSString *)key {
    NSParameterAssert(key);
    return [self cachePathForKey:key inPath:self.diskCachePath];
}

- (NSUInteger)totalSize {
    NSUInteger size = 0;
    NSDirectoryEnumerator *fileEnumerator = [self.fileManager enumeratorAtPath:self.diskCachePath];
    for (NSString *fileName in fileEnumerator) {
        NSString *filePath = [self.diskCachePath stringByAppendingPathComponent:fileName];
        NSDictionary<NSString *, id> *attrs = [self.fileManager attributesOfItemAtPath:filePath error:nil];
        size += [attrs fileSize];
    }
    return size;
}

- (NSUInteger)totalCount {
    NSUInteger count = 0;
    NSDirectoryEnumerator *fileEnumerator = [self.fileManager enumeratorAtPath:self.diskCachePath];
    count = fileEnumerator.allObjects.count;
    return count;
}

#pragma mark - Cache paths

- (nullable NSString *)cachePathForKey:(nullable NSString *)key inPath:(nonnull NSString *)path {
    NSString *filename = SDDiskCacheFileNameForKey(key);
    return [path stringByAppendingPathComponent:filename];
}

- (void)moveCacheDirectoryFromPath:(nonnull NSString *)srcPath toPath:(nonnull NSString *)dstPath {
    NSParameterAssert(srcPath);
    NSParameterAssert(dstPath);
    // Check if old path is equal to new path
    if ([srcPath isEqualToString:dstPath]) {
        return;
    }
    BOOL isDirectory;
    // Check if old path is directory
    if (![self.fileManager fileExistsAtPath:srcPath isDirectory:&isDirectory] || !isDirectory) {
        return;
    }
    // Check if new path is directory
    if (![self.fileManager fileExistsAtPath:dstPath isDirectory:&isDirectory] || !isDirectory) {
        if (!isDirectory) {
            // New path is not directory, remove file
            [self.fileManager removeItemAtPath:dstPath error:nil];
        }
        NSString *dstParentPath = [dstPath stringByDeletingLastPathComponent];
        // Creates any non-existent parent directories as part of creating the directory in path
        if (![self.fileManager fileExistsAtPath:dstParentPath]) {
            [self.fileManager createDirectoryAtPath:dstParentPath withIntermediateDirectories:YES attributes:nil error:NULL];
        }
        // New directory does not exist, rename directory
        [self.fileManager moveItemAtPath:srcPath toPath:dstPath error:nil];
    } else {
        // New directory exist, merge the files
        NSDirectoryEnumerator *dirEnumerator = [self.fileManager enumeratorAtPath:srcPath];
        NSString *file;
        while ((file = [dirEnumerator nextObject])) {
            [self.fileManager moveItemAtPath:[srcPath stringByAppendingPathComponent:file] toPath:[dstPath stringByAppendingPathComponent:file] error:nil];
        }
        // Remove the old path
        [self.fileManager removeItemAtPath:srcPath error:nil];
    }
}

#pragma mark - Hash

#define SD_MAX_FILE_EXTENSION_LENGTH (NAME_MAX - CC_MD5_DIGEST_LENGTH * 2 - 1)

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static inline NSString * _Nonnull SDDiskCacheFileNameForKey(NSString * _Nullable key)
{
    const char *str = key.UTF8String;
    if (str == NULL)
    {
        str = "";
    }
    
    // 计算key的md5值
    unsigned char r[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG)strlen(str), r);
    NSURL *keyURL = [NSURL URLWithString:key];
    NSString *ext = keyURL ? keyURL.pathExtension : key.pathExtension;
    
    if (ext.length > SD_MAX_FILE_EXTENSION_LENGTH)
    {
        ext = nil;
    }
    
    // md5值拼接文件后缀
    // X 表示以十六进制形式输出
    // 02 表示不足两位，前面补0输出；超过两位，不影响
    NSString *filename = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%@",
                          r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10],
                          r[11], r[12], r[13], r[14], r[15], ext.length == 0 ? @"" : [NSString stringWithFormat:@".%@", ext]];
    // 加密后的文件名
    return filename;
}
#pragma clang diagnostic pop

@end







