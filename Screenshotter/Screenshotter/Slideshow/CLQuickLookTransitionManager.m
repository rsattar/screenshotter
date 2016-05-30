//
//  CLQuickLookTransitionManager.m
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

#import "CLQuickLookTransitionManager.h"

#import "CLQuickLookViewController.h"
#import "CLScreenshotView.h"
#import "GenericSlideshowViewController.h"

@implementation CLQuickLookTransitionManager


// This is used for percent driven interactive transitions, as well as for container controllers that have companion animations that might need to
// synchronize with the main animation.
- (NSTimeInterval)transitionDuration:(id <UIViewControllerContextTransitioning>)transitionContext
{

    UIViewController *fromViewController = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIViewController *actualFromVC = fromViewController;
    if ([fromViewController isKindOfClass:[UINavigationController class]]) {
        UINavigationController *fromNavController = (UINavigationController *)fromViewController;
        actualFromVC = fromNavController.viewControllers.lastObject;
    }
    if ([actualFromVC isKindOfClass:[GenericSlideshowViewController class]]) {
        return 0.35;
    }

    return 0.35;
}


// This method can only  be a nop if the transition is interactive and not a percentDriven interactive transition.
- (void)animateTransition:(id <UIViewControllerContextTransitioning>)transitionContext
{
    UINavigationController *fromNavController = nil;
    UINavigationController *toNavController = nil;
    GenericSlideshowViewController *slideshowViewController = nil;

    UIViewController *fromViewController = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIViewController *actualFromVC = fromViewController;
    if ([fromViewController isKindOfClass:[UINavigationController class]]) {
        fromNavController = (UINavigationController *)fromViewController;
        actualFromVC = fromNavController.viewControllers.lastObject;

        if ([actualFromVC isKindOfClass:[GenericSlideshowViewController class]]) {
            slideshowViewController = (GenericSlideshowViewController *)actualFromVC;
            //actualFromVC = slideshowViewController.childViewControllers[slideshowViewController.viewIndex];
        }
    }
    UIViewController *toViewController = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    UIViewController *actualToVC = toViewController;
    if ([toViewController isKindOfClass:[UINavigationController class]]) {
        toNavController = (UINavigationController *)toViewController;
        actualToVC = toNavController.viewControllers.lastObject;

        if ([actualToVC isKindOfClass:[GenericSlideshowViewController class]]) {
            slideshowViewController = (GenericSlideshowViewController *)actualToVC;
            //actualToVC = slideshowViewController.childViewControllers[slideshowViewController.viewIndex];
        }
    }

    NSTimeInterval duration = [self transitionDuration:transitionContext];

    Screenshot *screenshot = self.screenshot;
    PHAsset *screenshotAsset = self.phAsset;
    ScreenshotFileInfo *screenshotFile = self.screenshotFile;

    if ([actualToVC isKindOfClass:[GenericSlideshowViewController class]]) {
        // --> Slideshow

        CGRect startRect = CGRectNull;
        if (screenshot) {
            startRect = [self.quickLookSourceDelegate rectForScreenshot:screenshot inView:transitionContext.containerView];
        } else if (screenshotFile) {
            startRect = [self.quickLookSourceDelegate rectForScreenshotFile:screenshotFile inView:transitionContext.containerView];
        }
        CGRect endRect = [transitionContext finalFrameForViewController:toViewController];

        if (!CGRectIsNull(startRect) && !CGRectIsNull(endRect)) {
            // w00t we can animate from the frame in!
            UIView *fadingBackgroundView = [[UIView alloc] initWithFrame:fromViewController.view.bounds];
            fadingBackgroundView.backgroundColor = [UIColor blackColor];
            fadingBackgroundView.alpha = 0.0;
            CLScreenshotView *animatingScreenshotView = [[CLScreenshotView alloc] initWithFrame:startRect];
            animatingScreenshotView.loadFullScreenImage = YES;
            if (screenshot) {
                [animatingScreenshotView setScreenshot:screenshot andAsset:screenshotAsset];
            } else if (screenshotFile) {
                [animatingScreenshotView setScreenshotFile:screenshotFile loadImmediately:YES];
            }

            toViewController.view.alpha = 0.0;

            [transitionContext.containerView addSubview:fadingBackgroundView];
            [transitionContext.containerView addSubview:animatingScreenshotView];
            [transitionContext.containerView addSubview:toViewController.view];

            // Hide cell that was tapped
            if (screenshot) {
                [self.quickLookSourceDelegate setVisibilityOfScreenshot:screenshot toVisible:NO];
            } else if (screenshotFile) {
                [self.quickLookSourceDelegate setVisibilityOfScreenshotFile:screenshotFile toVisible:NO];
            }

            [UIView animateWithDuration:duration*0.5 animations:^{
                fadingBackgroundView.alpha = 1.0;
            }];
            [UIView animateWithDuration:duration delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:1.0 options:0 animations:^{
                animatingScreenshotView.frame = endRect;
            } completion:^(BOOL finished) {
                toViewController.view.alpha = 1.0;
                [fadingBackgroundView removeFromSuperview];
                [animatingScreenshotView removeFromSuperview];
                if (screenshot) {
                    [self.quickLookSourceDelegate setVisibilityOfScreenshot:screenshot toVisible:YES];
                } else if (screenshotFile) {
                    [self.quickLookSourceDelegate setVisibilityOfScreenshotFile:screenshotFile toVisible:YES];
                }
                [transitionContext completeTransition:finished];
            }];
        } else {
            // Not enough info, just fade in
            [transitionContext.containerView addSubview:toViewController.view];
            toViewController.view.alpha = 0.0;
            CGRect startingRect = fromViewController.view.bounds;
            //startingRect = CGRectInset(startingRect, 150, 200);
            toViewController.view.frame = startingRect;

            [UIView animateWithDuration:duration animations:^{
                toViewController.view.alpha = 1.0;
                toViewController.view.frame = fromViewController.view.bounds;
            } completion:^(BOOL finished) {
                [transitionContext completeTransition:finished];
            }];
        }


    } else if ([actualFromVC isKindOfClass:[GenericSlideshowViewController class]]) {
        // Slideshow --> ?

        CGRect startRect = actualFromVC.view.bounds;
        CGRect endRect = CGRectNull;
        if (screenshot) {
            endRect = [self.quickLookSourceDelegate rectForScreenshot:screenshot inView:actualToVC.view];
        } else if (screenshotFile) {
            endRect = [self.quickLookSourceDelegate rectForScreenshotFile:screenshotFile inView:actualToVC.view];
        }

        if (!CGRectIsNull(startRect) && !CGRectIsNull(endRect)) {
            UIView *fadingBackgroundView = [[UIView alloc] initWithFrame:fromViewController.view.bounds];
            fadingBackgroundView.backgroundColor = [UIColor blackColor];
            fadingBackgroundView.alpha = 1.0;

            CLScreenshotView *animatingScreenshotView = [[CLScreenshotView alloc] initWithFrame:startRect];
            animatingScreenshotView.loadFullScreenImage = YES;
            animatingScreenshotView.imageView.image = self.screenshotView.imageView.image;
            if (screenshot) {
                [animatingScreenshotView setScreenshot:screenshot andAsset:screenshotAsset];
            } else if (screenshotFile) {
                [animatingScreenshotView setScreenshotFile:screenshotFile loadImmediately:YES];
            }

            [transitionContext.containerView addSubview:toViewController.view];
            [transitionContext.containerView addSubview:fadingBackgroundView];
            [transitionContext.containerView addSubview:animatingScreenshotView];
            //[transitionContext.containerView addSubview:fromViewController.view];

            // Hide cell we're going back to
            if (screenshot) {
                [self.quickLookSourceDelegate setVisibilityOfScreenshot:screenshot toVisible:NO];
            } else if (screenshotFile) {
                [self.quickLookSourceDelegate setVisibilityOfScreenshotFile:screenshotFile toVisible:NO];
            }

            toViewController.view.frame = [transitionContext finalFrameForViewController:toViewController];

            self.screenshotView.alpha = 0.0;
            [UIView animateWithDuration:duration*0.75 delay:0 options:0 animations:^{
                fadingBackgroundView.alpha = 0.0;
            } completion:nil];
            [UIView animateWithDuration:duration delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:1.0 options:0 animations:^{
                fromViewController.view.alpha = 0.0;
                animatingScreenshotView.frame = endRect;
            } completion:^(BOOL finished) {
                [fadingBackgroundView removeFromSuperview];
                [animatingScreenshotView removeFromSuperview];
                if (screenshot) {
                    [self.quickLookSourceDelegate setVisibilityOfScreenshot:screenshot toVisible:YES];
                } else if (screenshotFile) {
                    [self.quickLookSourceDelegate setVisibilityOfScreenshotFile:screenshotFile toVisible:YES];
                }
                [transitionContext completeTransition:finished];
            }];
        } else {

            [transitionContext.containerView insertSubview:toViewController.view atIndex:0];
            [UIView animateWithDuration:duration animations:^{
                fromViewController.view.alpha = 0.0;
            } completion:^(BOOL finished) {
                [transitionContext completeTransition:finished];
            }];
        }
    }
}

@end
