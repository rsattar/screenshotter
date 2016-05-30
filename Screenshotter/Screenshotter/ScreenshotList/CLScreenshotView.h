//
//  CLScreenshotView.h
//  Screenshotter
//
//  Created by Rizwan Sattar on 1/26/14.
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

#import <AssetsLibrary/AssetsLibrary.h>
#import <Photos/Photos.h>
#import "Screenshot.h"

@interface CLScreenshotView : UIView

// Asset-based
@property (readonly, nonatomic) Screenshot *screenshot;
@property (readonly, nonatomic) PHAsset *phAsset;
// Or file-based
@property (readonly, nonatomic) ScreenshotFileInfo *screenshotFile;

@property (assign, nonatomic) BOOL loadFullScreenImage;

@property (readonly, nonatomic) UIImageView *imageView;

- (void)setScreenshot:(Screenshot *)screenshot andAsset:(PHAsset *)phAsset;
- (void)setScreenshotFile:(ScreenshotFileInfo *)screenshotFile loadImmediately:(BOOL)loadImmediately;
- (void)prepareForReuse;

@end
