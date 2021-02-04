/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>
#import "SDWebImageDownloader.h"
#import "SDWebImageOperation.h"

// 开发者可以实现自己的下载操作只需要实现该协议即可
@protocol SDWebImageDownloaderOperation <NSURLSessionTaskDelegate, NSURLSessionDataDelegate>

@required
// 初始化函数，根据指定的request、session和下载选项创建一个下载任务
- (nonnull instancetype)initWithRequest:(nullable NSURLRequest *)request
                              inSession:(nullable NSURLSession *)session
                                options:(SDWebImageDownloaderOptions)options;

- (nonnull instancetype)initWithRequest:(nullable NSURLRequest *)request
                              inSession:(nullable NSURLSession *)session
                                options:(SDWebImageDownloaderOptions)options
                                context:(nullable SDWebImageContext *)context;
// 添加进度和完成后的回调块
- (nullable id)addHandlersForProgress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                            completed:(nullable SDWebImageDownloaderCompletedBlock)completedBlock;

- (BOOL)cancel:(nullable id)token;

@property (strong, nonatomic, readonly, nullable) NSURLRequest *request;
@property (strong, nonatomic, readonly, nullable) NSURLResponse *response;

@optional
@property (strong, nonatomic, readonly, nullable) NSURLSessionTask *dataTask;
@property (strong, nonatomic, readonly, nullable) NSURLSessionTaskMetrics *metrics API_AVAILABLE(macosx(10.12), ios(10.0), watchos(3.0), tvos(10.0));
@property (strong, nonatomic, nullable) NSURLCredential *credential;
@property (assign, nonatomic) double minimumProgressInterval;

@end

// SDWebImageDownloaderOperation类继承自NSOperation并遵守了SDWebImageDownloaderOperation协议
@interface SDWebImageDownloaderOperation : NSOperation <SDWebImageDownloaderOperation>

// 下载任务的request
@property (strong, nonatomic, readonly, nullable) NSURLRequest *request;

// 连接服务端后的收到的响应
@property (strong, nonatomic, readonly, nullable) NSURLResponse *response;

// 执行下载操作的下载任务
@property (strong, nonatomic, readonly, nullable) NSURLSessionTask *dataTask;

// https需要使用的凭证
@property (strong, nonatomic, nullable) NSURLCredential *credential;

// 下载时配置的相关内容
@property (assign, nonatomic, readonly) SDWebImageDownloaderOptions options;



// 初始化方法需要下载文件的request、session以及下载相关配置选项
- (nonnull instancetype)initWithRequest:(nullable NSURLRequest *)request
                              inSession:(nullable NSURLSession *)session
                                options:(SDWebImageDownloaderOptions)options;

// 添加一个进度回调块和下载完成后的回调块
// 返回一个token，用于取消这个下载任务，这个token其实是一个字典
- (nullable id)addHandlersForProgress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                            completed:(nullable SDWebImageDownloaderCompletedBlock)completedBlock;

// 这个方法不是用来取消下载任务的，而是删除前一个方法添加的进度回调块和下载完成回调块，当所有的回调块都删除后，下载任务也会被取消
// 需要传入上一个方法返回的token
- (BOOL)cancel:(nullable id)token;

/**
 * The collected metrics from `-URLSession:task:didFinishCollectingMetrics:`.
 * This can be used to collect the network metrics like download duration, DNS lookup duration, SSL handshake duration, etc. See Apple's documentation: https://developer.apple.com/documentation/foundation/urlsessiontaskmetrics
 */
@property (strong, nonatomic, readonly, nullable) NSURLSessionTaskMetrics *metrics API_AVAILABLE(macosx(10.12), ios(10.0), watchos(3.0), tvos(10.0));

/**
 * The context for the receiver.
 */
@property (copy, nonatomic, readonly, nullable) SDWebImageContext *context;

@property (assign, nonatomic) double minimumProgressInterval;

/**
 *  Initializes a `SDWebImageDownloaderOperation` object
 *
 *  @see SDWebImageDownloaderOperation
 *
 *  @param request        the URL request
 *  @param session        the URL session in which this operation will run
 *  @param options        downloader options
 *  @param context        A context contains different options to perform specify changes or processes, see `SDWebImageContextOption`. This hold the extra objects which `options` enum can not hold.
 *
 *  @return the initialized instance
 */
- (nonnull instancetype)initWithRequest:(nullable NSURLRequest *)request
                              inSession:(nullable NSURLSession *)session
                                options:(SDWebImageDownloaderOptions)options
                                context:(nullable SDWebImageContext *)context NS_DESIGNATED_INITIALIZER;

@end




