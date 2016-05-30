//
//  CLScreenshotListViewController.h
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
#import "CLQuickLookTransitionManager.h"

#import "Tag.h"

@class CLScreenshotListViewController;
@protocol CLScreenshotListViewControllerDelegate <NSObject>

@required
- (void)screenshotListViewControllerDidRequestDismiss:(CLScreenshotListViewController *)controller didDeleteTagOrFolder:(BOOL)didDeleteTagOrFolder animated:(BOOL)animated;

@end


@interface CLScreenshotListViewController : UIViewController <CLQuickLookTransitionManagerDelegate>

@property (weak, nonatomic) NSObject <CLScreenshotListViewControllerDelegate> *delegate;

@property (assign, nonatomic) BOOL showAllScreenshots;
@property (strong, nonatomic) Tag *tagToFilter;
@property (strong, nonatomic) NSString *folderName;

@end
