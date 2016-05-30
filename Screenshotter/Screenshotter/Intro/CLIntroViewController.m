//
//  CLIntroViewController.m
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

#import "CLIntroViewController.h"

#import "CLScreenshotterApplication.h"
#import <Photos/Photos.h>
#import "UIColor+Hex.h"

@interface CLIntroViewController ()

@property (weak, nonatomic) IBOutlet NSLayoutConstraint *appIconTopConstraint;
@property (weak, nonatomic) IBOutlet UIView *infoPanelView;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *infoPanelTopConstraint;
@property (weak, nonatomic) IBOutlet UIView *infoPanelTopInnerShadowView;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *infoPanelTopPadding;
@property (weak, nonatomic) IBOutlet UIButton *getStartedButton;
@property (weak, nonatomic) IBOutlet UIButton *byClusterButton;

@property (strong, nonatomic) UIViewController *launchScreenViewController;
@end

@implementation CLIntroViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
        CLLog(@"CLIntroViewController INIT");
    }
    return self;
}

- (void)dealloc
{
    CLLog(@"CLIntroViewController DEALLOC");
}

- (UIStatusBarStyle) preferredStatusBarStyle
{
    return UIStatusBarStyleDefault;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    if (self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        return UIInterfaceOrientationMaskAll;
    }
    return UIInterfaceOrientationMaskPortrait;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
{
    return UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate
{
    return NO;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    UIStoryboard *launchScreenStoryboard = [UIStoryboard storyboardWithName:@"LaunchScreen" bundle:nil];
    self.launchScreenViewController = [launchScreenStoryboard instantiateViewControllerWithIdentifier:@"LaunchScreen"];

    [self addChildViewController:self.launchScreenViewController];
    [self.view insertSubview:self.launchScreenViewController.view belowSubview:self.infoPanelView];
    self.launchScreenViewController.view.frame = self.view.bounds;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    CGFloat percentageOfHeight = 0.285;
    CGFloat viewHeight = CGRectGetHeight([UIScreen mainScreen].bounds);
    CGFloat infoPanelPadding = self.infoPanelTopPadding.constant;

    if (![CLScreenshotterApplication isTallPhoneScreen]) {
        // Hardcoded hack for short iPhones
        // Needed to fit all the bullet points in
        percentageOfHeight = 0.25;
    } else if (viewHeight > 568.0) {
        // iPhones 6
        infoPanelPadding = 50.0;
    }
    self.infoPanelTopPadding.constant = infoPanelPadding;

    CGFloat idealTopSpace = viewHeight * percentageOfHeight;
    self.infoPanelTopConstraint.constant = idealTopSpace;

    CGFloat appIconHeight = CGRectGetHeight(self.appIconView.bounds);
    CGFloat amountHidden = 45.0;
    CGFloat iconTopSpace = MAX(16.0, idealTopSpace+amountHidden-appIconHeight);
    self.appIconTopConstraint.constant = iconTopSpace;

    if (self.launchScreenViewController && self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact) {
        [self prepareUIForAnimationFromLaunchScreen];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [[Analytics sharedInstance] registerScreen:@"Intro"];

    if (self.launchScreenViewController && self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact) {
        [self animateFromLaunchScreen];
    } else {
        [self removeLaunchScreenUI];
    }
}


- (void)removeLaunchScreenUI
{
    if (!self.launchScreenViewController) {
        return;
    }
    [self.launchScreenViewController willMoveToParentViewController:nil];
    [self.launchScreenViewController removeFromParentViewController];
    [self.launchScreenViewController.view removeFromSuperview];
    self.launchScreenViewController = nil;
}


- (void)prepareUIForAnimationFromLaunchScreen
{
    // Set up our own UI to their start states
    self.getStartedButton.alpha = 0.0;
    self.byClusterButton.alpha = 0.0;
    self.infoPanelView.alpha = 0.0;
}


- (void)animateFromLaunchScreen
{
    CGFloat timeMultiplier = 1.0;
    //CGFloat timeMultiplier = 10.0;
    // We must use hardcoded TAGS here, because setting outlets in a Launch Screen storyboard
    // makes it not work as a launch screen anymore ಠ_ಠ
    UIView *launchScreenTitleLabel = [self.launchScreenViewController.view viewWithTag:5];
    UIView *launchScreenAppIcon = [self.launchScreenViewController.view viewWithTag:10];
    UIView *launchScreenTaglineLabel = [self.launchScreenViewController.view viewWithTag:15];
    UIView *launchScreenBackground = [self.launchScreenViewController.view viewWithTag:20];

    CGFloat originalInfoPanelTop = self.infoPanelTopConstraint.constant;
    // Position below screen
    self.infoPanelTopConstraint.constant = CGRectGetHeight(self.view.bounds);

    [self.view setNeedsUpdateConstraints];
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];

    // Hide the views occluding our own UI
    launchScreenBackground.alpha = 0.0;
    self.launchScreenViewController.view.backgroundColor = [UIColor clearColor];

    // Fade away the titlelabel and tagline
    [UIView animateWithDuration:0.35*timeMultiplier delay:0.0*timeMultiplier options:0 animations:^{
        launchScreenTitleLabel.alpha = 0.0;
        CGRect frame = launchScreenTitleLabel.frame;
        frame.origin.y += 5;
        launchScreenTitleLabel.frame = frame;
        launchScreenTaglineLabel.alpha = 0.0;
    } completion:nil];

    // Move the app icon up to the appropriate position
    CGRect finalIconFrameVCCoordinates = [self.appIconView convertRect:self.appIconView.bounds toView:self.view];
    CGRect finalIconFrameLaunchCoordinates = [launchScreenAppIcon.superview convertRect:finalIconFrameVCCoordinates fromView:self.view];
    self.appIconView.alpha = 0.0;
    [UIView animateWithDuration:0.65*timeMultiplier delay:0.35*timeMultiplier usingSpringWithDamping:0.8 initialSpringVelocity:2.0 options:0 animations:^{
        launchScreenAppIcon.frame = finalIconFrameLaunchCoordinates;
    } completion:^(BOOL finished) {
        self.appIconView.alpha = 1.0;
        [self removeLaunchScreenUI];
    }];

    // We hid the info panel as our start state, so ensure it's visible (off screen)
    self.infoPanelView.alpha = 1.0;
    [UIView animateWithDuration:0.65*timeMultiplier delay:0.55*timeMultiplier usingSpringWithDamping:0.8 initialSpringVelocity:2.0 options:0 animations:^{
        self.infoPanelTopConstraint.constant = originalInfoPanelTop;
        [self.view layoutIfNeeded];
    } completion:nil];

    [UIView animateWithDuration:0.35*timeMultiplier delay:0.8*timeMultiplier options:0 animations:^{
        self.getStartedButton.alpha = 1.0;
        self.byClusterButton.alpha = 1.0;
    } completion:nil];


}

#pragma mark - Actions

- (IBAction)onGetStartedButtonTapped:(id)sender
{
    CLLog(@"User tapped get started in intro");

    __weak CLIntroViewController *_weakSelf = self;
    if ([PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusNotDetermined) {
        CLLog(@"Asking user for photo permission");
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [_weakSelf.delegate introViewControllerDidRequestDismiss:_weakSelf];
            });
        }];
    } else {
        [_weakSelf.delegate introViewControllerDidRequestDismiss:_weakSelf];
    }
}

- (IBAction)onByClusterButtonTapped:(id)sender
{
    CLLog(@"User tapped 'By Cluster' button in intro");
    NSURL *clusterAppURL = [NSURL URLWithString:@"https://itunes.apple.com/us/app/cluster-private-spaces-for/id596595032?mt=8"];
    [[UIApplication sharedApplication] openURL:clusterAppURL];
}


#pragma mark - Setup

- (void) styleButtonWithNeutralStyle:(UIButton *)button;
{
    UIFont *font = [UIFont boldSystemFontOfSize:16.0f];

    [button.titleLabel setFont:font];
    [button setTitleColor:[UIColor colorWithRGBHex:0x000000] forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithRGBHex:0x333333] forState:UIControlStateDisabled];

    UIEdgeInsets buttonBgInsets = UIEdgeInsetsMake(22, 22, 22, 22);
    UIImage *buttonImage = [[UIImage imageNamed:@"flat_grey_button_bg"] resizableImageWithCapInsets:buttonBgInsets];
    [button setBackgroundImage:buttonImage forState:UIControlStateNormal];
}

- (void) styleButtonWithPrimaryStyle:(UIButton *)button;
{
    UIFont *font = [UIFont fontWithName:@"HelveticaNeue-Light" size:18.0];

    [button.titleLabel setFont:font];
    [button setTitleColor:[UIColor colorWithRGBHex:0xFFFFFF] forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithRGBHex:0xEEEEEE] forState:UIControlStateDisabled];

    UIEdgeInsets buttonBgInsets = UIEdgeInsetsMake(22, 22, 22, 22);
    UIImage *buttonImage = [[UIImage imageNamed:@"primary_button"] resizableImageWithCapInsets:buttonBgInsets];
    [button setBackgroundImage:buttonImage forState:UIControlStateNormal];
}
@end
