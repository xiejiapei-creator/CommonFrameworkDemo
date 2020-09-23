//
//  ReactiveDemoViewController.h
//  框架Demo
//
//  Created by 谢佳培 on 2020/9/16.
//  Copyright © 2020 xiejiapei. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <ReactiveObjC.h>

@interface ReactiveDemoViewController : UIViewController

@end

@interface FirstViewController : UIViewController

@end

@interface SecondViewController : UIViewController

/** 添加一个RACSubject代替代理 */
@property (nonatomic, strong) RACSubject *delegateSignal;

@end
 
