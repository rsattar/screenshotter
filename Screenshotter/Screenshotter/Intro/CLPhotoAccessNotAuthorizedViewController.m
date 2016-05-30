//
//  CLPhotoAccessNotAuthorizedViewController.m
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

#import "CLPhotoAccessNotAuthorizedViewController.h"

#import <Photos/Photos.h>

@interface CLPhotoAccessNotAuthorizedViewController ()

@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *cannotContinueLabel;

@end

@implementation CLPhotoAccessNotAuthorizedViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    if (self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        return UIInterfaceOrientationMaskAll;
    }
    return UIInterfaceOrientationMaskPortrait;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    PHAuthorizationStatus authorization = [PHPhotoLibrary authorizationStatus];
    if (authorization == PHAuthorizationStatusRestricted) {
        // Parental Restrictions (rare)
        self.titleLabel.text = NSLocalizedStringWithDefaultValue(@"notAuthorized.title.restricted",
                                                                 nil,
                                                                 [NSBundle mainBundle],
                                                                 @"You have restrictions preventing access to your screenshots.",
                                                                 @"Label describing that user has restrictions preventing access to their screenshots.");
    } else {
        // User usually denied, so just assume this is what happened here
        self.titleLabel.text = NSLocalizedStringWithDefaultValue(@"notAuthorized.title.denied",
                                                                 nil,
                                                                 [NSBundle mainBundle],
                                                                 @"You denied permissions to access your screenshots.",
                                                                 @"Label describing that user has denied permissions to access their screenshots.");
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [[Analytics sharedInstance] registerScreen:@"Not Authorized"];
}

- (IBAction)onGoSettingsButtonTapped:(id)sender {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
}
@end
