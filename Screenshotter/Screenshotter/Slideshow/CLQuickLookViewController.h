//
//  CLQuickLookViewController.h
//  Screenshotter
//
//  Created by Rizwan Sattar on 2/21/14.
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

#import <UIKit/UIKit.h>

#import "CLScreenshotView.h"
#import <Photos/Photos.h>
#import "Screenshot.h"

@class CLQuickLookViewController;
@protocol CLQuickLookViewControllerDelegate <NSObject>

@required;
- (void)quickLookViewControllerDidRequestDismiss:(CLQuickLookViewController *)controller;

@end


@interface CLQuickLookViewController : UIViewController

@property (weak, nonatomic) NSObject <CLQuickLookViewControllerDelegate> *delegate;
@property (assign, nonatomic) BOOL dismissOnSingleTap;
@property (assign, nonatomic) BOOL animatingTransition;
// Asset-based
@property (readonly, nonatomic) Screenshot *screenshot;
@property (readonly, nonatomic) PHAsset *phAsset;
// Or file-based
@property (readonly, nonatomic) ScreenshotFileInfo *screenshotFile;

@property (readonly, nonatomic) CLScreenshotView *screenshotView;

- (void)setScreenshot:(Screenshot *)screenshot andAsset:(PHAsset *)phAsset;
- (void)setScreenshotFile:(ScreenshotFileInfo *)screenshotFile loadImmediately:(BOOL)loadImmediately;

@end
