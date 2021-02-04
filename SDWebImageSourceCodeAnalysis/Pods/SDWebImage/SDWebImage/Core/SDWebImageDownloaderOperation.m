/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageDownloaderOperation.h"
#import "SDWebImageError.h"
#import "SDInternalMacros.h"
#import "SDWebImageDownloaderResponseModifier.h"
#import "SDWebImageDownloaderDecryptor.h"

// 进度回调块和下载完成回调块的字符串类型的key
static NSString *const kProgressCallbackKey = @"progress";
static NSString *const kCompletedCallbackKey = @"completed";

// 定义了一个可变字典类型的回调块集合，这个字典key的取值就是上面两个字符串
typedef NSMutableDictionary<NSString *, id> SDCallbacksDictionary;

@interface SDWebImageDownloaderOperation ()

// 回调块数组，数组内的元素即为前面自定义的字典
@property (strong, nonatomic, nonnull) NSMutableArray<SDCallbacksDictionary *> *callbackBlocks;

@property (assign, nonatomic, readwrite) SDWebImageDownloaderOptions options;
@property (copy, nonatomic, readwrite, nullable) SDWebImageContext *context;

// 继承NSOperation需要定义executing和finished属性，并实现getter和setter，手动触发KVO通知
@property (assign, nonatomic, getter = isExecuting) BOOL executing;
@property (assign, nonatomic, getter = isFinished) BOOL finished;

// 可变NSData数据，存储下载的图片数据
@property (strong, nonatomic, nullable) NSMutableData *imageData;
// 缓存的图片数据
@property (copy, nonatomic, nullable) NSData *cachedData;
// 需要下载的文件的大小
@property (assign, nonatomic) NSUInteger expectedSize;
// 接收到下载的文件的大小
@property (assign, nonatomic) NSUInteger receivedSize;
// 连接服务端后的收到的响应
@property (strong, nonatomic, nullable, readwrite) NSURLResponse *response;
@property (strong, nonatomic, nullable) NSError *responseError;
// 上一进度百分比
@property (assign, nonatomic) double previousProgress;

// 修改原始URL响应
@property (strong, nonatomic, nullable) id<SDWebImageDownloaderResponseModifier> responseModifier;
// 解密图像数据
@property (strong, nonatomic, nullable) id<SDWebImageDownloaderDecryptor> decryptor;

/*
这里是weak修饰的NSURLSession属性
作者解释到unownedSession有可能不可用，因为这个session是外面传进来的，由其他类负责管理这个session，本类不负责管理
这个session有可能会被回收，当不可用时使用下面那个session
*/
@property (weak, nonatomic, nullable) NSURLSession *unownedSession;

/*
 strong修饰的session，当上面weak的session不可用时，需要创建一个session
 这个session需要由本类负责管理，需要在合适的地方调用invalid方法打破引用循环
 */
@property (strong, nonatomic, nullable) NSURLSession *ownedSession;

// 具体的下载任务
@property (strong, nonatomic, readwrite, nullable) NSURLSessionTask *dataTask;

@property (strong, nonatomic, readwrite, nullable) NSURLSessionTaskMetrics *metrics API_AVAILABLE(macosx(10.12), ios(10.0), watchos(3.0), tvos(10.0));

// 图像解码的串行操作队列
@property (strong, nonatomic, nonnull) NSOperationQueue *coderQueue;

#if SD_UIKIT
// iOS上支持在后台下载时需要一个identifier
@property (assign, nonatomic) UIBackgroundTaskIdentifier backgroundTaskId;
#endif

@end

@implementation SDWebImageDownloaderOperation

@synthesize executing = _executing;
@synthesize finished = _finished;

- (nonnull instancetype)init
{
    return [self initWithRequest:nil inSession:nil options:0];
}

- (instancetype)initWithRequest:(NSURLRequest *)request inSession:(NSURLSession *)session options:(SDWebImageDownloaderOptions)options
{
    return [self initWithRequest:request inSession:session options:options context:nil];
}

- (nonnull instancetype)initWithRequest:(nullable NSURLRequest *)request
                              inSession:(nullable NSURLSession *)session
                                options:(SDWebImageDownloaderOptions)options
                                context:(nullable SDWebImageContext *)context
{
    if ((self = [super init]))
    {
        _request = [request copy];
        _options = options;
        _context = [context copy];
        _callbackBlocks = [NSMutableArray new];
        _responseModifier = context[SDWebImageContextDownloadResponseModifier];
        _decryptor = context[SDWebImageContextDownloadDecryptor];
        _executing = NO;
        _finished = NO;
        _expectedSize = 0;
        // 在初始化方法中将传入的session赋给了unownedSession，所以这个session是外部传入的，本类就不需要负责管理它
        // 但是它有可能会被释放，所以当这个session不可用时需要自己创建一个新的session并自行管理
        _unownedSession = session;
        _coderQueue = [NSOperationQueue new];
        _coderQueue.maxConcurrentOperationCount = 1;
#if SD_UIKIT
        _backgroundTaskId = UIBackgroundTaskInvalid;
#endif
    }
    return self;
}

// 添加进度回调块和下载完成回调块
- (nullable id)addHandlersForProgress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                            completed:(nullable SDWebImageDownloaderCompletedBlock)completedBlock
{
    // 创建一个<NSString,id>类型的可变字典，value为回调块
    SDCallbacksDictionary *callbacks = [NSMutableDictionary new];
    // 如果进度回调块存在就加进字典里，key为@"progress"
    if (progressBlock) callbacks[kProgressCallbackKey] = [progressBlock copy];
    // 如果下载完成回调块存在就加进字典里，key为@"completed"
    if (completedBlock) callbacks[kCompletedCallbackKey] = [completedBlock copy];
    // 阻塞并发队列，串行执行添加进数组的操作
    @synchronized (self)
    {
        [self.callbackBlocks addObject:callbacks];
    }
    // 回的token其实就是这个字典
    return callbacks;
}

// 通过key获取回调块数组中所有对应key的回调块
- (nullable NSArray<id> *)callbacksForKey:(NSString *)key
{
    NSMutableArray<id> *callbacks;
    // 同步方式执行，阻塞当前线程也阻塞队列
    @synchronized (self)
    {
        callbacks = [[self.callbackBlocks valueForKey:key] mutableCopy];
    }
    // 如果字典中没有对应key会返回null，所以需要删除为null的元素
    [callbacks removeObjectIdenticalTo:[NSNull null]];
    return [callbacks copy];
}

- (BOOL)cancel:(nullable id)token
{
    if (!token) return NO;
    
    BOOL shouldCancel = NO;
    // 同步方式执行，阻塞当前线程也阻塞队列
    @synchronized (self)
    {
        // 根据token删除数组中的数据，token就是key为string，value为block的字典
        NSMutableArray *tempCallbackBlocks = [self.callbackBlocks mutableCopy];
        // 删除的就是数组中的字典元素
        [tempCallbackBlocks removeObjectIdenticalTo:token];
        // 如果回调块数组长度为0就真的要取消下载任务了，因为已经没有人来接收下载完成和下载进度的信息，下载完成也没有任何意义
        if (tempCallbackBlocks.count == 0)
        {
            shouldCancel = YES;
        }
    }
    
    // 如果要真的要取消任务就调用cancel方法
    if (shouldCancel)
    {
        [self cancel];
    }
    else
    {
        @synchronized (self)
        {
            [self.callbackBlocks removeObjectIdenticalTo:token];
        }
        SDWebImageDownloaderCompletedBlock completedBlock = [token valueForKey:kCompletedCallbackKey];
        dispatch_main_async_safe(^{
            if (completedBlock) {
                completedBlock(nil, nil, [NSError errorWithDomain:SDWebImageErrorDomain code:SDWebImageErrorCancelled userInfo:@{NSLocalizedDescriptionKey : @"Operation cancelled by user during sending the request"}], YES);
            }
        });
    }
    return shouldCancel;
}

- (void)start
{
    // 同步代码块，防止产生竞争条件
    // NSOperation子类加进NSOperationQueue后会自行调用start方法，并且只会执行一次，不太理解为什么需要加这个
    @synchronized (self)
    {
        // 判断是否取消了下载任务
        if (self.isCancelled)
        {
            // 如果取消了就设置finished为YES，
            self.finished = YES;
            // 用户取消错误
            [self callCompletionBlocksWithError:[NSError errorWithDomain:SDWebImageErrorDomain code:SDWebImageErrorCancelled userInfo:@{NSLocalizedDescriptionKey : @"Operation cancelled by user before sending the request"}]];
            // 调用reset方法
            [self reset];
            return;
        }

#if SD_UIKIT
        // iOS支持可以在app进入后台后继续下载
        Class UIApplicationClass = NSClassFromString(@"UIApplication");
        BOOL hasApplication = UIApplicationClass && [UIApplicationClass respondsToSelector:@selector(sharedApplication)];
        if (hasApplication && [self shouldContinueWhenAppEntersBackground])
        {
            __weak typeof(self) wself = self;
            UIApplication * app = [UIApplicationClass performSelector:@selector(sharedApplication)];
            self.backgroundTaskId = [app beginBackgroundTaskWithExpirationHandler:^{
                [wself cancel];
            }];
        }
#endif
        // 判断unownedSession是否为nil
        NSURLSession *session = self.unownedSession;
        if (!session)
        {
            // 为空则自行创建一个NSURLSession对象
            // session运行在默认模式下
            NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
            // 超时时间15s
            sessionConfig.timeoutIntervalForRequest = 15;
            
            // delegateQueue为nil，所以回调方法默认在一个子线程的串行队列中执行
            session = [NSURLSession sessionWithConfiguration:sessionConfig
                                                    delegate:self
                                               delegateQueue:nil];
            // 局部变量赋值
            self.ownedSession = session;
        }
        
        // 根据配置的下载选项获取网络请求的缓存数据
        if (self.options & SDWebImageDownloaderIgnoreCachedResponse)
        {
            NSURLCache *URLCache = session.configuration.URLCache;
            if (!URLCache)
            {
                URLCache = [NSURLCache sharedURLCache];
            }
            NSCachedURLResponse *cachedResponse;
            @synchronized (URLCache)
            {
                cachedResponse = [URLCache cachedResponseForRequest:self.request];
            }
            if (cachedResponse)
            {
                self.cachedData = cachedResponse.data;
            }
        }
        
        // 使用可用的session来创建一个NSURLSessionDataTask类型的下载任务
        self.dataTask = [session dataTaskWithRequest:self.request];
        // 设置NSOperation子类的executing属性，标识开始下载任务
        self.executing = YES;
    }

    // 如果这个NSURLSessionDataTask不为空即开启成功
    if (self.dataTask)
    {
        if (self.options & SDWebImageDownloaderHighPriority)
        {
            // 设置任务优先级为高优先级
            self.dataTask.priority = NSURLSessionTaskPriorityHigh;
            // 图像解码的串行操作队列的服务质量为用户交互
            self.coderQueue.qualityOfService = NSQualityOfServiceUserInteractive;
        }
        else if (self.options & SDWebImageDownloaderLowPriority)
        {
            self.dataTask.priority = NSURLSessionTaskPriorityLow;
            self.coderQueue.qualityOfService = NSQualityOfServiceBackground;
        }
        else
        {
            self.dataTask.priority = NSURLSessionTaskPriorityDefault;
            self.coderQueue.qualityOfService = NSQualityOfServiceDefault;
        }
        
        // NSURLSessionDataTask任务开始执行
        [self.dataTask resume];
        
        // 遍历所有的进度回调块并执行
        for (SDWebImageDownloaderProgressBlock progressBlock in [self callbacksForKey:kProgressCallbackKey])
        {
            progressBlock(0, NSURLResponseUnknownLength, self.request.URL);
        }
        
        __block typeof(self) strongSelf = self;
        // 在什么线程发送通知，就会在什么线程接收通知
        // 为了防止其他监听通知的对象在回调方法中修改UI，这里就需要在主线程中发送通知
        dispatch_async(dispatch_get_main_queue(), ^{
            // 在主线程中发送通知，并将self传出去
            [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStartNotification object:strongSelf];
        });
    }
    else
    {
        [self callCompletionBlocksWithError:[NSError errorWithDomain:SDWebImageErrorDomain code:SDWebImageErrorInvalidDownloadOperation userInfo:@{NSLocalizedDescriptionKey : @"Task can't be initialized"}]];
        [self done];
    }
}

// SDWebImageOperation协议的cancel方法，取消任务，调用cancelInternal方法
- (void)cancel
{
    @synchronized (self)
    {
        // 真正取消下载任务的方法
        [self cancelInternal];
    }
}

- (void)cancelInternal
{
    // 如果下载任务已经结束了直接返回
    if (self.isFinished) return;
    
    // 调用NSOperation类的cancel方法，即将isCancelled属性置为YES
    [super cancel];

    // 如果NSURLSessionDataTask下载图片的任务存在
    if (self.dataTask)
    {
        // 调用其cancel方法取消下载任务
        [self.dataTask cancel];
        
        // 在主线程中发出下载停止的通知
        __block typeof(self) strongSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStopNotification object:strongSelf];
        });
        
        // 设置两个属性的值
        if (self.isExecuting) self.executing = NO;
        if (!self.isFinished) self.finished = YES;
    }
    else
    {
        
        [self callCompletionBlocksWithError:[NSError errorWithDomain:SDWebImageErrorDomain code:SDWebImageErrorCancelled userInfo:@{NSLocalizedDescriptionKey : @"Operation cancelled by user during sending the request"}]];
    }
    
    // 调用reset方法
    [self reset];
}

// 下载完成后调用的方法
- (void)done
{
    // 设置finished为YES executing为NO
    self.finished = YES;
    self.executing = NO;
    
    // 调用reset方法
    [self reset];
}

- (void)reset
{
    @synchronized (self)
    {
        // 删除回调块字典数组的所有元素
        [self.callbackBlocks removeAllObjects];
        // NSURLSessionDataTask对象置为nil
        self.dataTask = nil;
        
        // 如果ownedSession存在，就需要我们手动调用invalidateAndCancel方法打破引用循环
        if (self.ownedSession)
        {
            [self.ownedSession invalidateAndCancel];
            self.ownedSession = nil;
        }
        
#if SD_UIKIT
        // 停止后台下载
        if (self.backgroundTaskId != UIBackgroundTaskInvalid)
        {
            // If backgroundTaskId != UIBackgroundTaskInvalid, sharedApplication is always exist
            UIApplication * app = [UIApplication performSelector:@selector(sharedApplication)];
            [app endBackgroundTask:self.backgroundTaskId];
            self.backgroundTaskId = UIBackgroundTaskInvalid;
        }
#endif
    }
}

- (void)setFinished:(BOOL)finished
{
    // 手动触发KVO通知
    [self willChangeValueForKey:@"isFinished"];
    _finished = finished;
    [self didChangeValueForKey:@"isFinished"];
}

- (void)setExecuting:(BOOL)executing
{
    [self willChangeValueForKey:@"isExecuting"];
    _executing = executing;
    [self didChangeValueForKey:@"isExecuting"];
}

- (BOOL)isConcurrent
{
    return YES;
}

#pragma mark NSURLSessionDataDelegate

// 收到服务端响应，在一次请求中只会执行一次
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
    NSURLSessionResponseDisposition disposition = NSURLSessionResponseAllow;
    
    BOOL valid = YES;
    // 修改原始URL响应
    if (self.responseModifier && response)
    {
        response = [self.responseModifier modifiedResponseWithResponse:response];
        if (!response)
        {
            valid = NO;
            self.responseError = [NSError errorWithDomain:SDWebImageErrorDomain code:SDWebImageErrorInvalidDownloadResponse userInfo:@{NSLocalizedDescriptionKey : @"Download marked as failed because response is nil"}];
        }
    }
    // 将连接服务端后的收到的响应赋值到成员变量
    self.response = response;
    
    // 根据http状态码判断是否成功响应，需要注意的是304被认为是异常响应
    NSInteger statusCode = [response respondsToSelector:@selector(statusCode)] ? ((NSHTTPURLResponse *)response).statusCode : 200;
    BOOL statusCodeValid = statusCode >= 200 && statusCode < 400;
    if (!statusCodeValid)
    {
        valid = NO;
        self.responseError = [NSError errorWithDomain:SDWebImageErrorDomain code:SDWebImageErrorInvalidDownloadStatusCode userInfo:@{NSLocalizedDescriptionKey : @"Download marked as failed because response status code is not in 200-400", SDWebImageErrorDownloadStatusCodeKey : @(statusCode)}];
    }
    
    if (statusCode == 304 && !self.cachedData)
    {
        valid = NO;
        self.responseError = [NSError errorWithDomain:SDWebImageErrorDomain code:SDWebImageErrorCacheNotModified userInfo:@{NSLocalizedDescriptionKey : @"Download response status code is 304 not modified and ignored"}];
    }
    
    // 获取要下载图片的长度
    NSInteger expected = (NSInteger)response.expectedContentLength;
    expected = expected > 0 ? expected : 0;
    // 设置长度
    self.expectedSize = expected;
    
    // 如果响应正常
    if (valid)
    {
        // 遍历进度回调块并触发进度回调块
        for (SDWebImageDownloaderProgressBlock progressBlock in [self callbacksForKey:kProgressCallbackKey])
        {
            progressBlock(0, expected, self.request.URL);
        }
    }
    else
    {
        disposition = NSURLSessionResponseCancel;
    }
    
    // 主线程中发送相关通知
    __block typeof(self) strongSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadReceiveResponseNotification object:strongSelf];
    });
    
    // 如果有回调块就执行
    if (completionHandler)
    {
        completionHandler(disposition);
    }
}

// 收到数据的回调方法，可能执行多次
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
    // 向可变数据中添加接收到的数据
    if (!self.imageData)
    {
        self.imageData = [[NSMutableData alloc] initWithCapacity:self.expectedSize];
    }
    [self.imageData appendData:data];
    
    // 获取已经下载了多大的数据
    self.receivedSize = self.imageData.length;

    if (self.expectedSize == 0)
    {
        // Unknown expectedSize, immediately call progressBlock and return
        for (SDWebImageDownloaderProgressBlock progressBlock in [self callbacksForKey:kProgressCallbackKey]) {
            progressBlock(self.receivedSize, self.expectedSize, self.request.URL);
        }
        return;
    }
    
    // 判断是否已经下载完成
    BOOL finished = (self.receivedSize >= self.expectedSize);
    // 计算下载进度
    double currentProgress = (double)self.receivedSize / (double)self.expectedSize;
    double previousProgress = self.previousProgress;
    double progressInterval = currentProgress - previousProgress;
    // 龟速下载直接返回
    if (!finished && (progressInterval < self.minimumProgressInterval))
    {
        return;
    }
    self.previousProgress = currentProgress;
    
    // 使用数据解密将禁用渐进式解码
    BOOL supportProgressive = (self.options & SDWebImageDownloaderProgressiveLoad) && !self.decryptor;
    // 支持渐进式解码
    if (supportProgressive)
    {
        // 获取图像数据
        NSData *imageData = [self.imageData copy];
        
        // 下载期间最多保留一个按照下载进度进行解码的操作
        // coderQueue是图像解码的串行操作队列
        if (self.coderQueue.operationCount == 0)
        {
            // NSOperation有自动释放池，不需要额外创建一个
            [self.coderQueue addOperationWithBlock:^{
                // 将数据交给解码器返回一个图片
                UIImage *image = SDImageLoaderDecodeProgressiveImageData(imageData, self.request.URL, finished, self, [[self class] imageOptionsFromDownloaderOptions:self.options], self.context);
                
                if (image)
                {
                    // 触发回调块回传这个图片
                    [self callCompletionBlocksWithImage:image imageData:nil error:nil finished:NO];
                }
            }];
        }
    }
    
    // 调用进度回调块并触发进度回调块
    for (SDWebImageDownloaderProgressBlock progressBlock in [self callbacksForKey:kProgressCallbackKey])
    {
        progressBlock(self.receivedSize, self.expectedSize, self.request.URL);
    }
}

// 如果要缓存响应时回调该方法
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
 willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler
{
    NSCachedURLResponse *cachedResponse = proposedResponse;

    // 如果request的缓存策略是不缓存本地数据就设置为nil
    if (!(self.options & SDWebImageDownloaderUseNSURLCache))
    {
        // 防止缓存响应
        cachedResponse = nil;
    }
    
    // 调用回调块
    if (completionHandler)
    {
        completionHandler(cachedResponse);
    }
}

#pragma mark NSURLSessionTaskDelegate

// 任务完成后的回调
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    // If we already cancel the operation or anything mark the operation finished, don't callback twice
    if (self.isFinished) return;
    
    @synchronized(self)
    {
        // 置空
        self.dataTask = nil;
        
        // 主线程根据error是否为空发送对应通知
        __block typeof(self) strongSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStopNotification object:strongSelf];
            if (!error)
            {
                [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadFinishNotification object:strongSelf];
            }
        });
    }
    
    // 如果error存在，即下载过程中出错
    if (error)
    {
        // 自定义错误而不是URLSession错误
        if (self.responseError)
        {
            error = self.responseError;
        }
        // 触发对应回调块
        [self callCompletionBlocksWithError:error];
        // 下载完成后调用的方法
        [self done];
    }
    // 下载成功
    else
    {
        // 判断下载完成回调块个数是否大于0
        if ([self callbacksForKey:kCompletedCallbackKey].count > 0)
        {
            // 获取不可变data图片数据
            NSData *imageData = [self.imageData copy];
            self.imageData = nil;
            // 如果下载的图片和解密图像数据的解码器存在
            if (imageData && self.decryptor)
            {
                // 解码图片，返回data
                imageData = [self.decryptor decryptedDataWithData:imageData response:self.response];
            }
            
            
            if (imageData)
            {
                // 如果下载设置为只使用缓存数据就会判断缓存数据与当前获取的数据是否一致，一致就触发完成回调块
                if (self.options & SDWebImageDownloaderIgnoreCachedResponse && [self.cachedData isEqualToData:imageData])
                {
                    // 错误：下载的图像不会被修改和忽略
                    self.responseError = [NSError errorWithDomain:SDWebImageErrorDomain code:SDWebImageErrorCacheNotModified userInfo:@{NSLocalizedDescriptionKey : @"Downloaded image is not modified and ignored"}];
                    // 调用带有未修改错误的回调完成块
                    [self callCompletionBlocksWithError:self.responseError];
                    // 下载完成后调用的方法
                    [self done];
                }
                else
                {
                    // 取消之前的所有解码过程
                    [self.coderQueue cancelAllOperations];
                    
                    // 图像解码的串行操作队列
                    [self.coderQueue addOperationWithBlock:^{
                        // 解码图片，返回图片
                        UIImage *image = SDImageLoaderDecodeImageData(imageData, self.request.URL, [[self class] imageOptionsFromDownloaderOptions:self.options], self.context);
 
                        CGSize imageSize = image.size;
                        // 下载的图像有0个像素
                        if (imageSize.width == 0 || imageSize.height == 0)
                        {
                            // 调用带有图像大小为0错误的回调完成块
                            NSString *description = image == nil ? @"Downloaded image decode failed" : @"Downloaded image has 0 pixels";
                            [self callCompletionBlocksWithError:[NSError errorWithDomain:SDWebImageErrorDomain code:SDWebImageErrorBadImageData userInfo:@{NSLocalizedDescriptionKey : description}]];
                        }
                        else
                        {
                            // 触发成功完成回调块
                            [self callCompletionBlocksWithImage:image imageData:imageData error:nil finished:YES];
                        }
                        // 下载完成后调用的方法
                        [self done];
                    }];
                }
            }
            else
            {
                [self callCompletionBlocksWithError:[NSError errorWithDomain:SDWebImageErrorDomain code:SDWebImageErrorBadImageData userInfo:@{NSLocalizedDescriptionKey : @"Image data is nil"}]];
                [self done];
            }
        }
        else
        {
            [self done];
        }
    }
}

// 如果是https访问就需要设置SSL证书相关
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    
    NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    __block NSURLCredential *credential = nil;
    
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust])
    {
        if (!(self.options & SDWebImageDownloaderAllowInvalidSSLCertificates))
        {
            disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        }
        else
        {
            credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            disposition = NSURLSessionAuthChallengeUseCredential;
        }
    }
    else
    {
        if (challenge.previousFailureCount == 0)
        {
            if (self.credential)
            {
                credential = self.credential;
                disposition = NSURLSessionAuthChallengeUseCredential;
            }
            else
            {
                disposition = NSURLSessionAuthChallengeCancelAuthenticationChallenge;
            }
        }
        else
        {
            disposition = NSURLSessionAuthChallengeCancelAuthenticationChallenge;
        }
    }
    
    if (completionHandler)
    {
        completionHandler(disposition, credential);
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics API_AVAILABLE(macosx(10.12), ios(10.0), watchos(3.0), tvos(10.0)) {
    self.metrics = metrics;
}

#pragma mark Helper methods
+ (SDWebImageOptions)imageOptionsFromDownloaderOptions:(SDWebImageDownloaderOptions)downloadOptions {
    SDWebImageOptions options = 0;
    if (downloadOptions & SDWebImageDownloaderScaleDownLargeImages) options |= SDWebImageScaleDownLargeImages;
    if (downloadOptions & SDWebImageDownloaderDecodeFirstFrameOnly) options |= SDWebImageDecodeFirstFrameOnly;
    if (downloadOptions & SDWebImageDownloaderPreloadAllFrames) options |= SDWebImagePreloadAllFrames;
    if (downloadOptions & SDWebImageDownloaderAvoidDecodeImage) options |= SDWebImageAvoidDecodeImage;
    if (downloadOptions & SDWebImageDownloaderMatchAnimatedImageClass) options |= SDWebImageMatchAnimatedImageClass;
    
    return options;
}

- (BOOL)shouldContinueWhenAppEntersBackground {
    return SD_OPTIONS_CONTAINS(self.options, SDWebImageDownloaderContinueInBackground);
}

- (void)callCompletionBlocksWithError:(nullable NSError *)error {
    [self callCompletionBlocksWithImage:nil imageData:nil error:error finished:YES];
}

// 遍历所有的完成回调块，在主线程中触发
- (void)callCompletionBlocksWithImage:(nullable UIImage *)image
                            imageData:(nullable NSData *)imageData
                                error:(nullable NSError *)error
                             finished:(BOOL)finished
{
    NSArray<id> *completionBlocks = [self callbacksForKey:kCompletedCallbackKey];
    dispatch_main_async_safe(^{
        for (SDWebImageDownloaderCompletedBlock completedBlock in completionBlocks) {
            completedBlock(image, imageData, error, finished);
        }
    });
}
@end




