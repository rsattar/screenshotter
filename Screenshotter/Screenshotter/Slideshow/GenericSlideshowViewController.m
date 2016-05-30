//
//  GenericSlideshowViewController.m
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

#import "GenericSlideshowViewController.h"



@interface GenericSlideshowViewController () <UIGestureRecognizerDelegate>

@property (assign, nonatomic) NSInteger numItems;

@property (assign, nonatomic) BOOL hasAppeared;
@property (strong, nonatomic) UIScrollView *scrollView;

@property (strong, nonatomic) NSMutableArray *itemViewControllers;
@property (assign, nonatomic) NSInteger viewIndex;

@property (strong, nonatomic) NSMutableIndexSet *displayedItemIndexes;

@property (strong, nonatomic) NSMutableArray *subviewsToRemove;

@property (assign, nonatomic) BOOL ignoreNextScrollEvent;

@property (strong, nonatomic) UITapGestureRecognizer *singleTapGestureRecognizer;

@end


@implementation GenericSlideshowViewController


- (id) initWithFrame:(CGRect)frame
{
    self = [super init];
    if (self) {
        
        self.view = [[UIView alloc] initWithFrame:frame];
        self.view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;

        self.controlsVisible = YES;
        self.singleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onSingleTapGestureRecognizerFired:)];
        self.singleTapGestureRecognizer.delegate = self;
        [self.view addGestureRecognizer:self.singleTapGestureRecognizer];

        CGRect screenBounds = self.view.bounds;
        
        UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:screenBounds];
        scrollView.autoresizingMask = UIViewAutoresizingFlexibleHeight |
            UIViewAutoresizingFlexibleWidth;
        scrollView.delaysContentTouches = NO;
        scrollView.maximumZoomScale = 1.0;
        scrollView.minimumZoomScale = 1.0;
        scrollView.delegate = self;

        scrollView.pagingEnabled = YES;
        scrollView.showsHorizontalScrollIndicator = NO;
        scrollView.showsVerticalScrollIndicator = NO;
        scrollView.scrollsToTop = NO;
        
        self.scrollView = scrollView;
        [self.view addSubview:self.scrollView];
        
        self.displayedItemIndexes = [NSMutableIndexSet indexSet];
        self.numItems = -1;
        // Set these directly without invoking their setter logic
        _itemIndex = 0;
        _viewIndex = 0;

        self.automaticallyAdjustsScrollViewInsets = NO;
    }
    return self;
}


- (UIStatusBarStyle) preferredStatusBarStyle
{
    return UIStatusBarStyleDefault;
}


- (BOOL) prefersStatusBarHidden
{
    return !self.controlsVisible;
}


- (void) invalidateItemCount
{
    self.numItems = [self.delegate numberOfItemsInSlideshow:self];
    [self adjustItemViewControllersForCurrentViewIndex];
    [self updateDisplayForCurrentItem];
}


- (NSInteger) numItems
{
    if (_numItems < 0) {
        _numItems = [self.delegate numberOfItemsInSlideshow:self];
    }
    return _numItems;
}


- (CGFloat) widthBuffer
{
    if (self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact) {
        return 40.0;
    }
    return 10.0;
}


- (void) updateDisplayForCurrentItem
{
    NSString *title = @"No photos";
    if (self.numItems) {
        title = [NSString stringWithFormat:@"%ld of %lu", (long)(self.itemIndex + 1), (unsigned long)self.numItems];
    }
    self.navigationItem.title = title;
}


- (void) firstAppearanceSetup
{
    [self adjustItemViewControllersForCurrentViewIndex];
    
    [self updateDisplayForCurrentItem];

    // NOTE: If this is used in a non-modal fashion this can override the navigation bar's
    // translucency for others. Kind of annoying.
    self.navigationController.navigationBar.translucent = YES;

    [self updateNavigationBarVisibleStateAnimated:NO];
}


- (void) viewWillAppear:(BOOL)animated
{
    if (!self.hasAppeared) {
        [self invalidateItemCount];
        [self firstAppearanceSetup];
        self.hasAppeared = YES;
    }
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
}


- (void) viewWillDisappear:(BOOL)animated
{
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
}


- (void) viewDidLayoutSubviews
{
    //
    // Make the view slightly larger than the actual screen, so there's a gap between
    // each panel as we scroll through photos.
    // http://stackoverflow.com/questions/849383
    //
    CGRect frame = self.view.frame;
    CGFloat widthBuffer = [self widthBuffer];
    frame.size.width += widthBuffer;
    frame.origin.x = widthBuffer / 2.0 * -1.0;
    self.scrollView.frame = frame;
    [self repositionItemViewControllersMaintainingScrollOffset:NO];
}


- (void) setItemIndex:(NSInteger)itemIndex
{
    // Clamp the index to min and max
    // This is after seeing some abnormal behavior where
    // we set an itemIndex for, say, 4, and we have 0 items
    _itemIndex = MAX(0, MIN(itemIndex, self.numItems-1));

    [self updateDisplayForCurrentItem];
    [self currentItemDidChange];
}


- (void) navigateToItemIndex:(NSInteger)itemIndex
{
    self.itemIndex = itemIndex;
    self.viewIndex = 0;
    [self adjustItemViewControllersForCurrentViewIndex];

    [self updateDisplayForCurrentItem];
}


- (void) removeSubviewWhenSafe:(UIView*)view
{
    if (!_subviewsToRemove) {
        _subviewsToRemove = [NSMutableArray arrayWithObject:view];
    } else {
        [_subviewsToRemove addObject:view];
    }
}


- (void) prepareToDismissAnimated:(BOOL)animate
{
}


- (void) dismissAnimated:(BOOL)animated
{
    [self prepareToDismissAnimated:animated];
    [self.delegate slideshowDidRequestDismiss:self animated:animated];
}


#pragma mark - Handling single taps


- (void) onSingleTapGestureRecognizerFired:(UITapGestureRecognizer *)recognizer
{
    if (self.singleTapAction == GenericSlideshowSingleTapActionToggleNavigationBar) {
        [self setControlsVisible:!self.controlsVisible animated:YES];
    } else if (self.singleTapAction == GenericSlideshowSingleTapActionDismiss) {
        CLLog(@"Tapped slideshow to dismiss");
        [self dismissAnimated:YES];
    }
}


- (BOOL) gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    if ([otherGestureRecognizer isKindOfClass:[UITapGestureRecognizer class]]) {
        UITapGestureRecognizer *otherTapGestureRecognizer = (UITapGestureRecognizer *)otherGestureRecognizer;
        if (otherTapGestureRecognizer.numberOfTapsRequired > 1) {
            return YES;
        }
    }
    return NO;
}


#pragma mark - Hiding/showing controls


- (void) setControlsVisible:(BOOL)controlsVisible
{
    [self setControlsVisible:controlsVisible animated:NO];
}


- (void) setControlsVisible:(BOOL)controlsVisible animated:(BOOL)animated
{
    _controlsVisible = controlsVisible;
    [self updateNavigationBarVisibleStateAnimated:animated];

    void (^animationBlock)() = ^{
        self.view.backgroundColor = (_controlsVisible ? [UIColor whiteColor] : [UIColor blackColor]);
        for (UIViewController *vc in self.itemViewControllers) {
            if (_controlsVisible) {
                [self adjustItemViewControllerToShowControls:vc];
            } else {
                [self adjustItemViewControllerToHideControls:vc];
            }
        }
    };

    if (animated) {
        [UIView animateWithDuration:UINavigationControllerHideShowBarDuration animations:^{
            animationBlock();
        } completion:nil];
    } else {
        animationBlock();
    }
}


- (BOOL) shouldShowNavigationBar
{
    return _controlsVisible;
}


- (void) updateNavigationBarVisibleStateAnimated:(BOOL)animated
{
    BOOL shouldShowNavigationBar = [self shouldShowNavigationBar];

    // On iOS 7+, navigation bar hiding does a fade,
    // navigation bar showing does a slide.
    // Make them fade in both cases
    BOOL useCustomNavigationBarAnimation = NO;
    if (shouldShowNavigationBar) {
        // iOS 6 seems to slide always, which we don't want.
        useCustomNavigationBarAnimation = YES;
    }

    if (useCustomNavigationBarAnimation) {
        if (shouldShowNavigationBar) {
            // Use our custom fade in animation
            self.navigationController.navigationBarHidden = NO;
            self.navigationController.navigationBar.alpha = 0.0;
        }
    } else {
        // Use standard navigation bar hide animation
        [self.navigationController setNavigationBarHidden:!shouldShowNavigationBar animated:animated];
    }

    [self setNeedsStatusBarAppearanceUpdate];

    void (^animationBlock)() = ^{
        if (useCustomNavigationBarAnimation) {
            self.navigationController.navigationBar.alpha = shouldShowNavigationBar ? 1.0 : 0.0;
        }
    };

    void (^finishBlock)() = ^{
        if (useCustomNavigationBarAnimation && !shouldShowNavigationBar) {
            self.navigationController.navigationBarHidden = YES;
        }
    };

    if (animated) {
        [UIView animateWithDuration:UINavigationControllerHideShowBarDuration animations:^{
            animationBlock();
        } completion:^(BOOL finished) {
            finishBlock();
        }];
    } else {
        animationBlock();
        finishBlock();
    }
}


- (void) adjustItemViewControllerToHideControls:(UIViewController*)itemViewController
{
    // overrideable
}


- (void) adjustItemViewControllerToShowControls:(UIViewController*)itemViewController
{
    // overrideable
}


- (void) currentItemDidChange
{
    // overrideable
    if ([self.delegate respondsToSelector:@selector(genericSlideShowViewController:didDisplayItemAtIndex:)]) {
        [self.delegate genericSlideShowViewController:self
                                didDisplayItemAtIndex:self.itemIndex];
    }
}


#pragma mark - Item subviews


- (NSInteger) calculateViewIndex
{
    CGFloat pageWidth = self.scrollView.frame.size.width;
    int page = floor((self.scrollView.contentOffset.x - pageWidth / 2) / pageWidth) + 1;
    return page;
}


- (void) adjustItemViewControllersForCurrentViewIndex
{
    // No items. Empty view.
    NSInteger numItems = self.numItems;
    if (numItems == 0) {
        for (UIViewController *itemVC in self.itemViewControllers) {
            [self removeItemViewController:itemVC];
        }
        self.itemViewControllers = [NSMutableArray array];
        return;
    }
    
    UIViewController *myViewController = nil;
    if (self.viewIndex < self.itemViewControllers.count) {
        myViewController = [self.itemViewControllers objectAtIndex:self.viewIndex];
    }

    UIViewController *leftViewController = nil;
    BOOL needsLeftView = self.itemIndex > 0;
    NSInteger leftViewIndex = self.viewIndex - 1;
    if (needsLeftView && leftViewIndex >= 0 && leftViewIndex < self.itemViewControllers.count) {
        leftViewController = [self.itemViewControllers objectAtIndex:leftViewIndex];
    }

    UIViewController *rightViewController = nil;
    BOOL needsRightView = self.itemIndex + 1 < numItems;
    NSInteger rightViewIndex = self.viewIndex + 1;
    if (needsRightView && rightViewIndex < self.itemViewControllers.count) {
        rightViewController = [self.itemViewControllers objectAtIndex:rightViewIndex];
    }

    NSMutableArray *itemViewControllers = [NSMutableArray arrayWithCapacity:3];
    CGRect itemBounds = self.scrollView.bounds;
    itemBounds.size.width += [self widthBuffer];

    if (needsLeftView) {
        if (!leftViewController) {
            leftViewController = [self createItemViewControllerForIndex:self.itemIndex - 1 withFrame:itemBounds];
            [self addItemViewController:leftViewController];
        }
        [itemViewControllers addObject:leftViewController];
    }
    
    if (!myViewController) {
        myViewController = [self createItemViewControllerForIndex:self.itemIndex withFrame:itemBounds];
        [self addItemViewController:myViewController];
    }
    [itemViewControllers addObject:myViewController];

    if (needsRightView) {
        if (!rightViewController) {
            rightViewController = [self createItemViewControllerForIndex:self.itemIndex + 1 withFrame:itemBounds];
            [self addItemViewController:rightViewController];
        }
        [itemViewControllers addObject:rightViewController];
    }
    
    for (UIViewController *itemVC in self.itemViewControllers) {
        NSUInteger index = [itemViewControllers indexOfObject:itemVC];
        if (index == NSNotFound) {
            [self removeItemViewController:itemVC];
        }
    }
    
    self.itemViewControllers = itemViewControllers;
    if (self.itemIndex == 0) {
        self.viewIndex = 0;
    } else {
        self.viewIndex = 1;
    }
    
    [self repositionItemViewControllersMaintainingScrollOffset:YES];
}


- (void) addItemViewController:(UIViewController *)viewController
{
    [self addChildViewController:viewController];
    [self.scrollView addSubview:viewController.view];
}


- (void) removeItemViewController:(UIViewController *)viewController
{
    [viewController willMoveToParentViewController:nil];
    [viewController removeFromParentViewController];
    [viewController.view removeFromSuperview];
}


- (void) repositionItemViewControllersMaintainingScrollOffset:(BOOL)maintainScrollOffset
{
    //NSLog(@"Repositioning subviews...");
    NSInteger subviewCount = self.itemViewControllers.count;
    
    CGRect bounds = self.scrollView.bounds;
    CGFloat widthBuffer = [self widthBuffer];
    
    self.scrollView.contentSize = CGSizeMake(bounds.size.width * subviewCount, bounds.size.height);
    
    for (NSInteger i = 0; i < subviewCount; i++) {
        UIViewController *itemVC = [self.itemViewControllers objectAtIndex:i];
        itemVC.view.frame = CGRectMake(bounds.size.width * i + widthBuffer / 2.0, 0,
                                       bounds.size.width - widthBuffer, bounds.size.height);
        [self adjustItemViewControllerForCurrentLayout:itemVC];
    }

    CGFloat leftOffset = 0.0;
    if (maintainScrollOffset) {
        CGPoint currentOffset = self.scrollView.contentOffset;

        CGFloat halfPanel = bounds.size.width / 2.0;
        leftOffset = currentOffset.x;
        while (leftOffset > halfPanel) {
            leftOffset -= bounds.size.width;
        }
    }
    
    self.scrollView.contentOffset = CGPointMake((bounds.size.width * self.viewIndex) - leftOffset, 0);
}


- (void) removeCurrentItem
{
    UIViewController *itemViewController = [self.itemViewControllers objectAtIndex:self.viewIndex];
    [self removeItemViewController:itemViewController];
    [self.itemViewControllers removeObjectAtIndex:self.viewIndex];

    // Adjust our model locally
    self.numItems--;
    
    NSMutableIndexSet *oldIndexes = self.displayedItemIndexes;
    self.displayedItemIndexes = [NSMutableIndexSet indexSet];
    [oldIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop){
        if (idx == self.itemIndex) {
            return;
        }
        if (idx > self.itemIndex) {
            idx -= 1;
        }
        [self.displayedItemIndexes addIndex:idx];
    }];

    // Adjust these indexes AFTER the preparedIndexes change.
    if (self.viewIndex > 0) {
        self.viewIndex -= 1;
    }
    if (self.itemIndex > 0) {
        self.itemIndex -= 1;
    } else {
        // Be sure to update the current item even if the index didn't change.
        [self currentItemDidChange];
    }

    [self adjustItemViewControllersForCurrentViewIndex];
    if (self.numItems == 0) {
        [self dismissAnimated:YES];
    } else {
        [self updateDisplayForCurrentItem];
    }

}


- (UIViewController*) currentItemViewController
{
    if (!self.numItems) {
        return nil;
    }
    return [self.itemViewControllers objectAtIndex:self.viewIndex];
}


#pragma mark - Item-type-specific things


- (UIViewController *)createItemViewControllerForIndex:(NSInteger)index withFrame:(CGRect)frame
{
    UIViewController *itemViewController = [self.delegate viewControllerForItemAtIndex:index];
    itemViewController.view.frame = frame;
    if (!self.controlsVisible) {
        [self adjustItemViewControllerToHideControls:itemViewController];
    }
    return itemViewController;
}


- (void) adjustItemViewControllerForCurrentLayout:(UIViewController *)itemViewController
{
    // to be overriding
}


- (BOOL) currentItemViewControllerIsZoomedIn
{
    // to be overriding
    return NO;
}


#pragma mark - UIScrollViewDelegate - scrolling


- (void) maybeTriggerReorg
{
    NSInteger viewIndex = [self calculateViewIndex];
    if (viewIndex != self.viewIndex) {
        self.itemIndex += (viewIndex - self.viewIndex);
        self.viewIndex = viewIndex;

        [self adjustItemViewControllersForCurrentViewIndex];
        
        for (UIView *view in _subviewsToRemove) {
            [view removeFromSuperview];
        }
        _subviewsToRemove = nil;
    }
}


- (void) scrollViewWillBeginDragging:(UIScrollView *)scrollView
{

    if (scrollView == self.scrollView) {
        [self maybeTriggerReorg];
    }
}


- (void) scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{

    if (scrollView == self.scrollView) {
        [self maybeTriggerReorg];
    }
}


- (void) scrollViewDidScroll:(UIScrollView *)scrollView
{
    if (scrollView == self.scrollView) {
        CGSize size = self.scrollView.frame.size;
        CGFloat left = size.width * self.viewIndex;
        if (self.scrollView.contentOffset.x > left) {
            // Prepare next item, hide previous item
            //[self maybeAppearItemAtOffset:1];
            //[self maybeDisappearItemAtOffset:-1];
        } else if (self.scrollView.contentOffset.x < left) {
            // Prepare item at -1, maybe hide item at 1
            //[self maybeAppearItemAtOffset:-1];
            //[self maybeDisappearItemAtOffset:1];
        } else {
            // Maybe hide item at -1 and 1
            //[self maybeDisappearItemAtOffset:-1];
            //[self maybeDisappearItemAtOffset:1];
        }
    }
}
@end
