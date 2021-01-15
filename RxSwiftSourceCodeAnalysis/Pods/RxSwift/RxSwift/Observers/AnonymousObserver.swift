//
//  AnonymousObserver.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/8/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

// 内部观察者
final class AnonymousObserver<Element>: ObserverBase<Element>
{
    typealias EventHandler = (Event<Element>) -> Void
    
    private let eventHandler : EventHandler
    
    // 保存了外界传入的闭包
    init(_ eventHandler: @escaping EventHandler) {
#if TRACE_RESOURCES
        _ = Resources.incrementTotal()
#endif
        self.eventHandler = eventHandler
    }

    override func onCore(_ event: Event<Element>) {
        self.eventHandler(event)
    }
    
#if TRACE_RESOURCES
    deinit {
        _ = Resources.decrementTotal()
    }
#endif
}
