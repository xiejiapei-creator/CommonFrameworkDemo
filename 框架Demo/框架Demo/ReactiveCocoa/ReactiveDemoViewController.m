//
//  ReactiveDemoViewController.m
//  框架Demo
//
//  Created by 谢佳培 on 2020/9/16.
//  Copyright © 2020 xiejiapei. All rights reserved.
//

#import "ReactiveDemoViewController.h"
#import "RACReturnSignal.h"

@interface ReactiveDemoViewController ()

@property (nonatomic, strong) RACCommand *command;
@property (nonatomic, strong) UITextField *RACSchedulerTextField;
@property (nonatomic, strong) UILabel *RACSchedulerLabel;
@property (nonatomic, strong) UIImageView *RACSchedulerImageView;
@property (nonatomic, strong) UIButton *RACSchedulerButton;
@property (nonatomic, strong) UIButton *eventButton;
@property (nonatomic, strong) UITextField *eventTextField;
@property (nonatomic, strong) UITextField *macroTextField;
@property (nonatomic, strong) UILabel *macroLabel;
@property (nonatomic, strong) UITextField *filterTextField;
@property (nonatomic, strong) RACSubject *signal;
@property (nonatomic, strong) UITextField *mapTextField;
@property (nonatomic, strong) UITextField *combineTextField;
@property (nonatomic, strong) UITextView *combineTextView;
@property (nonatomic, strong) UIButton *combineButton;
@property (nonatomic, strong) UIButton *doNextButton;
@property (nonatomic, strong) UILabel *doNextLabel;
@property (nonatomic, strong) UIButton *weakifyButton;
@property (nonatomic, strong) UILabel *weakifyLabel;
@property (nonatomic, strong) UITextField *channelFirstTextField;
@property (nonatomic, strong) UITextField *channelSecondTextField;
@property (nonatomic, strong) NSString *channelString;
@property (nonatomic, copy) NSString *dataURL;

@end

@implementation ReactiveDemoViewController
{
    int i;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    i = 0;

    [self createChannelSubviews];
    [self wrongChannelDemo];
    //self.channelString = @"888888";
    self.channelFirstTextField.text = @"888888";
    NSLog(@"channelString的值为：%@",self.channelString);
    NSLog(@"channelFirstTextField的文本值为：%@",self.channelFirstTextField.text);
}

#pragma mark - RACSignal

// RACSignal的使用
- (void)RACSignalDemo
{
    // 1.创建信号
    RACSignal *single = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        // block调用时刻：每当有订阅者订阅信号，就会调用block
        
        NSLog(@"想");
        
        // 2.发送信号
        [subscriber sendNext:@"发送了信号"];
        
        NSLog(@"你");
        
        // 如果不再发送数据，最好发送信号完成，内部会自动调用[RACDisposable disposable]取消订阅信号
        [subscriber sendCompleted];
        
        // 执行完信号后进行的清理工作，如果不需要就返回 nil
        return [RACDisposable disposableWithBlock:^{
            // block调用时刻：当信号发送完成或者发送错误，就会自动执行这个block，取消订阅信号
            
            // 执行完Block后，当前信号就不再被订阅了
            NSLog(@"豆腐");
        }];
    }];
    
    NSLog(@"我");
    
    // 3.订阅信号，才会激活信号
    [single subscribeNext:^(id x) {
        // block调用时刻：每当有信号发出数据，就会调用block
        NSLog(@"吃");
        NSLog(@"信号的值：%@",x);
    }];
}

// RACDisposable的使用
- (void)RACDisposableDemo
{
    // 1.创建信号
    RACSignal * single = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        
        NSLog(@"想");
        // 2.发送信号
        [subscriber sendNext:@"发送了一个信号"];
        NSLog(@"你");
        
        //RACDisposable 手动移除订阅者
        return [RACDisposable disposableWithBlock:^{
            NSLog(@"豆腐");
        }];
    }];
    
    // 3.订阅信号
    NSLog(@"我");
    RACDisposable * disposable = [single subscribeNext:^(id x) {
        NSLog(@"吃");
        NSLog(@"信号的值：%@",x);
    }];
    
    // 4.手动移除订阅
    [disposable dispose];
}

// 自动删除订阅
- (RACSignal *)autoDeleteSubscription
{
    // 1.创建信号
    RACSignal *single = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        
        NSLog(@"想");
        // 2.发送信号
        [subscriber sendNext:@"发送了信号"];
        NSLog(@"你");
        
        // 4.发送完成，订阅自动移除
        [subscriber sendCompleted];
        
        // RACDisposable 手动移除订阅者
        return nil;
    }];
    
    NSLog(@"我");
    // 3.订阅信号
    [single subscribeNext:^(id x) {
        NSLog(@"吃");
        NSLog(@"信号的值：%@",x);
    }];
    
    return single;
}

#pragma mark - RACSubject

// RACSubject的使用
- (void)RACSubjectDemo
{
    // 1.创建信号
    RACSubject *subject = [RACSubject subject];
    
    // 2.订阅信号
    [subject subscribeNext:^(id x) {
        // block调用时刻：当信号发出新值，就会调用
        NSLog(@"第一个订阅者：%@",x);
    }];
    
    [subject subscribeNext:^(id x) {
        // block调用时刻：当信号发出新值，就会调用
        NSLog(@"第二个订阅者：%@",x);
    }];
    
    // 3.发送信号
    [subject sendNext:@"谢佳培"];
}

- (void)createAgentSubviews
{
    UIButton *button = [[UIButton alloc] initWithFrame:CGRectMake(150, 100, 100, 100)];
    button.backgroundColor = [UIColor blackColor];
    [button setTitle:@"替换代理" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(replaceAgent) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:button];
}

// 替换代理
- (void)replaceAgent
{
    FirstViewController *firstViewController = [[FirstViewController alloc] init];
    [self presentViewController:firstViewController animated:YES completion:nil];
}

// RACRelaySubject的使用
- (void)RACRelaySubjectDemo
{
    // 1.创建信号
    RACReplaySubject *replaySubject = [RACReplaySubject subject];
    
    // 2.发送信号
    [replaySubject sendNext:@1];
    [replaySubject sendNext:@2];
    
    // 3.订阅信号
    [replaySubject subscribeNext:^(id x) {
        NSLog(@"第一个订阅者接收到的数据为：%@",x);
    }];
    
    // 订阅信号
    [replaySubject subscribeNext:^(id x) {
        NSLog(@"第二个订阅者接收到的数据为：%@",x);
    }];
}

#pragma mark - RACCommand
 
// RACCommand的使用
- (void)RACCommandDemo
{
    // 1.创建命令
    RACCommand *command = [[RACCommand alloc] initWithSignalBlock:^RACSignal *(id input) {
        NSLog(@"执行命令");
        
        // 创建空信号。必须返回信号
        // return [RACSignal empty];
        
        // 2.创建信号，用来传递数据
        return [RACSignal createSignal:^RACDisposable *(id subscriber) {
            [subscriber sendNext:@"请求接口返回的数据"];
            
            // 数据传递完成，调用sendCompleted，这时命令才执行完毕
            [subscriber sendCompleted];
            
            return nil;
        }];
    }];
    
    // 强引用命令，不要被销毁，否则接收不到数据
    self.command = command;
    
    // 3.订阅RACCommand中的信号
    [command.executionSignals subscribeNext:^(id x) {
        [x subscribeNext:^(id x) {
            NSLog(@"订阅RACCommand中的信号：%@",x);
        }];
    }];
    
    // RAC高级用法
    // switchToLatest：获取signal of signals发出的最新信号，也就是可以直接拿到RACCommand中的信号
    [command.executionSignals.switchToLatest subscribeNext:^(id x) {
        NSLog(@"获取signal of signals发出的最新信号：%@",x);
    }];
    
    // 4.监听命令是否执行完毕，默认会来一次，可以直接跳过，skip表示跳过第一次信号
    [[command.executing skip:1] subscribeNext:^(id x) {
    
        if ([x boolValue] == YES)// 正在执行
        {
            NSLog(@"正在执行");
        }
        else// 执行完成
        {
            NSLog(@"执行完成");
        }
    }];
    
    // 5.执行命令
    [self.command execute:@1];
}

#pragma mark - RACMulticastConnection

// RACMulticastConnection的使用
- (void)RACMulticastConnectionDemo
{
    // 1.创建信号
    RACSignal *signal = [RACSignal createSignal:^RACDisposable *(id subscriber) {
        NSLog(@"发送请求");
        [subscriber sendNext:@1];
        return nil;
    }];
    
    // 2.创建连接
    RACMulticastConnection *connect = [signal publish];
    
    // 3.订阅信号
    // 没有激活信号，只是保存订阅者到数组，必须通过调用连接来一次性调用所有订阅者的sendNext:
    [connect.signal subscribeNext:^(id x) {
        NSLog(@"订阅者一的信号");
    }];
    
    [connect.signal subscribeNext:^(id x) {
        NSLog(@"订阅者二的信号");
    }];
    
    // 4.连接,激活信号
    [connect connect];
}

#pragma mark - RACTuple和RACSequence

// RACTuple和RACSequence的使用
- (void)RACTupleAndRACSequenceDemo
{
    // 1.遍历数组
    NSArray *numbers = @[@1,@2,@3,@4,@5];
    
    // numbers.rac_sequence：把数组转换成集合RACSequence
    // numbers.rac_sequence.signal：把集合RACSequence转换RACSignal信号类
    // 订阅信号，激活信号，会自动把集合中的所有值，遍历出来
    [numbers.rac_sequence.signal subscribeNext:^(id x) {
        NSLog(@"遍历数组：%@",x);
    }];
    
    // 2.遍历字典。遍历出来的键值对会包装成RACTuple(元组对象)
    NSDictionary *dict = @{@"name":@"谢佳培",@"birth":@1997};
    [dict.rac_sequence.signal subscribeNext:^(RACTuple *x) {
    
        // 解包元组，会把元组的值按顺序给参数里面的变量赋值
        RACTupleUnpack(NSString *key,NSString *value) = x;
        NSLog(@"key:%@，value:%@",key,value);
        
        // 相当于以下写法
        NSString *keyStr = x[0];
        NSString *valueStr = x[1];
        NSLog(@"keyStr:%@，valueStr:%@",keyStr,valueStr);
    }];
}

#pragma mark - 事件监听

- (void)createEventDemo
{
    self.eventButton = [[UIButton alloc] initWithFrame:CGRectMake(120, 100, 200, 100)];
    self.eventButton.backgroundColor = [UIColor blackColor];
    [self.eventButton setTitle:@"黑色按钮" forState:UIControlStateNormal];
    [self.view addSubview:self.eventButton];
    
    self.eventTextField = [[UITextField alloc] initWithFrame:CGRectMake(120, 300, 200, 100)];
    self.eventTextField.backgroundColor = [UIColor greenColor];
    [self.view addSubview:self.eventTextField];
}

- (void)monitoringEventsDemo
{
    // 代替代理
    [[self rac_signalForSelector:@selector(viewDidAppear:)] subscribeNext:^(id x) {
        NSLog(@"蒙奇 D 路飞");
    }];
    
    // 代替KVO
    UIScrollView *scrolView = [[UIScrollView alloc] initWithFrame:CGRectMake(200, 300, 200, 200)];
    scrolView.contentSize = CGSizeMake(200, 400);
    scrolView.backgroundColor = [UIColor greenColor];
    [self.view addSubview:scrolView];
    
    [[scrolView rac_valuesAndChangesForKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew observer:self] subscribeNext:^(id x) {
        NSLog(@"新值为：%@",x);
    }];
    
    // 监听事件
    [[self.eventButton rac_signalForControlEvents:UIControlEventTouchUpInside] subscribeNext:^(id x) {
        NSLog(@"按钮被点击了");
    }];
    
    // 代替通知
    [[[NSNotificationCenter defaultCenter] rac_addObserverForName:UIKeyboardWillShowNotification object:nil] subscribeNext:^(id x) {
        NSLog(@"键盘弹出");
    }];
    
    // 监听文本框文字改变
    [self.eventTextField.rac_textSignal subscribeNext:^(id x) {
        NSLog(@"文字改变了%@",x);
    }];
    
    RACSignal *firstRequest = [RACSignal createSignal:^RACDisposable *(id subscriber) {
        [subscriber sendNext:@"发送请求1"];
        return nil;
    }];
    
    RACSignal *secondRequest = [RACSignal createSignal:^RACDisposable *(id subscriber) {
        [subscriber sendNext:@"发送请求2"];
        return nil;
    }];
    
    // 同步信号。每个参数对应信号发出的数据
    [self rac_liftSelector:@selector(updateUIWithFirstRequestData:secondRequestData:) withSignalsFromArray:@[firstRequest,secondRequest]];
}

- (void)updateUIWithFirstRequestData:(id)firstData secondRequestData:(id)secondData
{
    NSLog(@"用于更新UI的数据：firstData_%@，secondData_%@",firstData,secondData);
}

#pragma mark - 宏

- (void)createWeakifySubviews
{
    self.doNextLabel = [[UILabel alloc] initWithFrame:CGRectMake(120, 100, 200, 100)];
    self.doNextLabel.textColor = [UIColor whiteColor];
    self.doNextLabel.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.doNextLabel];
    
    self.doNextButton = [[UIButton alloc] initWithFrame:CGRectMake(120, 320, 200, 100)];
    self.doNextButton.backgroundColor = [UIColor blackColor];
    [self.doNextButton setTitle:@"设置标签" forState:UIControlStateNormal];
    [self.view addSubview:self.doNextButton];
}

- (void)createMacroViews
{
    self.macroTextField = [[UITextField alloc] initWithFrame:CGRectMake(120, 300, 200, 100)];
    self.macroTextField.backgroundColor = [UIColor greenColor];
    [self.view addSubview:self.macroTextField];
    
    self.macroLabel = [[UILabel alloc] initWithFrame:CGRectMake(120, 100, 200, 100)];
    self.macroLabel.textColor = [UIColor whiteColor];
    self.macroLabel.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.macroLabel];
}

- (void)macroDemo
{
    // 只要文本框文字改变，就会修改label的文字
    RAC(self.macroLabel,text) = self.macroTextField.rac_textSignal;
    
    // 文本框文字长度大于4为红色背景，小于4为蓝色背景，textView同理
    RAC(self.macroTextField ,backgroundColor) = [self.macroTextField.rac_textSignal map:^id(NSString* value) {
        return value.length > 4 ? [UIColor redColor]:[UIColor blueColor];
    }];
    
    // view.center的值
    [RACObserve(self.view, center) subscribeNext:^(id x) {
        NSLog(@"view.center的值为：%@",x);
    }];
    
    // 把参数中的数据包装成元组
    RACTuple *tuple = RACTuplePack(@"谢佳培",@1997);
    
    // 解包元组，会把元组的值，按顺序给参数里面的变量赋值
    RACTupleUnpack(NSString *name,NSNumber *birth) = tuple;
    NSLog(@"name:%@，birth:%@",name,birth);
}

- (void)weakifyDemo
{
    @weakify(self);
    [[[self.weakifyButton rac_signalForControlEvents:(UIControlEventTouchUpInside)]
      doNext:^(id x) {
        @strongify(self);
        self.weakifyLabel.textColor = [UIColor redColor];
    }] subscribeNext:^(UIControl *x) {
        self.weakifyLabel.text = @"1314";
    }];
}

#pragma mark - 操作方法之映射

- (void)createMapSubView
{
    self.mapTextField = [[UITextField alloc] initWithFrame:CGRectMake(120, 300, 200, 100)];
    self.mapTextField.backgroundColor = [UIColor greenColor];
    [self.view addSubview:self.mapTextField];
}

// flattenMap的使用
- (void)flattenMapDemo
{
    // 创建源信号
    RACSubject *subject = [RACSubject subject];
    
    // 绑定信号
    RACSignal *bindSignal = [subject flattenMap:^RACSignal *(id value) {
        // block:只要源信号发送内容就会调用
        
        // value:就是源信号发送的内容
        NSString *str = [NSString stringWithFormat:@"%@",value];
        NSLog(@"源信号发送的内容为：%@",str);

        return [RACReturnSignal return:value];
        
    }];
    
    // 订阅绑定信号。flattenMap中返回的是什么信号，订阅的就是什么信号
    [bindSignal subscribeNext:^(id x) {
        NSLog(@"订阅的绑定信号收到的内容为：%@",x);
    }];
    
    // 源信号发送数据
    [subject sendNext:@"哪吒和孙悟空"];
}

// map的使用
- (void)mapDemo
{
    RACSubject *subject = [RACSubject subject];
    RACSignal *bindSignal = [subject map:^id(id value) {
        // 返回的类型，就是你需要映射的值
        return [NSString stringWithFormat:@"%@",value];
    }];
    
    [bindSignal subscribeNext:^(id x) {
        NSLog(@"神话英雄：%@",x);
    }];
    
    [subject sendNext:@"哪吒"];
    [subject sendNext:@"悟空"];
}

// map——颜色
- (void)mapColorDemo
{
    [[[self.mapTextField.rac_textSignal filter:^BOOL(NSString* value) {
        return value.length > 3 ? YES:NO;
    }] map:^id(NSString* value) {
        return value.length > 4 ? [UIColor redColor] : [UIColor blackColor];
    }] subscribeNext:^(UIColor* value) {
        self.mapTextField.backgroundColor = value;
    }];
}

#pragma mark - 操作方法之组合

- (void)createCombineSubviews
{
    self.combineTextField = [[UITextField alloc] initWithFrame:CGRectMake(120, 100, 200, 100)];
    self.combineTextField.backgroundColor = [UIColor greenColor];
    [self.view addSubview:self.combineTextField];
    
    self.combineTextView = [[UITextView alloc] initWithFrame:CGRectMake(120, 300, 200, 100)];
    self.combineTextView.backgroundColor = [UIColor redColor];
    [self.view addSubview:self.combineTextView];
    
    self.combineButton = [[UIButton alloc] initWithFrame:CGRectMake(120, 500, 200, 100)];
    self.combineButton.backgroundColor = [UIColor blackColor];
    [self.combineButton setTitle:@"黑色按钮" forState:UIControlStateNormal];
    [self.combineButton setTitleColor:[UIColor whiteColor] forState:UIControlStateDisabled];
    [self.combineButton setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [self.combineButton addTarget:self action:@selector(clickCombineButton) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.combineButton];
}

// concat的使用
- (void)concatDemo
{
    RACSignal *signalA = [RACSignal createSignal:^RACDisposable *(id subscriber) {
    
        // 发送信号
        [subscriber sendNext:@"山川"];
        // 第一个信号必须要调用sendCompleted
        [subscriber sendCompleted];
        return nil;
    }];
    
    RACSignal *signalB = [RACSignal createSignal:^RACDisposable *(id subscriber) {
    
        // 发送信号
        [subscriber sendNext:@"河流"];
        return nil;
    }];
    
    // 创建组合信号
    // concat: 按顺序去连接
    RACSignal *concatSignal = [signalA concat:signalB];
    
    // 订阅组合信号
    [concatSignal subscribeNext:^(id x) {
    
        // 既能拿到A信号的值，又能拿到B信号的值
        NSLog(@"组合信号的值：%@",x);
    }];
}

// then的使用
- (void)thenDemo
{
    RACSignal *signalA = [RACSignal createSignal:^RACDisposable *(id subscriber) {
        // 发送信号
        [subscriber sendNext:@"山川"];
        [subscriber sendCompleted];
        return nil;
    }];
    
    RACSignal *signalB = [RACSignal createSignal:^RACDisposable *(id subscriber) {
    
        // 发送信号
        [subscriber sendNext:@"河流"];
        return nil;
    }];
    
    // 创建组合信号
    // then: 忽略掉第一个信号所有值
    RACSignal *thenSignal = [signalA then:^RACSignal *{
        // 返回信号就是需要组合的信号
        return signalB;
    }];
    
    // 订阅信号
    [thenSignal subscribeNext:^(id x) {
        NSLog(@"组合信号值：%@",x);
    }];
}

// merge的使用
- (void)mergeDemo
{
    // 任意一个信号请求完成都会订阅到
    RACSubject *signalA = [RACSubject subject];
    RACSubject *signalB = [RACSubject subject];
    
    // 组合信号
    RACSignal *mergeSignal = [signalA merge:signalB];
    
    // 订阅信号
    [mergeSignal subscribeNext:^(id x) {
        // 任意一个信号发送内容都会来这个block
        NSLog(@"信号值：%@",x);
    }];
    
    // 发送数据
    [signalA sendNext:@"abc"];
    [signalB sendNext:@"123"];
}

// zipWith的使用
- (void)zipWithDemo
{
    RACSubject *signalA = [RACSubject subject];
    RACSubject *signalB = [RACSubject subject];
    
    // 压缩成一个信号，等所有信号都发送内容的时候才会调用
    // 当一个界面多个请求的时候，要等所有请求完成才能更新UI
    RACSignal *zipSignal = [signalA zipWith:signalB];
    
    // 订阅信号
    [zipSignal subscribeNext:^(id x) {
        NSLog(@"信号值为：%@",x);
    }];
    
    // 发送信号
    // 打印顺序是由压缩的信号顺序决定的，不是由发送信号的顺序决定的
    [signalB sendNext:@"123"];
    [signalA sendNext:@"abc"];
}

// combine的使用
- (void)combineDemo
{
    RACSignal *signalA = [RACSignal createSignal:^RACDisposable *(id subscriber) {
        [subscriber sendNext:@1];
        return nil;
    }];
    
    RACSignal *signalB = [RACSignal createSignal:^RACDisposable *(id subscriber) {
        [subscriber sendNext:@2];
        return nil;
    }];
    
    // 把两个信号组合成一个信号，跟zip一样，没什么区别
    RACSignal *combineSignal = [signalA combineLatestWith:signalB];
        [combineSignal subscribeNext:^(id x) {
        NSLog(@"信号值为：%@",x);
    }];
}

// combine的使用：textField和textView
- (void)combineTextFieldAndTextViewDemo
{
    RACSignal *mergeTwoSignal = [RACSignal combineLatest:@[self.combineTextField.rac_textSignal, self.combineTextView.rac_textSignal] reduce:^id(NSString * value1,NSString * value2) {
        
        return [NSNumber numberWithBool:([value1 isEqualToString:@"11111"] && [value2 isEqualToString:@"22222"])];
    }];
    
    RAC(self.combineButton, enabled) = [mergeTwoSignal map:^id(NSNumber* value) {
        return value;
    }];
}

- (void)clickCombineButton
{
    NSLog(@"齐天大圣");
}

#pragma mark - 操作方法之过滤

- (void)createFilterSubview
{
    self.filterTextField = [[UITextField alloc] initWithFrame:CGRectMake(120, 300, 200, 100)];
    self.filterTextField.backgroundColor = [UIColor greenColor];
    [self.view addSubview:self.filterTextField];
}

// filter的使用
- (void)filterDemo
{
    // 只有当我们文本框的内容长度大于5，才想要获取文本框的内容
    [[self.filterTextField.rac_textSignal filter:^BOOL(id value) {
        // value: 源信号的内容
        return [value length] > 5;
    }] subscribeNext:^(id x) {
        // 返回值就是过滤条件，只有满足这个条件才能获取到内容
        NSLog(@"过滤后的值为：%@",x);
    }];
}

// ignore的使用
- (void)ignoreDemo
{
    // ignore:忽略一些值
    // ignoreValues:忽略所有的值
    
    // 1.创建信号
    RACSubject *subject = [RACSubject subject];
    // 2.忽略值
    RACSignal *ignoreSignal = [subject ignore:@"456"];
    // 3.订阅信号
    [ignoreSignal subscribeNext:^(id x) {
        NSLog(@"忽略后的值为：%@",x);
    }];
    
    // 4.发送数据
    [subject sendNext:@"2"];
    [subject sendNext:@"456"];
    [subject sendNext:@"789"];
}

// distinctUntilChanged的使用
- (void)distinctUntilChangedDemo
{
    // distinctUntilChanged:如果当前的值跟上一个值相同，就不会被订阅到
    
    RACSubject *subject = [RACSubject subject];
    
    [[subject distinctUntilChanged] subscribeNext:^(id x) {
        NSLog(@"区别后的值为：%@",x);
    }];
    
    [subject sendNext:@1];
    [subject sendNext:@2];
    [subject sendNext:@2];
    [subject sendNext:@3];
}

// take的使用
- (void)takeDemo
{
    // 1.创建信号
    RACSubject *subject = [RACSubject subject];
    
    // 2、处理信号，订阅信号
    [[subject take:2] subscribeNext:^(id x) {
        NSLog(@"信号值为：%@",x);
    }];
    
    // 3.发送信号
    [subject sendNext:@1];
    [subject sendNext:@2];
    [subject sendNext:@3];
}

// takeLast的使用
- (void)takeLastDemo
{
    // 1.创建信号
    RACSubject *signal = [RACSubject subject];
    
    // 2、处理信号，订阅信号
    [[signal takeLast:1] subscribeNext:^(id x) {
        NSLog(@"信号值为：%@",x);
    }];
    
    // 3.发送信号
    [signal sendNext:@1];
    [signal sendNext:@2];
    [signal sendNext:@3];
    
    [signal sendCompleted];
}

// takeUntil的使用
- (void)takeUntilDemo
{
    RACSubject *subject = [RACSubject subject];
    RACSubject *signal = [RACSubject subject];
    
    [[subject takeUntil:signal] subscribeNext:^(id x) {
        NSLog(@"信号值为：%@",x);
    }];
    
    [subject sendNext:@1];
    [subject sendNext:@"abc"];
    [signal sendError:nil];
    [signal sendNext:@2];
    [signal sendNext:@3];
}

// skip的使用
- (void)skipDemo
{
    // skip;跳跃几个值
    RACSubject *subject = [RACSubject subject];
    
    [[subject skip:2] subscribeNext:^(id x) {
        NSLog(@"跳过后的值为：%@",x);
    }];
    
    [subject sendNext:@1];
    [subject sendNext:@2];
    [subject sendNext:@3];
}

#pragma mark - 操作方法之秩序

- (void)createOrderSubviews
{
    self.doNextLabel = [[UILabel alloc] initWithFrame:CGRectMake(120, 100, 200, 100)];
    self.doNextLabel.textColor = [UIColor whiteColor];
    self.doNextLabel.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.doNextLabel];
    
    self.doNextButton = [[UIButton alloc] initWithFrame:CGRectMake(120, 320, 200, 100)];
    self.doNextButton.backgroundColor = [UIColor blackColor];
    [self.doNextButton setTitle:@"设置标签" forState:UIControlStateNormal];
    [self.view addSubview:self.doNextButton];
}

// doNext和doCompleted的使用
- (void)orderDemo
{
    RACSignal *signal = [RACSignal createSignal:^RACDisposable *(id subscriber) {
        [subscriber sendNext:@123];
        [subscriber sendCompleted];
        return nil;
    }];
    
    [[[signal doNext:^(id x) {
        
        // 执行[subscriber sendNext:@123];之前会调用这个Block
        NSLog(@"doNext");
    }] doCompleted:^{
        
        // 执行[subscriber sendCompleted];之前会调用这个Block
        NSLog(@"doCompleted");
    }] subscribeNext:^(id x) {
        
        NSLog(@"信号值为：%@",x);
    }];
}

// doNext的使用
- (void)doNextDemo
{
    [[[self.doNextButton rac_signalForControlEvents:(UIControlEventTouchUpInside)]
      doNext:^(id x) {

        // 改变label的背景色
        self.doNextLabel.backgroundColor = [UIColor redColor];
    }] subscribeNext:^(UIControl *x) {

        // 改变label的文字
        self.doNextLabel.text = @"齐天大圣";
    }];
}

#pragma mark - 操作方法之线程

// deliverOn的使用
- (void)deliverOnDemo
{
    @weakify(self)
    [[[[[self autoDeleteSubscription] then:^RACSignal *{
        @strongify(self);
        
        return self.RACSchedulerTextField.rac_textSignal;
        
    }] filter:^BOOL(NSString* value) {
        
        return value.length > 3 ? YES : NO;
        
    }] deliverOn:[RACScheduler mainThreadScheduler]] subscribeNext:^(NSString * value) {
        @strongify(self);
        
        // 回到主线程更新UI
        self.RACSchedulerLabel.text = value;
        NSLog(@"当前线程为：%@，value为：%@",[NSThread currentThread],value);
        
    } error:^(NSError * _Nullable error) {
        NSLog(@"出错了：%@",error);
    }];
}

- (void)createRACSchedulerSubviews
{
    self.RACSchedulerLabel = [[UILabel alloc] initWithFrame:CGRectMake(120, 100, 200, 100)];
    self.RACSchedulerLabel.textColor = [UIColor whiteColor];
    self.RACSchedulerLabel.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.RACSchedulerLabel];
    
    self.RACSchedulerTextField = [[UITextField alloc] initWithFrame:CGRectMake(120, 300, 200, 100)];
    self.RACSchedulerTextField.backgroundColor = [UIColor greenColor];
    [self.view addSubview:self.RACSchedulerTextField];
    
    self.RACSchedulerImageView = [[UIImageView alloc] initWithFrame:CGRectMake(120, 500, 200, 200)];
    self.RACSchedulerImageView.backgroundColor = [UIColor grayColor];
    [self.view addSubview:self.RACSchedulerImageView];
    
    self.RACSchedulerButton = [[UIButton alloc] initWithFrame:CGRectMake(120, 720, 200, 100)];
    self.RACSchedulerButton.backgroundColor = [UIColor blackColor];
    [self.RACSchedulerButton setTitle:@"请求图片" forState:UIControlStateNormal];
    @weakify(self);
    [[[[self.RACSchedulerButton rac_signalForControlEvents:(UIControlEventTouchUpInside)]
       flattenMap:^RACSignal *(id value) {
        
        return [self RACRequestImage];
        
    }] deliverOn:[RACScheduler mainThreadScheduler]] subscribeNext:^(UIImage * image) {
        @strongify(self);
        
        self.RACSchedulerImageView.image = image;
    }];
    [self.view addSubview:self.RACSchedulerButton];
}

// RACScheduler的使用


// 使用系统的方法加载图片
- (void)requestImage
{
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(queue, ^{
        
        NSURL *imageURL = [NSURL URLWithString:@"https://ss0.bdstatic.com/70cFvHSh_Q1YnxGkpoWK1HF6hhy/it/u=2789775069,1607374561&fm=26&gp=0.jpg"];
        
        UIImage *image = [UIImage imageWithData:[NSData dataWithContentsOfURL:imageURL]];
        if (image != nil)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.RACSchedulerImageView.image = image;
            });
        }
    });
}

// 使用RAC方法请求图片
- (RACSignal *)RACRequestImage
{
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        
        NSURL *imageURL = [NSURL URLWithString:@"https://ss0.bdstatic.com/70cFvHSh_Q1YnxGkpoWK1HF6hhy/it/u=2789775069,1607374561&fm=26&gp=0.jpg"];
        UIImage *image = [UIImage imageWithData:[NSData dataWithContentsOfURL:imageURL]];
        
        [subscriber sendNext:image];
        [subscriber sendCompleted];
        
        return nil;
    }];
}

// 网络请求
- (RACSignal *)RACNetworkRequest
{
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self);
        
        // 网络请求
        NSURL *url = [NSURL URLWithString:self.dataURL];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        NSURLSession *session = [NSURLSession sharedSession];
        
        NSURLSessionTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            
            NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSLog(@"请求回来的数据为：%@",dict);
            
            NSString *nameString = dict[@"name"];
            
            if (error == nil)// 请求成功
            {
                // 发送信号
                [subscriber sendNext:nameString];
                // 结束发送
                [subscriber sendCompleted];
            }
            else// 请求失败
            {
                // 发送错误
                [subscriber sendError:error];
            }
        }];
        
        // 开启网络请求任务
        [task resume];
        return nil;
    }];
}

#pragma mark - 操作方法之时间

// timeout的使用
- (void)timeoutDemo
{
    RACSignal *signalA = [[RACSignal createSignal:^RACDisposable *(id subscriber) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [subscriber sendNext:@123];
        });
        return nil;
    }] timeout:1 onScheduler:[RACScheduler currentScheduler]];
    
    
    [signalA subscribeNext:^(id x) {
    
        // 模拟2秒后才会发送消息
        NSLog(@"信号值为：%@",x);
    } error:^(NSError *error) {
        // 1秒后超时会自动调用
        NSLog(@"错误为：%@",error);
    }];
}

// interval的使用
- (void)intervalDemo
{
    RACSignal *signal = [[RACSignal createSignal:^RACDisposable *(id subscriber) {
        [subscriber sendNext:@123];
        return nil;
    }] delay:2.0];// delay延迟发送next
    
    [signal subscribeNext:^(id x) {
        NSLog(@"信号值为：%@",x);
    }];
}

#pragma mark - 操作方法之重复

// retry的使用
- (void)retryDemo
{
    __block int i = 0;
    RACSignal *signal = [RACSignal createSignal:^RACDisposable *(id subscriber) {
    
        if (i == 5)
        {
            [subscriber sendNext:@"谢佳培"];
        }
        else
        {
            NSLog(@"这名字不好听");
            [subscriber sendError:nil];
        }
    
        i++;
    
        return nil;
    }];
    
    [[signal retry] subscribeNext:^(id x) {
        NSLog(@"信号值为：%@",x);
    } error:^(NSError *error) {
        NSLog(@"错误信息为：%@",error);
    }];
}

// replay的使用
- (void)replayDemo
{
    RACSignal *signal = [RACSignal createSignal:^RACDisposable *(id subscriber) {
    
        [subscriber sendNext:@123];
        [subscriber sendNext:@456];
        return nil;
    }];
    
    [[signal replay] subscribeNext:^(id x) {
        NSLog(@"信号值为：%@",x);
    }];
    
    [[signal replay] subscribeNext:^(id x) {
        NSLog(@"信号值为：%@",x);
    }];
}

// throttle的使用
- (void)throttleDemo
{
    RACSubject *signal = [RACSubject subject];
    _signal = signal;

    // 节流，在一定时间（1秒）内，不接收任何信号内容，过了这个时间（1秒）获取最后发送的信号内容发出
    [[signal throttle:1.0 valuesPassingTest:^BOOL(id next) {
        return YES;
    }] subscribeNext:^(id x) {
        NSLog(@"信号值为：%@",x);
    }];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [_signal sendNext:@(i)];
    i++;
}

#pragma mark - RAC双向绑定

- (void)createChannelSubviews
{
    self.channelFirstTextField = [[UITextField alloc] initWithFrame:CGRectMake(120, 100, 200, 100)];
    self.channelFirstTextField.backgroundColor = [UIColor greenColor];
    [self.view addSubview:self.channelFirstTextField];
    
    self.channelSecondTextField = [[UITextField alloc] initWithFrame:CGRectMake(120, 300, 200, 100)];
    self.channelSecondTextField.backgroundColor = [UIColor greenColor];
    [self.view addSubview:self.channelSecondTextField];
}

// rac_newTextChannel的使用
- (void)channelDemo
{
    [self.channelFirstTextField.rac_newTextChannel subscribe:self.channelSecondTextField.rac_newTextChannel];
    
    [self.channelSecondTextField.rac_newTextChannel subscribe:self.channelFirstTextField.rac_newTextChannel];
}

// 直接使用rac_newTextChannel实现UITextField的双向绑定是有隐患的
- (void)rac_newTextChannelBug
{
    // 使用rac_newTextChannel双向绑定
    RACChannelTo(self, channelString) = self.channelFirstTextField.rac_newTextChannel;
    
    // 监控键盘输入时候两个值的变化
    [self.channelFirstTextField.rac_textSignal subscribeNext:^(id x) {
        NSLog(@"channelString的值为：%@",self.channelString);
        NSLog(@"channelFirstTextField的文本值为：%@",x);
    }];
}

// 直接使用RACChannelTo实现UITextField的双向绑定是有隐患的
- (void)RACChannelToBug
{
    // 使用RACChannelTo双向绑定
    RACChannelTo(self, channelString) = RACChannelTo(self.channelFirstTextField, text);
    
    // 监控键盘输入时候两个值的变化
    [self.channelFirstTextField.rac_textSignal subscribeNext:^(id x) {
        NSLog(@"channelString的值为：%@",self.channelString);
        NSLog(@"channelFirstTextField的文本值为：%@",x);
    }];
}

// 正确解决方案
- (void)rightChannelDemo
{
    RACChannelTo(self, channelString) = RACChannelTo(self.channelFirstTextField, text);
    
    @weakify(self);
    [self.channelFirstTextField.rac_textSignal subscribeNext:^(NSString * _Nullable x) {
        @strongify(self);
        self.channelString = x;
        NSLog(@"channelString的值为：%@",self.channelString);
        NSLog(@"channelFirstTextField的文本值为：%@",x);
    }];
}

// 简化代码
- (void)rightChannelSimpleDemo
{
    RACChannelTo(self, channelString) = RACChannelTo(self.channelFirstTextField, text);
    [self.channelFirstTextField.rac_textSignal subscribe:RACChannelTo(self, channelString)];
}

// 错误解决方案
- (void)wrongChannelDemo
{
    RACChannelTo(self, channelString) = self.channelFirstTextField.rac_newTextChannel;
    
    // 当textField.text改变的时候，会回调这个block，然后再给string赋值，实现双向绑定
    @weakify(self);
    [self.channelFirstTextField.rac_textSignal subscribeNext:^(NSString * _Nullable x) {
        @strongify(self);
        self.channelString = x;
        NSLog(@"channelString的值为：%@",self.channelString);
        NSLog(@"channelFirstTextField的文本值为：%@",x);
    }];
}

@end

#pragma mark - 替换代理

@implementation FirstViewController

- (void)viewDidLoad
{
    UIButton *button = [[UIButton alloc] initWithFrame:CGRectMake(120, 300, 200, 100)];
    button.backgroundColor = [UIColor blackColor];
    [button setTitle:@"跳转到第二个控制器" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(butttonClick) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:button];
}

- (void)butttonClick
{
    // 1.创建第二个控制器
    SecondViewController *secondViewController = [[SecondViewController alloc] init];
    
    // 2.设置代理信号
    secondViewController.delegateSignal = [RACSubject subject];
    
    // 3.订阅代理信号
    [secondViewController.delegateSignal subscribeNext:^(id x) {
        NSLog(@"点击了通知按钮");
    }];
    
    // 4.跳转到第二个控制器
    [self presentViewController:secondViewController animated:YES completion:nil];
}

@end

@implementation SecondViewController

- (void)viewDidLoad
{
    UIButton *button = [[UIButton alloc] initWithFrame:CGRectMake(120, 500, 200, 100)];
    button.backgroundColor = [UIColor blackColor];
    [button setTitle:@"通知第一个控制器" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(notice) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:button];
}

// 监听第二个控制器按钮是否被点击，如果被点击了则通知第一个控制器
- (void)notice
{
    // 判断代理信号是否有值
    if (self.delegateSignal)
    {
        // 有值，才需要通知
        [self.delegateSignal sendNext:nil];
    }
}

@end


