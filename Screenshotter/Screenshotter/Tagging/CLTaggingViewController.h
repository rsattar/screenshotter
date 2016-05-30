//
//  CLTaggingViewController.h
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

#import "Screenshot.h"
#import "Tag.h"


@class CLTaggingViewController;
@protocol CLTaggingViewControllerDelegate <NSObject>

@required
- (void)taggingViewControllerDidCancel:(CLTaggingViewController *)controller;
- (void)taggingViewController:(CLTaggingViewController *)controller didSaveItemsToFolder:(ScreenshotFolder *)folder alsoAddedToTag:(Tag *)tag;

@end


@interface CLTaggingViewController : UITableViewController

@property (weak, nonatomic) NSObject <CLTaggingViewControllerDelegate> *delegate;
@property (readonly, nonatomic) Tag *initialTag;
// Screenshots+Assets = Core-data based
@property (readonly, nonatomic) NSArray *screenshots;
@property (readonly, nonatomic) NSArray *assets;
// ScreenshotFiles == file-based (iCloud or local Documents)
@property (readonly, nonatomic) NSArray *screenshotFiles;

- (instancetype)initWithScreenshots:(NSArray *)screenshots assets:(NSArray *)assets initialTag:(Tag *)initialTag delegate:(NSObject <CLTaggingViewControllerDelegate>*)delegate;
- (instancetype)initWithScreenshotFiles:(NSArray *)screenshotFiles initialTag:(Tag *)initialTag delegate:(NSObject <CLTaggingViewControllerDelegate>*)delegate;

@end
