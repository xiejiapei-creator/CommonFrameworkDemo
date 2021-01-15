//
//  ObservableType.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 8/8/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

// 表示推送样式序列
public protocol ObservableType: ObservableConvertibleType
{
    func subscribe<Observer: ObserverType>(_ observer: Observer) -> Disposable where Observer.Element == Element
}

extension ObservableType
{
    // 将 observeType 转换为 observeable 的默认实现
    public func asObservable() -> Observable<Element>
    {
        // temporary workaround
        //return Observable.create(subscribe: self.subscribe)
        Observable.create { o in self.subscribe(o) }
    }
}
