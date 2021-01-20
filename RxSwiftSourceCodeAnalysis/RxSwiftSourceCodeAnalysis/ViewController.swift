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
    var titleLabel: UILabel! = UILabel(frame: CGRect(x: 130, y: 200, width: 100, height: 50))
    let disposeBag = DisposeBag()
    let lock = NSLock()
    var array = NSMutableArray()
    var intervalObservable: Observable<Int>!
    var startAction: UIButton! = UIButton(frame: CGRect(x: 130, y: 300, width: 100, height: 50))
    var stopAction: UIButton! = UIButton(frame: CGRect(x: 130, y: 380, width: 100, height: 50))
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        createSubview()
       
        // RxSwift核心流程
        //coreProcess()
        
        // Scheduler调度者
        //scheduler()
        
        // Dispose销毁者
        //disposeIntervalObservable()
        //disposeLimitObservable()
    }
    
    // MARK: RxSwift核心流程
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
    
    // MARK: Scheduler调度者
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
    
    // MARK: Dispose销毁者
    func disposeIntervalObservable()
    {
        self.intervalObservable = Observable<Int>.interval(.seconds(1), scheduler: MainScheduler.init())
        
        let dispose = self.intervalObservable.subscribe(onNext:
        { (num) in
            self.titleLabel.text = String(num)
        })
        
        _ = self.stopAction.rx.tap.subscribe(onNext: {
            print("停止计时")
            dispose.dispose()
        })
    }
    
    func disposeLimitObservable()
    {
        // 创建序列
        let observable = Observable<Any>.create
        { (observer) -> Disposable in
            observer.onNext("谢佳培")
            observer.onCompleted()
            //observer.onError(...)
            // 在完成后就已经销毁了序列，不会再发送下面的信号了
            observer.onNext("王小清")
            return Disposables.create { print("销毁释放了")}
        }
        
        // 订阅信号
        let dispose = observable.subscribe(onNext: { (anything) in
            print("收到的内容为:\(anything)")
        }, onError: { (error) in
            print("错误信息:\(error)")
        }, onCompleted: {
            print("完成了")
        }) {
            print("销毁回调")
        }
        
        print("执行完毕")
        //dispose.dispose()
    }
    
    func createSubview()
    {
        actionButton.setTitle("按钮", for: .normal)
        actionButton.backgroundColor = .orange
        view.addSubview(actionButton)
        
        titleLabel.text = "文本"
        titleLabel.backgroundColor = .yellow
        view.addSubview(titleLabel)
        
        startAction.setTitle("开始计时器", for: .normal)
        startAction.backgroundColor = .orange
        view.addSubview(startAction)
        
        stopAction.setTitle("停止计时器", for: .normal)
        stopAction.backgroundColor = .orange
        view.addSubview(stopAction)
    }
}


