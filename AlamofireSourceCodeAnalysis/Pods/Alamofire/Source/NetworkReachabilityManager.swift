//
//  NetworkReachabilityManager.swift
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

#if !(os(watchOS) || os(Linux))

import Foundation
import SystemConfiguration

open class NetworkReachabilityManager
{
    // 网络连接状态明显要比网络类型范围更大，因此又增加了两个选项
    public enum NetworkReachabilityStatus
    {
        // 表示当前的网络是未知的
        case unknown
        // 表示当前的网路不可达
        case notReachable
        // 在关联的ConnectionType上可以访问网络
        case reachable(ConnectionType)

        init(_ flags: SCNetworkReachabilityFlags)
        {
            guard flags.isActuallyReachable else { self = .notReachable; return }

            var networkStatus: NetworkReachabilityStatus = .reachable(.ethernetOrWiFi)

            if flags.isCellular { networkStatus = .reachable(.cellular) }

            self = networkStatus
        }

        // 对于手机而言，我们需要的连接类型就两种
        public enum ConnectionType
        {
            // 一种是WiFi网络
            case ethernetOrWiFi
            // 一种是蜂窝网络
            case cellular
        }
    }

    // 监听器类型实质是一个闭包。当网络状态改变时，闭包会被调用。闭包只有一个参数，为网络可达性状态
    public typealias Listener = (NetworkReachabilityStatus) -> Void

    /// Default `NetworkReachabilityManager` for the zero address and a `listenerQueue` of `.main`.
    public static let `default` = NetworkReachabilityManager()

    // MARK: - Properties

    // 当前网络是可达的，要么是蜂窝网络，要么是WiFi连接
    open var isReachable: Bool { isReachableOnCellular || isReachableOnEthernetOrWiFi }
    // 表明当前网络是通过蜂窝网络连接
    open var isReachableOnCellular: Bool { status == .reachable(.cellular) }
    // 表明当前网络是通过WiFi连接
    open var isReachableOnEthernetOrWiFi: Bool { status == .reachable(.ethernetOrWiFi) }
    
    
    // 返回当前的网络状态
    open var status: NetworkReachabilityStatus
    {
        flags.map(NetworkReachabilityStatus.init) ?? .unknown
    }

    // 监听器中代码执行所在的队列
    public let reachabilityQueue = DispatchQueue(label: "org.alamofire.reachabilityQueue")

    // 网络状态就是根据flags判断出来的
    open var flags: SCNetworkReachabilityFlags?
    {
        // 有了它才能获取flags
        var flags = SCNetworkReachabilityFlags()

        return (SCNetworkReachabilityGetFlags(reachability, &flags)) ? flags : nil
    }

    // 可达性
    private let reachability: SCNetworkReachability


    /// Mutable state storage.
    struct MutableState {
        /// A closure executed when the network reachability status changes.
        var listener: Listener?
        /// `DispatchQueue` on which listeners will be called.
        var listenerQueue: DispatchQueue?
        /// Previously calculated status.
        var previousStatus: NetworkReachabilityStatus?
    }



    /// Protected storage for mutable state.
    @Protected
    private var mutableState = MutableState()

    // MARK: - Initialization

    // 便利构造函数。通过传入一个主机地址验证可达性
    public convenience init?(host: String)
    {
        guard let reachability = SCNetworkReachabilityCreateWithName(nil, host) else { return nil }

        self.init(reachability: reachability)
    }

    // 依靠监听0.0.0.0来构造
    // 可达性将0.0.0.0视为一个特殊的地址，因为它会监听设备的路由信息，在 ipv4 和 ipv6 下都可以使用
    public convenience init?()
    {
        var zero = sockaddr()
        zero.sa_len = UInt8(MemoryLayout<sockaddr>.size)
        zero.sa_family = sa_family_t(AF_INET)

        guard let reachability = SCNetworkReachabilityCreateWithAddress(nil, &zero) else { return nil }

        self.init(reachability: reachability)
    }

    // 通过指定 SCNetworkReachability 来初始化
    private init(reachability: SCNetworkReachability)
    {
        self.reachability = reachability
    }

    // 在析构的时候会停止监听网络变化
    deinit
    {
        stopListening()
    }

    // MARK: - Listening

    // 开始监听网络状况。启动失败会返回 false
    @discardableResult //表明可以忽略返回值
    open func startListening(onQueue queue: DispatchQueue = .main,
                             onUpdatePerforming listener: @escaping Listener) -> Bool
    {
        stopListening()

        // 创建一个监听器
        $mutableState.write
        { state in
            state.listenerQueue = queue
            state.listener = listener
        }
        
        // 设置上下文
        var context = SCNetworkReachabilityContext(version: 0,
                                                   info: Unmanaged.passUnretained(self).toOpaque(),
                                                   retain: nil,
                                                   release: nil,
                                                   copyDescription: nil)
        // 创建回调函数
        let callback: SCNetworkReachabilityCallBack =
        { _, flags, info in
            guard let info = info else { return }
            // 获取 NetworkReachabilityManager 的实例对象
            let instance = Unmanaged<NetworkReachabilityManager>.fromOpaque(info).takeUnretainedValue()
            // 调用监听方法
            instance.notifyListener(flags)
        }
        
        // 注册队列
        let queueAdded = SCNetworkReachabilitySetDispatchQueue(reachability, reachabilityQueue)
        // 注册回调函数
        let callbackAdded = SCNetworkReachabilitySetCallback(reachability, callback, &context)

        // 通知网络状态发送改变
        if let currentFlags = flags
        {
            reachabilityQueue.async
            {
                self.notifyListener(currentFlags)
            }
        }

        return callbackAdded && queueAdded
    }

    // 停止监控网络状态
    open func stopListening()
    {
        // 取消回调
        SCNetworkReachabilitySetCallback(reachability, nil, nil)
        // 取消队列
        SCNetworkReachabilitySetDispatchQueue(reachability, nil)
        // 销毁监听器
        $mutableState.write
        { state in
            state.listener = nil
            state.listenerQueue = nil
            state.previousStatus = nil
        }
    }

    // MARK: - Internal - Listener Notification

    /// Calls the `listener` closure of the `listenerQueue` if the computed status hasn't changed.
    ///
    /// - Note: Should only be called from the `reachabilityQueue`.
    ///
    /// - Parameter flags: `SCNetworkReachabilityFlags` to use to calculate the status.
    func notifyListener(_ flags: SCNetworkReachabilityFlags) {
        let newStatus = NetworkReachabilityStatus(flags)

        $mutableState.write { state in
            guard state.previousStatus != newStatus else { return }

            state.previousStatus = newStatus

            let listener = state.listener
            state.listenerQueue?.async { listener?(newStatus) }
        }
    }
}

// MARK: -

extension NetworkReachabilityManager.NetworkReachabilityStatus: Equatable {}

extension SCNetworkReachabilityFlags {
    var isReachable: Bool { contains(.reachable) }
    var isConnectionRequired: Bool { contains(.connectionRequired) }
    var canConnectAutomatically: Bool { contains(.connectionOnDemand) || contains(.connectionOnTraffic) }
    var canConnectWithoutUserInteraction: Bool { canConnectAutomatically && !contains(.interventionRequired) }
    var isActuallyReachable: Bool { isReachable && (!isConnectionRequired || canConnectWithoutUserInteraction) }
    var isCellular: Bool {
        #if os(iOS) || os(tvOS)
        return contains(.isWWAN)
        #else
        return false
        #endif
    }

    /// Human readable `String` for all states, to help with debugging.
    var readableDescription: String {
        let W = isCellular ? "W" : "-"
        let R = isReachable ? "R" : "-"
        let c = isConnectionRequired ? "c" : "-"
        let t = contains(.transientConnection) ? "t" : "-"
        let i = contains(.interventionRequired) ? "i" : "-"
        let C = contains(.connectionOnTraffic) ? "C" : "-"
        let D = contains(.connectionOnDemand) ? "D" : "-"
        let l = contains(.isLocalAddress) ? "l" : "-"
        let d = contains(.isDirect) ? "d" : "-"
        let a = contains(.connectionAutomatic) ? "a" : "-"

        return "\(W)\(R) \(c)\(t)\(i)\(C)\(D)\(l)\(d)\(a)"
    }
}
#endif

 


