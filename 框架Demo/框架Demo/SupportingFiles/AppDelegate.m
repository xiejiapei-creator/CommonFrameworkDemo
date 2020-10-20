//
//  AppDelegate.m
//  框架Demo
//
//  Created by 谢佳培 on 2020/9/15.
//  Copyright © 2020 xiejiapei. All rights reserved.
//

#import "AppDelegate.h"
#import "YYModelDemoViewController.h"
#import "ReactiveDemoViewController.h"
#import "FMDBViewController.h"
#import "FMDBSimpleDemoViewController.h"

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    FMDBSimpleDemoViewController *rootVC = [[FMDBSimpleDemoViewController alloc] init];
    UINavigationController *mainNC = [[UINavigationController alloc] initWithRootViewController:rootVC];
    
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor whiteColor];
    self.window.rootViewController = mainNC;
    [self.window makeKeyAndVisible];

    return YES;
}

@end
