/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageDownloader.h"
#import "SDWebImageDownloaderOperation.h"
#import <ImageIO/ImageIO.h>

static NSString *const kProgressCallbackKey = @"progress";
static NSString *const kCompletedCallbackKey = @"completed";

@interface SDWebImageDownloader ()

@property (strong, nonatomic) NSOperationQueue *downloadQueue;
@property (weak, nonatomic) NSOperation *lastAddedOperation;
@property (assign, nonatomic) Class operationClass;
@property (strong, nonatomic) NSMutableDictionary *URLCallbacks;
@property (strong, nonatomic) NSMutableDictionary *HTTPHeaders;
// This queue is used to serialize the handling of the network responses of all the download operation in a single queue
@property (SDDispatchQueueSetterSementics, nonatomic) dispatch_queue_t barrierQueue;

@end

@implementation SDWebImageDownloader

+ (void)initialize {
    // Bind SDNetworkActivityIndicator if available (download it here: http://github.com/rs/SDNetworkActivityIndicator )
    // To use it, just add #import "SDNetworkActivityIndicator.h" in addition to the SDWebImage import
    if (NSClassFromString(@"SDNetworkActivityIndicator")) {

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id activityIndicator = [NSClassFromString(@"SDNetworkActivityIndicator") performSelector:NSSelectorFromString(@"sharedActivityIndicator")];
#pragma clang diagnostic pop

        // Remove observer in case it was previously added.
        [[NSNotificationCenter defaultCenter] removeObserver:activityIndicator name:SDWebImageDownloadStartNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:activityIndicator name:SDWebImageDownloadStopNotification object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:activityIndicator
                                                 selector:NSSelectorFromString(@"startActivity")
                                                     name:SDWebImageDownloadStartNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:activityIndicator
                                                 selector:NSSelectorFromString(@"stopActivity")
                                                     name:SDWebImageDownloadStopNotification object:nil];
    }
}

+ (SDWebImageDownloader *)sharedDownloader {
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}

- (id)init {
    if ((self = [super init])) {
        _operationClass = [SDWebImageDownloaderOperation class];
        _shouldDecompressImages = YES;
        // 设置下载 operation 的默认执行顺序（先进先出还是先进后出）
        _executionOrder = SDWebImageDownloaderFIFOExecutionOrder;
        // 初始化 _downloadQueue（下载队列）
        _downloadQueue = [NSOperationQueue new];
        // 初始化 _barrierQueue（GCD 队列）最大并发数（6）
        _downloadQueue.maxConcurrentOperationCount = 6;
        // 初始化 _URLCallbacks（下载回调 block 的容器）
        _URLCallbacks = [NSMutableDictionary new];
        // 设置 _HTTPHeaders 默认值
        _HTTPHeaders = [@{@"Accept": @"image/webp,image/*;q=0.8"} mutableCopy];
        _barrierQueue = dispatch_queue_create("com.hackemist.SDWebImageDownloaderBarrierQueue", DISPATCH_QUEUE_CONCURRENT);
        // 设置默认下载超时时长 15s
        _downloadTimeout = 15.0;
    }
    return self;
}

- (void)dealloc {
    [self.downloadQueue cancelAllOperations];
    SDDispatchQueueRelease(_barrierQueue);
}

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if (value) {
        self.HTTPHeaders[field] = value;
    }
    else {
        [self.HTTPHeaders removeObjectForKey:field];
    }
}

- (NSString *)valueForHTTPHeaderField:(NSString *)field {
    return self.HTTPHeaders[field];
}

- (void)setMaxConcurrentDownloads:(NSInteger)maxConcurrentDownloads {
    _downloadQueue.maxConcurrentOperationCount = maxConcurrentDownloads;
}

- (NSUInteger)currentDownloadCount {
    return _downloadQueue.operationCount;
}

- (NSInteger)maxConcurrentDownloads {
    return _downloadQueue.maxConcurrentOperationCount;
}

- (void)setOperationClass:(Class)operationClass {
    _operationClass = operationClass ?: [SDWebImageDownloaderOperation class];
}

- (id <SDWebImageOperation>)downloadImageWithURL:(NSURL *)url options:(SDWebImageDownloaderOptions)options progress:(SDWebImageDownloaderProgressBlock)progressBlock completed:(SDWebImageDownloaderCompletedBlock)completedBlock {
    __block SDWebImageDownloaderOperation *operation;
    __weak __typeof(self)wself = self;

    // 1. 把入参 url、progressBlock 和 completedBlock 传进该方法，并在第一次下载该 URL 时回调 createCallback
    [self addProgressCallback:progressBlock andCompletedBlock:completedBlock forURL:url createCallback:^{
        NSTimeInterval timeoutInterval = wself.downloadTimeout;
        if (timeoutInterval == 0.0) {
            timeoutInterval = 15.0;
        }

        // In order to prevent from potential duplicate caching (NSURLCache + SDImageCache) we disable the cache for image requests if told otherwise
        // 1.1 创建下载 request ，设置 request 的 cachePolicy、HTTPShouldHandleCookies、HTTPShouldUsePipelining
        // 以及 allHTTPHeaderFields（这个属性交由外面处理，设计的比较巧妙）
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:(options & SDWebImageDownloaderUseNSURLCache ? NSURLRequestUseProtocolCachePolicy : NSURLRequestReloadIgnoringLocalCacheData) timeoutInterval:timeoutInterval];
        request.HTTPShouldHandleCookies = (options & SDWebImageDownloaderHandleCookies);
        request.HTTPShouldUsePipelining = YES;
        if (wself.headersFilter) {
            request.allHTTPHeaderFields = wself.headersFilter(url, [wself.HTTPHeaders copy]);
        }
        else {
            request.allHTTPHeaderFields = wself.HTTPHeaders;
        }
        // 1.2 创建 SDWebImageDownloaderOperation（继承自 NSOperation）
        operation = [[wself.operationClass alloc] initWithRequest:request options:options progress:^(NSInteger receivedSize, NSInteger expectedSize) {
            // 1.2.1 SDWebImageDownloaderOperation 的 progressBlock 回调处理
            // 这个 block 有两个回调参数：接收到的数据大小和预计数据大小
            
            // 这里用了 weak-strong dance，首先使用 strongSelf 强引用 weakSelf，目的是为了保住 self 不被释放
            SDWebImageDownloader *sself = wself;
            // 然后检查 self 是否已经被释放（这里为什么先“保活”后“判空”呢？因为如果先判空的话，有可能判空后 self 就被释放了）
            if (!sself) return;
            // 取出 url 对应的回调 block 数组（这里取的时候有些讲究，考虑了多线程问题，而且取的是 copy 的内容）
            __block NSArray *callbacksForURL;
            dispatch_sync(sself.barrierQueue, ^{
                callbacksForURL = [sself.URLCallbacks[url] copy];
            });
            // 遍历数组，从每个元素（字典）中取出 progressBlock 进行回调
            for (NSDictionary *callbacks in callbacksForURL) {
                SDWebImageDownloaderProgressBlock callback = callbacks[kProgressCallbackKey];
                if (callback) callback(receivedSize, expectedSize);
            }
        } completed:^(UIImage *image, NSData *data, NSError *error, BOOL finished) {
            // 1.2.2 SDWebImageDownloaderOperation 的 completedBlock 回调处理
            // 这个 block 有四个回调参数：图片 UIImage，图片数据 NSData，错误 NSError，是否结束 isFinished
            
            // 同样，这里也用了 weak-strong dance
            SDWebImageDownloader *sself = wself;
            if (!sself) return;
            
            // 接着，取出 url 对应的回调 block 数组
            __block NSArray *callbacksForURL;
            dispatch_barrier_sync(sself.barrierQueue, ^{
                callbacksForURL = [sself.URLCallbacks[url] copy];
                // 如果结束了（isFinished），就移除 url 对应的回调 block 数组（移除的时候也要考虑多线程问题）
                if (finished) {
                    [sself.URLCallbacks removeObjectForKey:url];
                }
            });
            // 遍历数组，从每个元素（字典）中取出 completedBlock 进行回调
            for (NSDictionary *callbacks in callbacksForURL) {
                SDWebImageDownloaderCompletedBlock callback = callbacks[kCompletedCallbackKey];
                if (callback) callback(image, data, error, finished);
            }
        } cancelled:^{
            // SDWebImageDownloaderOperation 的 cancelBlock 回调处理
            
            // 同样，这里也用了 weak-strong dance
            SDWebImageDownloader *sself = wself;
            if (!sself) return;
            
            // 然后移除 url 对应的所有回调 block
            dispatch_barrier_async(sself.barrierQueue, ^{
                [sself.URLCallbacks removeObjectForKey:url];
            });
        }];
        // 1.3 设置下载完成后是否需要解压缩
        operation.shouldDecompressImages = wself.shouldDecompressImages;
        
        // 1.4 如果设置了 username 和 password，就给 operation 的下载请求设置一个 NSURLCredential
        if (wself.username && wself.password) {
            operation.credential = [NSURLCredential credentialWithUser:wself.username password:wself.password persistence:NSURLCredentialPersistenceForSession];
        }
        
        // 1.5 设置 operation 的队列优先级
        if (options & SDWebImageDownloaderHighPriority) {
            operation.queuePriority = NSOperationQueuePriorityHigh;
        } else if (options & SDWebImageDownloaderLowPriority) {
            operation.queuePriority = NSOperationQueuePriorityLow;
        }

        // 1.6 将 operation 加入到队列 downloadQueue 中，队列（NSOperationQueue）会自动管理 operation 的执行
        [wself.downloadQueue addOperation:operation];
        // 1.7 如果 operation 执行顺序是先进后出，就设置 operation 依赖关系（先加入的依赖于后加入的），并记录最后一个 operation（lastAddedOperation）
        if (wself.executionOrder == SDWebImageDownloaderLIFOExecutionOrder) {
            // Emulate LIFO execution order by systematically adding new operations as last operation's dependency
            [wself.lastAddedOperation addDependency:operation];
            wself.lastAddedOperation = operation;
        }
    }];

    // 2. 返回 createCallback 中创建的 operation（SDWebImageDownloaderOperation）
    return operation;
}

- (void)addProgressCallback:(SDWebImageDownloaderProgressBlock)progressBlock andCompletedBlock:(SDWebImageDownloaderCompletedBlock)completedBlock forURL:(NSURL *)url createCallback:(SDWebImageNoParamsBlock)createCallback {
    // 判断 url 是否为 nil，如果为 nil 则直接回调 completedBlock，返回失败的结果，然后 return
    // 因为 url 会作为存储 callbacks 的 key
    if (url == nil) {
        if (completedBlock != nil) {
            completedBlock(nil, nil, nil, NO);
        }
        return;
    }

    // MARK: 使用 dispatch_barrier_sync 函数来保证同一时间只有一个线程能对 URLCallbacks 进行操作
    dispatch_barrier_sync(self.barrierQueue, ^{
        // 从属性 URLCallbacks(一个字典) 中取出对应 url 的 callBacksForURL
        // 这是一个数组，因为可能一个 url 不止在一个地方下载
        BOOL first = NO;
        if (!self.URLCallbacks[url]) {
            // 如果没有取到，也就意味着这个 url 是第一次下载
            // 那就初始化一个 callBacksForURL 放到属性 URLCallbacks 中
            self.URLCallbacks[url] = [NSMutableArray new];
            first = YES;
        }

        // 处理同一个 URL 的多次下载请求
        NSMutableArray *callbacksForURL = self.URLCallbacks[url];
        // 往数组 callBacksForURL 中添加 包装有 callbacks（progressBlock 和 completedBlock）的字典
        NSMutableDictionary *callbacks = [NSMutableDictionary new];
        if (progressBlock) callbacks[kProgressCallbackKey] = [progressBlock copy];
        if (completedBlock) callbacks[kCompletedCallbackKey] = [completedBlock copy];
        [callbacksForURL addObject:callbacks];
        // 更新 URLCallbacks 存储的对应 url 的 callBacksForURL
        self.URLCallbacks[url] = callbacksForURL;

        // 如果这个 url 是第一次请求下载，就回调 createCallback
        if (first) {
            createCallback();
        }
    });
}

- (void)setSuspended:(BOOL)suspended {
    [self.downloadQueue setSuspended:suspended];
}

@end
