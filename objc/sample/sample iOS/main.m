//
//  main.m
//  sample iOS
//
//  Created by Elviss Strazdins on 26/11/2019.
//  Copyright © 2019 Elviss Strazdiņš. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"

int main(int argc, char* argv[])
{
    NSString* appDelegateClassName;
    @autoreleasepool
    {
        // Setup code that might create autoreleased objects goes here.
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
    }
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}
