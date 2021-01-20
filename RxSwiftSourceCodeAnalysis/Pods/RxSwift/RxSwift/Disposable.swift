//
//  Disposable.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/8/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

/// Represents a disposable resource.

// 实现Disposable协议里最重要的方法dispose
public protocol Disposable
{
    func dispose()
}
