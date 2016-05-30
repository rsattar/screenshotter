//
//  GenericSlideshowViewController.h
//  Cluster
//
//  Created by Taylor Hughes on 2/5/13.
//  Copyright (c) 2013 Cluster Labs, Inc. All rights reserved.
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

typedef NS_ENUM(NSUInteger, GenericSlideshowSingleTapAction) {
    GenericSlideshowSingleTapActionNone,
    GenericSlideshowSingleTapActionToggleNavigationBar,
    GenericSlideshowSingleTapActionDismiss
};


@class GenericSlideshowViewController;
@protocol GenericSlideshowViewControllerDelegate <NSObject>

@required

- (NSUInteger) numberOfItemsInSlideshow:(GenericSlideshowViewController *)controller;
- (UIViewController *) viewControllerForItemAtIndex:(NSInteger)index;
- (void) slideshowDidRequestDismiss:(GenericSlideshowViewController *)controller animated:(BOOL)animated;

@optional
- (void) genericSlideShowViewController:(GenericSlideshowViewController *)controller
                  didDisplayItemAtIndex:(NSUInteger)index;

@end


@interface GenericSlideshowViewController : UIViewController <UIScrollViewDelegate>

@property (weak, nonatomic) NSObject <GenericSlideshowViewControllerDelegate> *delegate;

@property (assign, nonatomic) NSInteger itemIndex;
@property (readonly, nonatomic) NSInteger viewIndex;

@property (readonly, nonatomic) UIScrollView *scrollView;

- initWithFrame:(CGRect)frame;

- (void) invalidateItemCount;

- (void) removeCurrentItem;
- (UIViewController *) currentItemViewController;
- (void) navigateToItemIndex:(NSInteger)itemIndex;

// Protected methods
@property (assign, nonatomic) BOOL controlsVisible;
@property (assign, nonatomic) GenericSlideshowSingleTapAction singleTapAction;
- (void) setControlsVisible:(BOOL)controlsVisible animated:(BOOL)animated;
- (void) removeSubviewWhenSafe:(UIView*)view;
- (void) updateDisplayForCurrentItem;

// Protected, overridable methods
- (void) adjustItemViewControllerForCurrentLayout:(UIViewController *)itemViewController;

- (void) updateNavigationBarVisibleStateAnimated:(BOOL)animated;
- (void) adjustItemViewControllerToHideControls:(UIViewController*)itemViewController;
- (void) adjustItemViewControllerToShowControls:(UIViewController *)itemViewController;

- (void) currentItemDidChange;

- (void) prepareToDismissAnimated:(BOOL)animate;
- (void) dismissAnimated:(BOOL)animated;

@end
