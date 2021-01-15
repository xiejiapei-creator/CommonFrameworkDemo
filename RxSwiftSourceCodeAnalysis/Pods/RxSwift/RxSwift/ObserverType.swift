//
//  ObserverType.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/8/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

/// Supports push-style iteration over an observable sequence.
public protocol ObserverType {
    /// The type of elements in sequence that observer can observe.
    associatedtype Element

    /// Notify observer about sequence event.
    ///
    /// - parameter event: Event that occurred.
    func on(_ event: Event<Element>)
}

/// Convenience API extensions to provide alternate next, error, completed events
extension ObserverType
{
    // 等效于on（.next（element:element））的便利方法
    // 参数：要发送给观察者的下一个元素
    public func onNext(_ element: Element)
    {
        self.on(.next(element))
    }
    
    // 等同于on（.completed）的便利方法
    public func onCompleted()
    {
        self.on(.completed)
    }
    
    // 相当于on（.error）的便利方法
    // 参数：将错误发送给观察者
    public func onError(_ error: Swift.Error)
    {
        self.on(.error(error))
    }
}
