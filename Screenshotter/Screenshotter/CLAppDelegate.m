//
//  CLAppDelegate.m
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

#import "CLAppDelegate.h"

@import Firebase;

#import "CLIntroViewController.h"
#import "CLPhotoAccessNotAuthorizedViewController.h"
#import "CLScreenshotGroupsViewController.h"
#import "CLScreenshotsLoader.h"
#import <Photos/Photos.h>
#import "Screenshot.h"
#import "ScreenshotCatalog.h"
#import "Screenshotter-Swift.h"
#import "UIColor+Hex.h"

static NSString *const HAS_LAUNCHED_BEFORE_KEY = @"hasLaunchedBefore";

static BOOL const DEBUG_ALWAYS_SHOW_INTRO = NO;
static BOOL const DEBUG_ASK_ABOUT_STORAGE_OPTION = NO;

static BOOL const MIGRATE_SCREENSHOTS_TO_FOLDERS = YES;

@interface CLAppDelegate () <CLIntroViewControllerDelegate, iCloudNotAvailableViewControllerDelegate>

@property (strong, nonatomic) UISplitViewController *splitViewController;
@property (strong, nonatomic) UINavigationController *navigationController;
@property (strong, nonatomic) CLIntroViewController *introViewController;
@property (strong, nonatomic) iCloudNotAvailableViewController *iCloudNotAvailableViewController;

@property (assign, nonatomic) BOOL hasAttemptedToMigrateScreenshotsToFolders;

@end

@implementation CLAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [Analytics sharedInstance];

    [self setupSystemwideStyles];

    BOOL hasLaunchedBefore = [self hasLaunchedBefore];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onCatalogDidFinishSyncing:)
                                                 name:ScreenshotCatalogDidFinishSyncingNotification
                                               object:[ScreenshotCatalog sharedCatalog]];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onStorageDocumentsWereUpdated:)
                                                 name:[ScreenshotStorage sharedInstance].DOCUMENTS_WERE_UPDATED_NOTIFICATION
                                               object:[ScreenshotStorage sharedInstance]];

    PHAuthorizationStatus authorizationStatus = [PHPhotoLibrary authorizationStatus];
    if (hasLaunchedBefore && authorizationStatus == PHAuthorizationStatusAuthorized) {
        [[ScreenshotCatalog sharedCatalog] beginSyncingWithCameraRoll];
        [[ScreenshotCatalog sharedCatalog] beginListeningForPhotoLibraryChanges];
    }

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    // Override point for customization after application launch.
    self.window.backgroundColor = [UIColor darkGrayColor];
    CLScreenshotGroupsViewController *groupsViewController = [[CLScreenshotGroupsViewController alloc] init];

    self.splitViewController = [[UISplitViewController alloc] init];
    self.navigationController = [[UINavigationController alloc] initWithRootViewController:groupsViewController];

    groupsViewController.currentDetailViewController = [groupsViewController defaultDetailViewController];
    UINavigationController *detailNavController = [[UINavigationController alloc] initWithRootViewController:groupsViewController.currentDetailViewController];

    CLLog(@"Auto-displaying screenshots list");
    self.splitViewController.viewControllers = @[self.navigationController, detailNavController];
    self.splitViewController.presentsWithGesture = YES;

    if (DEBUG_ALWAYS_SHOW_INTRO || !hasLaunchedBefore) {
        self.introViewController = [[CLIntroViewController alloc] initWithNibName:nil bundle:nil];
        self.introViewController.delegate = self;
        UINavigationController *introNav = nil;
        if (self.window.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            introNav = [[UINavigationController alloc] initWithRootViewController:self.introViewController];
        } else {
            introNav = [[RotationLockedNavigationController alloc] initWithRootViewController:self.introViewController];
        }
        introNav.navigationBarHidden = YES;
        introNav.automaticallyAdjustsScrollViewInsets = NO;
        [self setRootViewController:introNav animated:NO withTransition:0 completion:nil];
    } else if (authorizationStatus == PHAuthorizationStatusDenied ||
               authorizationStatus == PHAuthorizationStatusRestricted) {
        [self showNotAuthorizedScreenAnimated:NO];
    } else {
        if (authorizationStatus == PHAuthorizationStatusNotDetermined) {
            // User must have reset their photos access
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (status != PHAuthorizationStatusAuthorized) {
                        [self showNotAuthorizedScreenAnimated:YES];
                    }
                });
            }];
        }

        // We can go ahead!
        [self setRootViewController:self.splitViewController animated:NO withTransition:0 completion:nil];
    }
    [self.window makeKeyAndVisible];
    if (self.window.rootViewController == self.splitViewController) {
        // In case we have to ask the user about iCloud, make sure we do this after the view is in the hierarchy
        [self startScreenshotStorageSessionWithCompletionHandler:nil];
    }

    CLLog(@"App opened, first time: %@", hasLaunchedBefore ? @"No" : @"Yes");

    return YES;
}

- (void)setRootViewController:(UIViewController *)viewController animated:(BOOL)animated withTransition:(UIViewAnimationOptions)transition completion:(void (^)())completion
{
    if (animated) {
        // We add the subview directly and use UIViewAnimationOptionShowHideTransitionViews so that
        // views like the not-authorized screen has time to do a layout and update its frame before
        // being shown
        [self.window addSubview:viewController.view];
        viewController.view.frame = self.window.rootViewController.view.frame;
        UIViewAnimationOptions options = transition | UIViewAnimationOptionShowHideTransitionViews;
        [UIView transitionFromView:self.window.rootViewController.view toView:viewController.view duration:0.5 options:options completion:^(BOOL finished) {
            [self.window.rootViewController.view removeFromSuperview];
            self.window.rootViewController = viewController;
            if (completion) {
                completion();
            }
        }];
    } else {
        self.window.rootViewController = viewController;
        if (completion) {
            completion();
        }
    }
}

- (BOOL)hasLaunchedBefore
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:HAS_LAUNCHED_BEFORE_KEY];
}

- (void)setHasLaunchedBefore:(BOOL)hasLaunchedBefore
{
    [[NSUserDefaults standardUserDefaults] setBool:hasLaunchedBefore forKey:HAS_LAUNCHED_BEFORE_KEY];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    [[ScreenshotCatalog sharedCatalog] saveContext];
}

#pragma mark - CLIntroViewControllerDelegate

- (void)introViewControllerDidRequestDismiss:(CLIntroViewController *)controller
{
    [self setHasLaunchedBefore:YES];
    PHAuthorizationStatus authorization = [PHPhotoLibrary authorizationStatus];
    if (authorization == PHAuthorizationStatusAuthorized) {
        CLLog(@"Photo permission granted, switching to main");
        [[ScreenshotCatalog sharedCatalog] beginSyncingWithCameraRoll];
        [[ScreenshotCatalog sharedCatalog] beginListeningForPhotoLibraryChanges];
        __weak CLAppDelegate *_weakSelf = self;
        // Start the storage session, which involves asking for storage option in UI if needed
        [self startScreenshotStorageSessionWithCompletionHandler:^{
            // Make sure when we animate in that our secondary view is displayed during the animation
            if (_weakSelf.splitViewController.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact) {
                _weakSelf.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModePrimaryHidden;
            }
            [_weakSelf setRootViewController:_weakSelf.splitViewController animated:YES withTransition:UIViewAnimationOptionTransitionFlipFromRight completion:^{
                _weakSelf.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeAutomatic;
                _weakSelf.introViewController = nil;
            }];
        }];

    } else if (authorization == PHAuthorizationStatusDenied) {
        // Show denied screen
        CLLog(@"Photo permission denied");
        [self showNotAuthorizedScreenAnimated:YES];
    } else if (authorization == PHAuthorizationStatusRestricted) {
        // Show restricted screen
        CLLog(@"Photo permission restricted");
        [self showNotAuthorizedScreenAnimated:YES];
    }
}


#pragma mark - When Authorization Denied or Restricted


- (void)showNotAuthorizedScreenAnimated:(BOOL)animated
{
    CLPhotoAccessNotAuthorizedViewController *accessDenied = [[CLPhotoAccessNotAuthorizedViewController alloc] initWithNibName:nil bundle:nil];
    [self setRootViewController:accessDenied animated:YES withTransition:UIViewAnimationOptionTransitionFlipFromLeft completion:nil];
}


#pragma mark - Styling


- (void) setupSystemwideStyles
{
    // This sets the color for all navigation bar backgrounds
    [UINavigationBar appearance].barTintColor = [UIColor colorWithRGBHex:0xFFFFFF]; // kind of matches the launch image gradient

    // Declare a transparent colored shadow object
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [UIColor clearColor];

    // Set the font/text style for titles in a navigation bar
    NSDictionary *attributes = @{
                                 NSFontAttributeName: [UIFont fontWithName:@"HelveticaNeue-Thin" size:22.0],
                                 NSForegroundColorAttributeName: [UIColor colorWithRGBHex:0x333333],
                                 NSShadowAttributeName: shadow,
                                 };
    [UINavigationBar appearance].titleTextAttributes = attributes;
    [UINavigationBar appearance].tintColor = [UIColor colorWithRGBHex:0x007aff];

    // Even though we're not a "black" style, this hints to the system that by default
    // we want our UIStatusBar to be light colored, when a nav bar is shown below it
    [UINavigationBar appearance].barStyle = UIBarStyleDefault;

    // Set the font/text style for bar button items (top-left, top-right)
    NSDictionary *buttonAttributes = @{
                                       NSFontAttributeName: [UIFont fontWithName:@"HelveticaNeue-Thin" size:18.0],
                                       NSForegroundColorAttributeName: [UIColor colorWithRGBHex:0x007aff],
                                       NSShadowAttributeName: shadow,
                                       };
    // (Apply the fancy bar button item styles only within a navigation bar)
    // This is so the icons/text, etc. in a (bottom) toolbar are not affected.
    [[UIBarButtonItem appearanceWhenContainedIn:[UINavigationBar class], nil] setTitleTextAttributes:buttonAttributes forState:UIControlStateNormal];
    [UIBarButtonItem appearanceWhenContainedIn:[UINavigationBar class], nil].tintColor = [UIColor colorWithRGBHex:0x007aff];
    // Background color of collection view
    [UICollectionView appearance].backgroundColor = [UIColor colorWithRGBHex:0xFAFAFA];
    [UITableView appearance].backgroundColor = [UIColor colorWithRGBHex:0xFAFAFA];
}


#pragma mark - iCloud


- (void)startScreenshotStorageSessionWithCompletionHandler:(void (^)())completionHandler
{
    [self askUserAboutUsingiCloudIfNeededWithCompletionHandler:^(BOOL iCloudEnabled, BOOL userMadeChoice) {
        ScreenshotStorage *storage = [ScreenshotStorage sharedInstance];
        if (ScreenshotStorage.iCloudUsagePermissionState == UsagePermissionStateShouldUse && !storage.iCloudAvailable) {
            // User had expressed interest in iCloud, but iCloud is not available.
            // This could also happen if the user was using iCloud, but then turned off "Documents & Data" at some point.
            self.iCloudNotAvailableViewController = [[iCloudNotAvailableViewController alloc] initWithNibName:@"iCloudNotAvailableViewController" bundle:nil];
            self.iCloudNotAvailableViewController.delegate = self;
            [self.window.rootViewController presentViewController:self.iCloudNotAvailableViewController
                                                         animated:NO
                                                       completion:nil];
        } else {
            // We've made a decision either way so go ahead and initialize
            [[ScreenshotStorage sharedInstance] updateToCurrentStorageOption];
        }
        if (completionHandler) {
            completionHandler();
        }
    }];
}


- (void)askUserAboutUsingiCloudIfNeededWithCompletionHandler:(void (^)(BOOL iCloudEnabled, BOOL userMadeChoice))completionHandler
{
    BOOL hasPhotosAccess = [PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusAuthorized;

    ScreenshotStorage *storage = [ScreenshotStorage sharedInstance];
    BOOL iCloudAvailable = [ScreenshotStorage sharedInstance].iCloudAvailable;
    [[Analytics sharedInstance] set:@{@"icloud_available" : @(iCloudAvailable)}];

    if (!iCloudAvailable) {
        // iCloud is not available, so we don't even have a chance
        CLLog(@"iCloud not available so not asking the user to choose between iCloud and local documents");
        [[Analytics sharedInstance] set:@{@"storage_choice" : @"Local"}];
        if (completionHandler) {
            completionHandler(NO, NO);
        }
        return;
    }

    // Only ask if we haven't determined it yet
    if (DEBUG_ASK_ABOUT_STORAGE_OPTION || ScreenshotStorage.iCloudUsagePermissionState == UsagePermissionStateNotDetermined) {
        if (storage.currentiCloudToken && hasPhotosAccess) {

            /*
            NSString *title = @"Choose Storage Option";
            NSString *message = @"Using iCloud means screenshots that you file will be backed up and magically synced between your iOS devices and Macs.";
            UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title
                                                                                     message:message
                                                                              preferredStyle:UIAlertControllerStyleAlert];
            [alertController addAction:[UIAlertAction actionWithTitle:@"Local Only" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                // Use Local Storage
                // (Okay)
                CLLog(@"User chose local storage (okay)");
                ScreenshotStorage.iCloudUsagePermissionState = UsagePermissionStateShouldNotUse;
                if (completionHandler) {
                    completionHandler(NO, YES);
                }
            }]];

            [alertController addAction:[UIAlertAction actionWithTitle:@"Use iCloud" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                // Use iCloud! (yey)
                // (fuckyeah)
                CLLog(@"User chose iCloud!");
                ScreenshotStorage.iCloudUsagePermissionState = UsagePermissionStateShouldUse;
                if (completionHandler) {
                    completionHandler(YES, YES);
                }
            }]];

            CLLog(@"Showing user choice for local or iCloud storage");
            [self.navigationController.topViewController presentViewController:alertController animated:YES completion:nil];
             */

            ChooseStorageOptionViewController *chooseStorage = [[ChooseStorageOptionViewController alloc] initWithNibName:@"ChooseStorageOptionViewController" bundle:nil];
            chooseStorage.choiceHandler = ^(BOOL choseiCloud){
                NSString *storageChoice = nil;
                if (choseiCloud) {
                    // Use iCloud! (yey)
                    // (fuckyeah)
                    CLLog(@"User chose iCloud!");
                    storageChoice = @"iCloud";
                    ScreenshotStorage.iCloudUsagePermissionState = UsagePermissionStateShouldUse;
                } else {
                    // Use Local Storage
                    // (Okay)
                    CLLog(@"User chose local storage (okay)");
                    storageChoice = @"Local";
                    ScreenshotStorage.iCloudUsagePermissionState = UsagePermissionStateShouldNotUse;
                }
                [[Analytics sharedInstance] set:@{@"storage_choice" : storageChoice}];
                [[Analytics sharedInstance] track:@"choose_storage_type"];
                if (self.introViewController) {
                    // Special case: Don't dismiss/pop, just call back
                    if (completionHandler) {
                        completionHandler(choseiCloud, YES);
                    }
                } else {
                    [self.splitViewController dismissViewControllerAnimated:YES completion:^{
                        if (completionHandler) {
                            completionHandler(choseiCloud, YES);
                        }
                    }];
                }
            };

            // Special case: if intro view, then push view on as part of onboarding instead of a modal
            if (self.introViewController) {
                [self.introViewController.navigationController pushViewController:chooseStorage animated:YES];
                [UIView animateWithDuration:0.35 animations:^{
                    self.introViewController.appIconView.alpha = 0.0;
                } completion:^(BOOL finished) {
                    self.introViewController.appIconView.hidden = YES;
                }];
            } else {
                [self.splitViewController presentViewController:chooseStorage animated:YES completion:nil];
            }
        }
    } else {
        BOOL iCloudEnabled = ScreenshotStorage.iCloudUsagePermissionState == UsagePermissionStateShouldUse;
        NSString *storageChoice = nil;
        if (iCloudEnabled) {
            storageChoice = @"iCloud";
        } else {
            storageChoice = @"Local";
        }
        [[Analytics sharedInstance] set:@{@"storage_choice" : storageChoice}];
        if (completionHandler) {
            completionHandler(iCloudEnabled, NO);
        }
    }
}

#pragma mark - iCloudNotAvailableViewControllerDelegate

- (void)iCloudNotAvailableViewControllerDidChangeStorageToUseLocalContainer:(iCloudNotAvailableViewController *)controller
{
    [self.iCloudNotAvailableViewController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
    self.iCloudNotAvailableViewController = nil;
}


#pragma mark - Screenshot Catalog did finish syncing


- (void) onCatalogDidFinishSyncing:(NSNotification *)notification
{
    [self maybeMigrateToFolderBasedScreenshots];
}


#pragma mark - Storage container was chosen/changed


- (void) onStorageDocumentsWereUpdated:(NSNotification *)notification
{
    // Documents being updated means a storage container was chosen
    [self maybeMigrateToFolderBasedScreenshots];
}


#pragma mark - Migration to folders


- (void) maybeMigrateToFolderBasedScreenshots
{
    ScreenshotCatalog *catalog = [ScreenshotCatalog sharedCatalog];
    UsagePermissionState containerPermission = [ScreenshotStorage iCloudUsagePermissionState];
    if (MIGRATE_SCREENSHOTS_TO_FOLDERS &&
        !self.hasAttemptedToMigrateScreenshotsToFolders && // Do this only once.
        !catalog.syncingDatabase && // Not in the middle of moving tags, etc. around
        containerPermission != UsagePermissionStateNotDetermined) { // User has chosen a container (local/iCloud)

        self.hasAttemptedToMigrateScreenshotsToFolders = YES;
        NSArray *nonTrashTags = [catalog retrieveAllTagsIncludeTrash:NO];
        if (nonTrashTags.count > 0) {
            CLLog(@"Beginning tag migration to folders...");
            NSDate *startTime = [NSDate date];
            [[ScreenshotCatalog sharedCatalog] migrateToFolderBasedScreenshotFilesWithCompletion:^(BOOL succeeded, NSError *error) {
                CLLog(@"Tag migration finished to folders. (%fs)", [[NSDate date] timeIntervalSinceDate:startTime]);
            }];
        }
    }
}
@end
