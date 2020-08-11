// AFImageDownloader.m
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

#import <TargetConditionals.h>

#if TARGET_OS_IOS || TARGET_OS_TV

#import "AFImageDownloader.h"
#import "AFHTTPSessionManager.h"

@interface AFImageDownloaderResponseHandler : NSObject

@property (nonatomic, strong) NSUUID *uuid;
@property (nonatomic, copy) void (^successBlock)(NSURLRequest*, NSHTTPURLResponse*, UIImage*);
@property (nonatomic, copy) void (^failureBlock)(NSURLRequest*, NSHTTPURLResponse*, NSError*);

@end

@implementation AFImageDownloaderResponseHandler

//初始化回调对象
- (instancetype)initWithUUID:(NSUUID *)uuid
                     success:(nullable void (^)(NSURLRequest *request, NSHTTPURLResponse * _Nullable response, UIImage *responseObject))success
                     failure:(nullable void (^)(NSURLRequest *request, NSHTTPURLResponse * _Nullable response, NSError *error))failure {
    if (self = [self init]) {
        self.uuid = uuid;
        self.successBlock = success;
        self.failureBlock = failure;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat: @"<AFImageDownloaderResponseHandler>UUID: %@", [self.uuid UUIDString]];
}

@end

@interface AFImageDownloaderMergedTask : NSObject

@property (nonatomic, strong) NSString *URLIdentifier;// 用来标识这个task的
@property (nonatomic, strong) NSUUID *identifier;// 用来标识这个task的
@property (nonatomic, strong) NSURLSessionDataTask *task;

// 用来存储task完成后的回调的，里面可以存一组。当任务完成时候，里面的回调都会被调用
@property (nonatomic, strong) NSMutableArray <AFImageDownloaderResponseHandler*> *responseHandlers;

@end

@implementation AFImageDownloaderMergedTask

- (instancetype)initWithURLIdentifier:(NSString *)URLIdentifier identifier:(NSUUID *)identifier task:(NSURLSessionDataTask *)task {
    if (self = [self init]) {
        self.URLIdentifier = URLIdentifier;
        self.task = task;
        self.identifier = identifier;
        self.responseHandlers = [[NSMutableArray alloc] init];
    }
    return self;
}

//添加任务完成回调
- (void)addResponseHandler:(AFImageDownloaderResponseHandler*)handler {
    [self.responseHandlers addObject:handler];
}

//移除任务完成回调
- (void)removeResponseHandler:(AFImageDownloaderResponseHandler*)handler {
    [self.responseHandlers removeObject:handler];
}

@end

@implementation AFImageDownloadReceipt

- (instancetype)initWithReceiptID:(NSUUID *)receiptID task:(NSURLSessionDataTask *)task {
    if (self = [self init]) {
        self.receiptID = receiptID;
        self.task = task;
    }
    return self;
}

@end

@interface AFImageDownloader ()

@property (nonatomic, strong) dispatch_queue_t synchronizationQueue;
@property (nonatomic, strong) dispatch_queue_t responseQueue;

@property (nonatomic, assign) NSInteger maximumActiveDownloads;
@property (nonatomic, assign) NSInteger activeRequestCount;

@property (nonatomic, strong) NSMutableArray *queuedMergedTasks;
@property (nonatomic, strong) NSMutableDictionary *mergedTasks;

@end


@implementation AFImageDownloader

//设置一个系统缓存，内存缓存为20M，磁盘缓存为150M，
//这个是系统级别维护的缓存
+ (NSURLCache *)defaultURLCache {
    return [[NSURLCache alloc] initWithMemoryCapacity:20 * 1024 * 1024
                                         diskCapacity:150 * 1024 * 1024
                                             diskPath:@"com.alamofire.imagedownloader"];
}

+ (NSURLSessionConfiguration *)defaultURLSessionConfiguration {
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];

    //TODO set the default HTTP headers

    configuration.HTTPShouldSetCookies = YES;
    configuration.HTTPShouldUsePipelining = NO;

    configuration.requestCachePolicy = NSURLRequestUseProtocolCachePolicy;
    configuration.allowsCellularAccess = YES;
    configuration.timeoutIntervalForRequest = 60.0;
    configuration.URLCache = [AFImageDownloader defaultURLCache];

    return configuration;
}

- (instancetype)init {
    NSURLSessionConfiguration *defaultConfiguration = [self.class defaultURLSessionConfiguration];
    //创建了一个sessionManager，将用于基于AF自己封装的AFHTTPSessionManager的网络请求
    AFHTTPSessionManager *sessionManager = [[AFHTTPSessionManager alloc] initWithSessionConfiguration:defaultConfiguration];
    sessionManager.responseSerializer = [AFImageResponseSerializer serializer];

    return [self initWithSessionManager:sessionManager
                 downloadPrioritization:AFImageDownloadPrioritizationFIFO
                 maximumActiveDownloads:4
                             imageCache:[[AFAutoPurgingImageCache alloc] init]];//AFAutoPurgingImageCache的创建，这个类是AF做图片缓存用的
}

- (instancetype)initWithSessionManager:(AFHTTPSessionManager *)sessionManager
                downloadPrioritization:(AFImageDownloadPrioritization)downloadPrioritization
                maximumActiveDownloads:(NSInteger)maximumActiveDownloads
                            imageCache:(id <AFImageRequestCache>)imageCache {
    if (self = [super init]) {
        //持有
        self.sessionManager = sessionManager;
        //定义下载任务的顺序，默认FIFO，先进先出-队列模式，还有后进先出-栈模式
        self.downloadPrioritizaton = downloadPrioritization;
        //最大的下载数
        self.maximumActiveDownloads = maximumActiveDownloads;
        //自定义的cache
        self.imageCache = imageCache;

        //队列中的任务，待执行的
        self.queuedMergedTasks = [[NSMutableArray alloc] init];
        //合并的任务，所有任务的字典
        self.mergedTasks = [[NSMutableDictionary alloc] init];
        //活跃的request数
        self.activeRequestCount = 0;

        //用UUID来拼接名字
        NSString *name = [NSString stringWithFormat:@"com.alamofire.imagedownloader.synchronizationqueue-%@", [[NSUUID UUID] UUIDString]];
        //创建一个串行的请求queue，用来做内部生成task等，保证了线程安全问题
        self.synchronizationQueue = dispatch_queue_create([name cStringUsingEncoding:NSASCIIStringEncoding], DISPATCH_QUEUE_SERIAL);

        //创建并行响应queue，用来做网络请求完成的数据回调
        name = [NSString stringWithFormat:@"com.alamofire.imagedownloader.responsequeue-%@", [[NSUUID UUID] UUIDString]];
        self.responseQueue = dispatch_queue_create([name cStringUsingEncoding:NSASCIIStringEncoding], DISPATCH_QUEUE_CONCURRENT);
    }

    return self;
}

+ (instancetype)defaultInstance {
    static AFImageDownloader *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (nullable AFImageDownloadReceipt *)downloadImageForURLRequest:(NSURLRequest *)request
                                                        success:(void (^)(NSURLRequest * _Nonnull, NSHTTPURLResponse * _Nullable, UIImage * _Nonnull))success
                                                        failure:(void (^)(NSURLRequest * _Nonnull, NSHTTPURLResponse * _Nullable, NSError * _Nonnull))failure {
    return [self downloadImageForURLRequest:request withReceiptID:[NSUUID UUID] success:success failure:failure];
}

- (nullable AFImageDownloadReceipt *)downloadImageForURLRequest:(NSURLRequest *)request
                                                  withReceiptID:(nonnull NSUUID *)receiptID
                                                        success:(nullable void (^)(NSURLRequest *request, NSHTTPURLResponse  * _Nullable response, UIImage *responseObject))success
                                                        failure:(nullable void (^)(NSURLRequest *request, NSHTTPURLResponse * _Nullable response, NSError *error))failure {
    
    __block NSURLSessionDataTask *task = nil;
    
    //同步串行去做下载的事，生成一个task，这些事情都是在当前线程中串行同步做的，所以不用担心线程安全问题
    dispatch_sync(self.synchronizationQueue, ^{
        //一：首先做了一个url的判断，如果为空则直接返回失败Block
        
        //url字符串
        NSString *URLIdentifier = request.URL.absoluteString;
        if (URLIdentifier == nil) {//没Url
            if (failure) {//返回错误信息
                NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(request, nil, error);
                });
            }
            return;
        }
        
        //二：判断这个需要请求的url，是不是已经被生成的task中，如果是的话，则多添加一个回调处理就可以直接返回

        //从自己task字典中根据Url去取AFImageDownloaderMergedTask，里面有task id url等等信息
        AFImageDownloaderMergedTask *existingMergedTask = self.mergedTasks[URLIdentifier];
        if (existingMergedTask != nil) {//如果这个任务已经存在
            //回调处理，里面包含成功和失败Block和UUid，当task完成的时候，会调用我们添加的回调
            AFImageDownloaderResponseHandler *handler = [[AFImageDownloaderResponseHandler alloc] initWithUUID:receiptID success:success failure:failure];
            //添加handler
            [existingMergedTask addResponseHandler:handler];
            //给task赋值
            task = existingMergedTask.task;
            return;
        }
        
        // 三：接着根据缓存策略加载缓存，如果有缓存则从self.imageCache中直接返回缓存，否则继续往下走

        //根据request的缓存策略，加载缓存
        switch (request.cachePolicy) {
            //这3种情况都会去加载缓存
            case NSURLRequestUseProtocolCachePolicy:
            case NSURLRequestReturnCacheDataElseLoad:
            case NSURLRequestReturnCacheDataDontLoad: {
                //从cache中根据request拿数据
                UIImage *cachedImage = [self.imageCache imageforRequest:request withAdditionalIdentifier:nil];
                if (cachedImage != nil) {
                    if (success) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            success(request, nil, cachedImage);
                        });
                    }
                    return;
                }
                break;
            }
            default:
                break;
        }
        
        // 四：走到这说明没相同url的task（没有正在请求中的request），同时也没有cache，那么就开始一个新的task
        // 调用的是AFUrlSessionManager里的请求方法生成了一个task
        // 然后通过多线程并发self.responseQueue做了请求完成的处理
        // 响应处理完成，则调用safelyRemoveMergedTaskWithURLIdentifier把task从全局字典中移除
        // 接着循环这个task的responseHandlers，调用它的成功或者失败的回调，并且请求成功还往cache里添加了请求到的数据
        // 然后减少正在请求的任务数，并且开启下一个任务

        //走到这说明既，也没有cache，则开始请求
        NSUUID *mergedTaskIdentifier = [NSUUID UUID];
        //task
        NSURLSessionDataTask *createdTask;
        __weak __typeof__(self) weakSelf = self;

        //用sessionManager去请求，只是创建task，目前仍处于挂起状态
        createdTask = [self.sessionManager
                       dataTaskWithRequest:request
                       completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
                           
                           //在responseQueue中回调数据,初始化为并行queue
                           dispatch_async(self.responseQueue, ^{
                               __strong __typeof__(weakSelf) strongSelf = weakSelf;
                               
                               //拿到当前的task
                               AFImageDownloaderMergedTask *mergedTask = self.mergedTasks[URLIdentifier];
                               
                               //如果之前的task数组中，有这个请求的任务task，则从数组中移除
                               if ([mergedTask.identifier isEqual:mergedTaskIdentifier]) {
                                   //安全的移除，并返回当前被移除的AF task
                                   mergedTask = [strongSelf safelyRemoveMergedTaskWithURLIdentifier:URLIdentifier];
                                   
                                   if (error) {//请求错误
                                       //去遍历task所有响应的处理
                                       for (AFImageDownloaderResponseHandler *handler in mergedTask.responseHandlers) {
                                           
                                           if (handler.failureBlock) {
                                               //主线程，调用失败的Block
                                               dispatch_async(dispatch_get_main_queue(), ^{
                                                   handler.failureBlock(request, (NSHTTPURLResponse*)response, error);
                                               });
                                           }
                                       }
                                   } else {//成功
                                       //根据request，往cache里添加请求到的数据
                                       [strongSelf.imageCache addImage:responseObject forRequest:request withAdditionalIdentifier:nil];

                                       //去遍历task所有响应的处理
                                       for (AFImageDownloaderResponseHandler *handler in mergedTask.responseHandlers) {
                                           if (handler.successBlock) {
                                               //主线程，调用失败的Block
                                               dispatch_async(dispatch_get_main_queue(), ^{
                                                   handler.successBlock(request, (NSHTTPURLResponse*)response, responseObject);
                                               });
                                           }
                                       }
                                       
                                   }
                               }
                               //减少活跃的任务数
                               [strongSelf safelyDecrementActiveTaskCount];
                               //如果可以，则开启下一个任务
                               [strongSelf safelyStartNextTaskIfNecessary];
                           });
                       }];

        // 五：用NSUUID生成的唯一标识，去生成AFImageDownloaderResponseHandler，然后生成一个AFImageDownloaderMergedTask
        // 把上一步生成的createdTask和回调都绑定给这个AF自定义可合并回调的task
        // 然后这个task加到全局的task映射字典中，key为url
        
        //创建handler
        AFImageDownloaderResponseHandler *handler = [[AFImageDownloaderResponseHandler alloc] initWithUUID:receiptID
                                                                                                   success:success
                                                                                                   failure:failure];
        //创建task
        AFImageDownloaderMergedTask *mergedTask = [[AFImageDownloaderMergedTask alloc]
                                                   initWithURLIdentifier:URLIdentifier
                                                   identifier:mergedTaskIdentifier
                                                   task:createdTask];
        //添加handler
        [mergedTask addResponseHandler:handler];
        
        //往当前任务字典里添加任务
        self.mergedTasks[URLIdentifier] = mergedTask;


        // 六：判断当前正在下载的任务是否超过最大并行数，如果没有则开始下载，否则先加到等待的数组中去
        
        if ([self isActiveRequestCountBelowMaximumLimit]) {//如果小于最大并行数
            //则开始任务下载resume，把当前活跃的request数量+1
            [self startMergedTask:mergedTask];
        } else {
            //如果暂时不能下载，被加到等待下载的数组中去的话
            //会根据我们一开始设置的下载策略，是先进先出，还是后进先出，去插入这个下载任务
            [self enqueueMergedTask:mergedTask];
        }
        
        //拿到最终生成的task
        task = mergedTask.task;
    });
    
    // 七：最后判断这个mergeTask是否为空。
    // 不为空生成了一个AFImageDownloadReceipt，绑定了一个UUID。为空则返回nil
    if (task) {
        //创建一个AFImageDownloadReceipt并返回，里面就多一个receiptID（UUID）
        return [[AFImageDownloadReceipt alloc] initWithReceiptID:receiptID task:task];
    } else {
        //为空则返回nil
        return nil;
    }
}

//根据AFImageDownloadReceipt来取消任务，即对应一个响应回调
- (void)cancelTaskForImageDownloadReceipt:(AFImageDownloadReceipt *)imageDownloadReceipt {
    dispatch_sync(self.synchronizationQueue, ^{
        //拿到url
        NSString *URLIdentifier = imageDownloadReceipt.task.originalRequest.URL.absoluteString;
        
        //根据url拿到task
        AFImageDownloaderMergedTask *mergedTask = self.mergedTasks[URLIdentifier];
        
        //快速遍历查找某个下标，如果返回YES，则index为当前下标
        NSUInteger index = [mergedTask.responseHandlers indexOfObjectPassingTest:^BOOL(AFImageDownloaderResponseHandler * _Nonnull handler, __unused NSUInteger idx, __unused BOOL * _Nonnull stop) {
            return handler.uuid == imageDownloadReceipt.receiptID;
        }];

        if (index != NSNotFound) {
            //移除响应处理
            AFImageDownloaderResponseHandler *handler = mergedTask.responseHandlers[index];
            [mergedTask removeResponseHandler:handler];
            NSString *failureReason = [NSString stringWithFormat:@"ImageDownloader cancelled URL request: %@",imageDownloadReceipt.task.originalRequest.URL.absoluteString];
            NSDictionary *userInfo = @{NSLocalizedFailureReasonErrorKey:failureReason};
            NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:userInfo];
            
            //并调用失败block，原因为取消
            if (handler.failureBlock) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    handler.failureBlock(imageDownloadReceipt.task.originalRequest, nil, error);
                });
            }
        }

        //如果任务里的响应回调为空或者状态为挂起，则取消task,并且从字典中移除
        if (mergedTask.responseHandlers.count == 0 && mergedTask.task.state == NSURLSessionTaskStateSuspended) {
            [mergedTask.task cancel];
            [self removeMergedTaskWithURLIdentifier:URLIdentifier];
        }
    });
}

//移除task
- (AFImageDownloaderMergedTask*)safelyRemoveMergedTaskWithURLIdentifier:(NSString *)URLIdentifier {
    __block AFImageDownloaderMergedTask *mergedTask = nil;
    //用同步串行的形式，防止移除中出现重复移除一系列问题
    dispatch_sync(self.synchronizationQueue, ^{
        mergedTask = [self removeMergedTaskWithURLIdentifier:URLIdentifier];
    });
    return mergedTask;
}

//根据URLIdentifier移除task
- (AFImageDownloaderMergedTask *)removeMergedTaskWithURLIdentifier:(NSString *)URLIdentifier {
    AFImageDownloaderMergedTask *mergedTask = self.mergedTasks[URLIdentifier];
    [self.mergedTasks removeObjectForKey:URLIdentifier];
    return mergedTask;
}

//减少活跃的任务数
- (void)safelyDecrementActiveTaskCount {
    //回到串行queue
    dispatch_sync(self.synchronizationQueue, ^{
        if (self.activeRequestCount > 0) {
            self.activeRequestCount -= 1;
        }
    });
}

//如果可以，则开启下一个任务
- (void)safelyStartNextTaskIfNecessary {
    //回到串行queue
    dispatch_sync(self.synchronizationQueue, ^{
        //先判断并行数限制
        if ([self isActiveRequestCountBelowMaximumLimit]) {
            while (self.queuedMergedTasks.count > 0) {
                //获取数组中第一个task
                AFImageDownloaderMergedTask *mergedTask = [self dequeueMergedTask];
                //如果状态是挂起状态
                if (mergedTask.task.state == NSURLSessionTaskStateSuspended) {
                    [self startMergedTask:mergedTask];
                    break;
                }
            }
        }
    });
}

//开始下载
- (void)startMergedTask:(AFImageDownloaderMergedTask *)mergedTask {
    [mergedTask.task resume];
    
    //任务活跃数+1
    ++self.activeRequestCount;
}

//把任务先加到数组里
- (void)enqueueMergedTask:(AFImageDownloaderMergedTask *)mergedTask {
    switch (self.downloadPrioritizaton) {
        case AFImageDownloadPrioritizationFIFO://先进先出
            [self.queuedMergedTasks addObject:mergedTask];
            break;
        case AFImageDownloadPrioritizationLIFO://后进先出
            [self.queuedMergedTasks insertObject:mergedTask atIndex:0];
            break;
    }
}

- (AFImageDownloaderMergedTask *)dequeueMergedTask {
    AFImageDownloaderMergedTask *mergedTask = nil;
    mergedTask = [self.queuedMergedTasks firstObject];
    [self.queuedMergedTasks removeObject:mergedTask];
    return mergedTask;
}

//判断并行数限制
- (BOOL)isActiveRequestCountBelowMaximumLimit {
    return self.activeRequestCount < self.maximumActiveDownloads;
}

@end

#endif
