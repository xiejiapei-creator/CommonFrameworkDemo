// UIImageView+AFNetworking.m
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

#import "UIImageView+AFNetworking.h"

#import <objc/runtime.h>

#if TARGET_OS_IOS || TARGET_OS_TV

#import "AFImageDownloader.h"

@interface UIImageView (_AFNetworking)
@property (readwrite, nonatomic, strong, setter = af_setActiveImageDownloadReceipt:) AFImageDownloadReceipt *af_activeImageDownloadReceipt;
@end

@implementation UIImageView (_AFNetworking)

//绑定属性的get方法。AFImageDownloadReceipt类是一个事件响应的接受对象，包含一个task，一个uuid
- (AFImageDownloadReceipt *)af_activeImageDownloadReceipt {
    return (AFImageDownloadReceipt *)objc_getAssociatedObject(self, @selector(af_activeImageDownloadReceipt));
}

//绑定属性的set方法。这个属性就是我们这次下载任务相关联的信息
- (void)af_setActiveImageDownloadReceipt:(AFImageDownloadReceipt *)imageDownloadReceipt {
    objc_setAssociatedObject(self, @selector(af_activeImageDownloadReceipt), imageDownloadReceipt, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

#pragma mark -

@implementation UIImageView (AFNetworking)

+ (AFImageDownloader *)sharedImageDownloader {

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu"
    return objc_getAssociatedObject(self, @selector(sharedImageDownloader)) ?: [AFImageDownloader defaultInstance];
#pragma clang diagnostic pop
}

+ (void)setSharedImageDownloader:(AFImageDownloader *)imageDownloader {
    objc_setAssociatedObject(self, @selector(sharedImageDownloader), imageDownloader, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark -

- (void)setImageWithURL:(NSURL *)url {
    [self setImageWithURL:url placeholderImage:nil];
}

- (void)setImageWithURL:(NSURL *)url
       placeholderImage:(UIImage *)placeholderImage
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    //设置head的Accept类型为image
    [request addValue:@"image/*" forHTTPHeaderField:@"Accept"];

    [self setImageWithURLRequest:request placeholderImage:placeholderImage success:nil failure:nil];
}

- (void)setImageWithURLRequest:(NSURLRequest *)urlRequest
              placeholderImage:(UIImage *)placeholderImage
                       success:(void (^)(NSURLRequest *request, NSHTTPURLResponse * _Nullable response, UIImage *image))success
                       failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse * _Nullable response, NSError *error))failure
{
// 一：判断url是否为空，如果为空则取消task，设置为占位图
    
    if ([urlRequest URL] == nil) {//url为空，则取消
        //取消task
        [self cancelImageDownloadTask];
        
        //设置为占位图
        self.image = placeholderImage;
        
        return;
    }

// 二：
    //判断设置的当前回调的request和需要请求的request是不是为同一个，是的话为重复调用，直接返回即可
    if ([self isActiveTaskURLEqualToURLRequest:urlRequest]){
        return;
    }

    //开始请求前，先取消之前的task了，即解绑回调
    [self cancelImageDownloadTask];

// 三：如果有缓存则直接读缓存，没缓存用AFImageDownloader去请求图片
// 完成后，则调用成功或者失败的回调，并且置空属性self.af_activeImageDownloadReceipt，成功则还需设置图片
    
    //拿到downloader
    AFImageDownloader *downloader = [[self class] sharedImageDownloader];
    //拿到cache
    id <AFImageRequestCache> imageCache = downloader.imageCache;
    
    //获取cachedImage
    UIImage *cachedImage = [imageCache imageforRequest:urlRequest withAdditionalIdentifier:nil];
    if (cachedImage) {//有缓存
        if (success) {
            //成功回调
            success(urlRequest, nil, cachedImage);
        } else {
            //设置图片
            self.image = cachedImage;
        }
        //置空回调
        [self clearActiveDownloadInformation];
    } else {//无缓存
        //如果有占位图，先设置
        if (placeholderImage) {
            self.image = placeholderImage;
        }

        __weak __typeof(self)weakSelf = self;
        //去下载，并得到一个receipt，可以用来取消回调
        NSUUID *downloadID = [NSUUID UUID];
        AFImageDownloadReceipt *receipt;
        receipt = [downloader
                   downloadImageForURLRequest:urlRequest
                   withReceiptID:downloadID
                   success:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, UIImage * _Nonnull responseObject) {
                       __strong __typeof(weakSelf)strongSelf = weakSelf;
            
                       //判断receiptID和downloadID是否相同
                       if ([strongSelf.af_activeImageDownloadReceipt.receiptID isEqual:downloadID]) {
                           if (success) {
                               //成功回调
                               success(request, response, responseObject);
                           } else if(responseObject) {
                               //设置图片
                               strongSelf.image = responseObject;
                           }
                           //置空回调
                           [strongSelf clearActiveDownloadInformation];
                       }

                   }
                   failure:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, NSError * _Nonnull error) {
                       __strong __typeof(weakSelf)strongSelf = weakSelf;
            
                        //失败有failuerBlock就回调
                        if ([strongSelf.af_activeImageDownloadReceipt.receiptID isEqual:downloadID]) {
                            if (failure) {
                                failure(request, response, error);
                            }
                            //置空回调对象
                            [strongSelf clearActiveDownloadInformation];
                        }
                   }];
        //赋值
        self.af_activeImageDownloadReceipt = receipt;
    }
}

//取消task
- (void)cancelImageDownloadTask {
    if (self.af_activeImageDownloadReceipt != nil) {
        //取消事件回调响应
        [[self.class sharedImageDownloader] cancelTaskForImageDownloadReceipt:self.af_activeImageDownloadReceipt];
        //置空回调对象
        [self clearActiveDownloadInformation];
     }
}

// 置空回调对象
- (void)clearActiveDownloadInformation {
    self.af_activeImageDownloadReceipt = nil;
}

- (BOOL)isActiveTaskURLEqualToURLRequest:(NSURLRequest *)urlRequest {
    return [self.af_activeImageDownloadReceipt.task.originalRequest.URL.absoluteString isEqualToString:urlRequest.URL.absoluteString];
}

@end

#endif
