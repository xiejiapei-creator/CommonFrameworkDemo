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
    var actionButton: UIButton! = UIButton(frame: CGRect(x: 130, y: 100, width: 100, height: 50))
    var tittleLabel: UILabel! = UILabel(frame: CGRect(x: 130, y: 200, width: 100, height: 50))
    let disposeBag = DisposeBag()
    let lock = NSLock()
    var array = NSMutableArray()
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        createSubview()
       
        // RxSwift核心流程
        //coreProcess()
        
        // Scheduler调度者
        scheduler()
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
    
    // Scheduler调度者
    func scheduler()
    {
        // RXSwift内部处理了线程问题
        DispatchQueue.global().async
        {
            print("请求数据")
            self.actionButton.rx.tap
                .subscribe(onNext: { () in
                    print("点击了按钮，当前线程为：\(Thread.current)")
                })
                .disposed(by: self.disposeBag)
        }
    }
    
    
    
    func createSubview()
    {
        actionButton.setTitle("按钮", for: .normal)
        actionButton.backgroundColor = .orange
        view.addSubview(actionButton)
        
        tittleLabel.text = "文本"
        tittleLabel.backgroundColor = .yellow
        view.addSubview(tittleLabel)
    }
}




