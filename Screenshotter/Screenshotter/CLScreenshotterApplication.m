//
//  CLScreenshotterApplication.m
//  Screenshotter
//
//  Created by Rizwan Sattar on 2/11/14.
//  Copyright (c) 2014 Cluster Labs, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CLScreenshotterApplication.h"

#import <sys/utsname.h>

@implementation CLScreenshotterApplication


#pragma mark - System Information getters


+ (NSString *)softwareVersion
{
    return [[UIDevice currentDevice] systemVersion];
}


+ (NSString *)hardwareModel
{
    // See: http://stackoverflow.com/a/8304788/9849
    /*
     @"i386"      on the simulator
     @"iPod1,1"   on iPod Touch
     @"iPod2,1"   on iPod Touch Second Generation
     @"iPod3,1"   on iPod Touch Third Generation
     @"iPod4,1"   on iPod Touch Fourth Generation
     @"iPhone1,1" on iPhone
     @"iPhone1,2" on iPhone 3G
     @"iPhone2,1" on iPhone 3GS
     @"iPad1,1"   on iPad
     @"iPad2,1"   on iPad 2
     @"iPhone3,1" on iPhone 4
     @"iPhone4,1" on iPhone 4S
     */

    struct utsname systemInfo;

    uname(&systemInfo);

    NSString *modelName = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
    return modelName;
}


+ (NSString *)appId
{
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
}


+ (NSString *)appVersion
{

    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    return version;
}


+ (NSString *)appVersionAndBuildNumber
{

    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    NSString *buildNumber = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
    return [NSString stringWithFormat:@"%@ (%@)", version, buildNumber];
}


+ (NSString *)appEnvironment
{
    BOOL isProduction = YES;
#ifdef DEBUG
    isProduction = NO;
#endif
    return (isProduction ? @"production" : @"development");
}


+ (NSString *)userAgent
{
    // Prepare User-Agent string
    // Chrome: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_4) AppleWebKit/536.11 (KHTML, like Gecko) Chrome/20.0.1132.47 Safari/536.11
    // iOS Safari: Mozilla/5.0 (iPhone; CPU iPhone OS 5_0 like Mac OS X) AppleWebKit/534.46 (KHTML, like Gecko) Version/5.1 Mobile/9A334 Safari/7534.48.3
    // Example: com.getcluster.Cluster:1.0.4, 1.0.4.2:iPhone4,1:5.1.1
    // appId:appVersion:hardwareModel:softwareVersion
    NSString *userAgentString = [NSString stringWithFormat:@"%@:%@:%@:%@",
                                 [CLScreenshotterApplication appId],
                                 [CLScreenshotterApplication appVersionAndBuildNumber],
                                 [CLScreenshotterApplication hardwareModel],
                                 [CLScreenshotterApplication softwareVersion]];
    return userAgentString;
}


+ (BOOL)isTallPhoneScreen
{
    // TODO(Riz): Maybe put it into a dispatch_once?
    BOOL isTallIphoneScreen =  YES;
    if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
    {
        CGSize result = [[UIScreen mainScreen] bounds].size;
        if(result.height == 480)
        {
            // iPhone 4S
            isTallIphoneScreen = NO;
        }
    }
    return isTallIphoneScreen;
}


+ (BOOL)isPad
{
    static BOOL isPad = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{

        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
            isPad = YES;
        }
    });
    return isPad;
}

@end
