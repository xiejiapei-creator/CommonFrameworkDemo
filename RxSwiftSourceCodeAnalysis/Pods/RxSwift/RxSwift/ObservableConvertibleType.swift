//
//  ObservableConvertibleType.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 9/17/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

// 可以转换为可观察序列的类型（observable<Element>）
public protocol ObservableConvertibleType
{
    // 序列中元素的类型
    associatedtype Element

    // 将 self 转换为 Observable 序列
    func asObservable() -> Observable<Element>
}
