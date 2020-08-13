//
//  JPViewController.m
//  JSPatch源码解析
//
//  Created by 谢佳培 on 2020/8/13.
//  Copyright © 2020 xiejiapei. All rights reserved.
//

#import "JPViewController.h"

@implementation JPViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    UIButton *btn = [[UIButton alloc] initWithFrame:CGRectMake(0, 100, [UIScreen mainScreen].bounds.size.width, 50)];
    [btn setTitle:@"Push JPTableViewController" forState:UIControlStateNormal];
    [btn addTarget:self action:@selector(handleBtn:) forControlEvents:UIControlEventTouchUpInside];
    [btn setBackgroundColor:[UIColor grayColor]];
    [self.view addSubview:btn];
}

- (void)handleBtn:(id)sender
{
  //output hello word
}



@end


