//
//  Cancelable.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 3/12/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

/// Represents disposable resource with state tracking.

// 实现了协议Cancelable
public protocol Cancelable : Disposable
{
    // 是否销毁了
    var isDisposed: Bool { get }
}
