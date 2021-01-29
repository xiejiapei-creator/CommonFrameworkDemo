//
//  Notifications.swift
//
//  Copyright (c) 2014-2018 Alamofire Software Foundation (http://alamofire.org/)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

// 用于指示通知名，在这里作用类似于一个命名空间
extension Request
{
    // 在 Request 继续运行的时候会发送通知，通知中含有此 Request
    public static let didResumeNotification = Notification.Name(rawValue: "org.alamofire.notification.name.request.didResume")
    // 在 Request 暂停的时候会发送通知，通知中含有此 Request
    public static let didSuspendNotification = Notification.Name(rawValue: "org.alamofire.notification.name.request.didSuspend")
    // 在 Request 取消的时候会发送通知，通知中含有此 Request
    public static let didCancelNotification = Notification.Name(rawValue: "org.alamofire.notification.name.request.didCancel")
    // 在 Request 完成的时候会发送通知，通知中含有此 Request
    public static let didFinishNotification = Notification.Name(rawValue: "org.alamofire.notification.name.request.didFinish")

    // 在 URLSessionTask 继续运行的时候会发送通知，通知中含有此 URLSessionTask 关联的 Request
    public static let didResumeTaskNotification = Notification.Name(rawValue: "org.alamofire.notification.name.request.didResumeTask")
    // 在 URLSessionTask 暂停的时候会发送通知，通知中含有此 URLSessionTask 关联的 Request
    public static let didSuspendTaskNotification = Notification.Name(rawValue: "org.alamofire.notification.name.request.didSuspendTask")
    // 在 URLSessionTask 取消的时候会发送通知，通知中含有此 URLSessionTask 关联的 Request
    public static let didCancelTaskNotification = Notification.Name(rawValue: "org.alamofire.notification.name.request.didCancelTask")
    // 在 URLSessionTask 完成的时候会发送通知，通知中含有此 URLSessionTask 关联的 Request
    public static let didCompleteTaskNotification = Notification.Name(rawValue: "org.alamofire.notification.name.request.didCompleteTask")
}

// MARK: -

extension Notification
{
    // 通过字典键值从通知的用户信息中获取到关联的Request
    public var request: Request?
    {
        userInfo?[String.requestKey] as? Request
    }

    // 传入通知名称和当前Request初始化通知
    init(name: Notification.Name, request: Request)
    {
        self.init(name: name, object: nil, userInfo: [String.requestKey: request])
    }
}

extension NotificationCenter
{
    // 传入通知名称和当前Request发送通知
    func postNotification(named name: Notification.Name, with request: Request)
    {
        let notification = Notification(name: name, request: request)
        post(notification)
    }
}

// 这里也是起到一个命名空间的作用，用于标记指定键值
extension String
{
    // 表示与通知关联的Request的用户信息字典键值
    fileprivate static let requestKey = "org.alamofire.notification.key.request"
}

// EventMonitor提供Alamofire通知发送的时机
public final class AlamofireNotifications: EventMonitor
{
    // 当Request收到resume调用时调用的事件
    public func requestDidResume(_ request: Request)
    {
        NotificationCenter.default.postNotification(named: Request.didResumeNotification, with: request)
    }

    // 当Request收到suspend调用时调用的事件
    public func requestDidSuspend(_ request: Request) {
        NotificationCenter.default.postNotification(named: Request.didSuspendNotification, with: request)
    }

    // 当Request收到cancel调用时调用的事件
    public func requestDidCancel(_ request: Request)
    {
        NotificationCenter.default.postNotification(named: Request.didCancelNotification, with: request)
    }

    // 当Request收到finish调用时调用的事件
    public func requestDidFinish(_ request: Request)
    {
        NotificationCenter.default.postNotification(named: Request.didFinishNotification, with: request)
    }

    // 在 URLSessionTask 继续运行的时候会发送通知，通知中含有此 URLSessionTask 关联的 Request
    public func request(_ request: Request, didResumeTask task: URLSessionTask)
    {
        NotificationCenter.default.postNotification(named: Request.didResumeTaskNotification, with: request)
    }

    // 在 URLSessionTask 暂停的时候会发送通知，通知中含有此 URLSessionTask 关联的 Request
    public func request(_ request: Request, didSuspendTask task: URLSessionTask)
    {
        NotificationCenter.default.postNotification(named: Request.didSuspendTaskNotification, with: request)
    }

    // 在 URLSessionTask 取消的时候会发送通知，通知中含有此 URLSessionTask 关联的 Request
    public func request(_ request: Request, didCancelTask task: URLSessionTask)
    {
        NotificationCenter.default.postNotification(named: Request.didCancelTaskNotification, with: request)
    }

    // 在 URLSessionTask 完成的时候会发送通知，通知中含有此 URLSessionTask 关联的 Request
    public func request(_ request: Request, didCompleteTask task: URLSessionTask, with error: AFError?)
    {
        NotificationCenter.default.postNotification(named: Request.didCompleteTaskNotification, with: request)
    }
}

 
