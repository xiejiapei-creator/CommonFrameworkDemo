//
//  AnonymousDisposable.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 2/15/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

/// Represents an Action-based disposable.
///
/// When dispose method is called, disposal action will be dereferenced.
private final class AnonymousDisposable : DisposeBase, Cancelable
{
    public typealias DisposeAction = () -> Void

    private let disposed = AtomicInt(0)
    private var disposeAction: DisposeAction?

    /// - returns: Was resource disposed.
    public var isDisposed: Bool {
        isFlagSet(self.disposed, 1)
    }

    private init(_ disposeAction: @escaping DisposeAction)
    {
        // 保存了disposeAction闭包，就是外界传入的{ print("销毁释放了")}
        self.disposeAction = disposeAction
        super.init()
    }

    // Non-deprecated version of the constructor, used by `Disposables.create(with:)`
    fileprivate init(disposeAction: @escaping DisposeAction) {
        self.disposeAction = disposeAction
        super.init()
    }

    // 实现了Disposable协议里最重要的方法dispose
    fileprivate func dispose()
    {
        // 判断是否已经销毁过
        if fetchOr(self.disposed, 1) == 0
        {
            // 如果没有销毁过就执行销毁闭包{ print("销毁释放了")}
            if let action = self.disposeAction
            {
                self.disposeAction = nil
                action()
            }
        }
    }
}

extension Disposables
{
    public static func create(with dispose: @escaping () -> Void) -> Cancelable
    {
        // 创建了一个匿名的可销毁者
        AnonymousDisposable(disposeAction: dispose)
    }
}
