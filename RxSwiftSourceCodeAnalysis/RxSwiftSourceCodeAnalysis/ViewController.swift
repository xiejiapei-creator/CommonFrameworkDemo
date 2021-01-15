//
//  ViewController.swift
//  RxSwiftSourceCodeAnalysis
//
//  Created by 谢佳培 on 2021/1/14.
//

import UIKit
import RxSwift
import RxCocoa

class ViewController: UIViewController
{

    override func viewDidLoad()
    {
        super.viewDidLoad()
       
        // RxSwift核心流程
        coreProcess()
    }
    
    // RxSwift核心流程
    func coreProcess()
    {
        // 1.创建序列
        let obserber = Observable<Any>.create
        { (obserber) -> Disposable in
            
            // 3.发送信号
            obserber.onNext("漫游在云海的鲸鱼")
            obserber.onCompleted()
            obserber.onError(NSError.init(domain: "unknowError", code: 1997, userInfo: nil))
            
            return Disposables.create()
        }
        
        // 2.订阅信号
        let _ = obserber.subscribe(
            onNext: { text in print("订阅公众号：\(text)")},
            onError: { (error) in print("订阅过程发生未知错误：\(error)")},
            onCompleted: { print("订阅完成") },
            onDisposed: { print("销毁观察者") })
    }
}



