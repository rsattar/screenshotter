//
//  CLScreenshotListViewController.m
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

#import "CLScreenshotListViewController.h"

#import "CLAppDelegate.h"
#import "CLBannerView.h"
#import "CLQuickLookViewController.h"
#import "CLScreenshotCell.h"
#import "CLScreenshotsLoader.h"
#import "CLScreenshotterApplication.h"
#import "CLTaggingViewController.h"
#import "GenericSlideshowViewController.h"
#import <Photos/Photos.h>
#import <QuartzCore/QuartzCore.h>
#import "ScreenshotCatalog.h"
#import "TagType.h"
#import "UIColor+Hex.h"

static BOOL const MARK_SCREENSHOTS_AS_ARCHIVE_INSTEAD_OF_DELETE = NO;

static BOOL const SORT_ASCENDING = NO;

static BOOL const HIDE_SHOW_TOOLBAR_WITH_SELECTION = NO;

static NSString *const HAS_SHOWN_ARCHIVE_HINT_BEFORE_KEY = @"hasShownArchiveHintBefore";

static NSTimeInterval const BANNER_ANIMATE_DURATION = 0.35;
static NSTimeInterval const BANNER_DISPLAY_DURATION = 1.5;

@interface CLScreenshotListViewController () <
    CLQuickLookViewControllerDelegate,
    CLTaggingViewControllerDelegate,
    GenericSlideshowViewControllerDelegate,
    UIActionSheetDelegate,
    UIAlertViewDelegate,
    UICollectionViewDataSource,
    UICollectionViewDelegate,
    UIGestureRecognizerDelegate,
    UICollectionViewDelegateFlowLayout,
    UIViewControllerTransitioningDelegate>

@property (strong, nonatomic) UICollectionView *collectionView;

@property (strong, nonatomic) UIBarButtonItem *selectBarButtonItem;
@property (strong, nonatomic) NSString *collectionTitle;
@property (strong, nonatomic) UIView *collectionTitleViewDuringUpdate;
@property (strong, nonatomic) UIBarButtonItem *cancelSelectionBarButtonItem;
@property (strong, nonatomic) UIBarButtonItem *shareSelectionBarButtonItem;

// Asset-based screenshots
@property (strong, nonatomic) NSMutableArray *screenshots;
@property (strong, nonatomic) NSMutableDictionary *screenshotAssetsById;
@property (assign, nonatomic) BOOL loadingScreenshots;
@property (assign, nonatomic) NSUInteger lastAssetOffset;
@property (assign, nonatomic) BOOL shouldReloadFromSource;
@property (assign, nonatomic) BOOL ignoreCatalogChanges;

// File-based screenshots
@property (strong, nonatomic) ScreenshotFolder *folder;
@property (strong, nonatomic) NSMutableArray *screenshotFiles;

@property (assign, nonatomic) BOOL shouldScrollToBottom;
@property (assign, nonatomic) BOOL userHasDraggedCollectionView;

@property (assign, nonatomic) BOOL updatingCollectionViewContentSize;

@property (assign, nonatomic) CGFloat maxCellWidth;
@property (assign, nonatomic) CGFloat loadMoreThreshold;
@property (assign, nonatomic) BOOL allScreenshotsLoaded;

@property (assign, nonatomic) CGFloat customBatchSize;

@property (strong, nonatomic) UIBarButtonItem *toolbarTagItem;
@property (strong, nonatomic) UIBarButtonItem *toolbarUntagItem;
@property (strong, nonatomic) UIButton *iconAndLabelButtonForTagOrUntag;
@property (strong, nonatomic) UIBarButtonItem *toolbarTrashItem;
@property (strong, nonatomic) UIBarButtonItem *toolbarUntrashItem;
@property (strong, nonatomic) UIBarButtonItem *toolbarTrashAllItem;
@property (strong, nonatomic) UIButton *iconAndLabelButtonForTrashAll;
@property (strong, nonatomic) NSMutableArray *barItemsDuringSelection;
@property (strong, nonatomic) NSMutableArray *barItemsDuringScroll;

@property (strong, nonatomic) UIActionSheet *screenshotUntaggingActionSheet;
@property (strong, nonatomic) UIAlertView *firstTimeScreenshotTrashingAlertView;

@property (strong, nonatomic) UITapGestureRecognizer *tapGestureRecognizer;
@property (strong, nonatomic) UILongPressGestureRecognizer *longPressGestureRecognizer;

@property (strong, nonatomic) CLQuickLookTransitionManager *transitionManager;

@property (strong, nonatomic) CLBannerView *bannerView;

@property (strong, nonatomic) GenericSlideshowViewController *slideshowViewController;

@property (assign, nonatomic) BOOL beingShown;

// Empty UI
@property (strong, nonatomic) UIView *emptyUIView;
@property (strong, nonatomic) UILabel *emptyUITitle;
@property (strong, nonatomic) UILabel *emptyUIMessage;
@property (strong, nonatomic) UIActivityIndicatorView *emptyUISyncingIndicator;
@property (strong, nonatomic) UIButton *emptyUIDeleteTagButton;

// Empty UI constraints
@property (strong, nonatomic) NSLayoutConstraint *emptyUIWidthConstraint;
@property (strong, nonatomic) NSArray *emptyUIVerticallyStackingContraints;
@property (strong, nonatomic) NSString *lastUsedStackingVisualFormat;

@end

@implementation CLScreenshotListViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
        _shouldReloadFromSource = YES;
        _maxCellWidth = 136;
        _screenshots = [NSMutableArray arrayWithCapacity:400];
        _screenshotAssetsById = [NSMutableDictionary dictionaryWithCapacity:400];
        // A very rough initial attempt at paging
        _loadMoreThreshold = 1.0 * CGRectGetHeight([UIScreen mainScreen].applicationFrame);

        // Listen to this forever and ever
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onCatalogUpdated:)
                                                     name:NSManagedObjectContextDidSaveNotification
                                                   object:[ScreenshotCatalog sharedCatalog].managedObjectContext];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onScreeenshotCatalogDidBeginSyncing:)
                                                     name:ScreenshotCatalogDidBeginSyncingNotification
                                                   object:[ScreenshotCatalog sharedCatalog]];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onScreenshotCatalogDidFinishSyncing:)
                                                     name:ScreenshotCatalogDidFinishSyncingNotification
                                                   object:[ScreenshotCatalog sharedCatalog]];
    }
    return self;
}


- (void)dealloc
{
    self.collectionView.delegate = nil;
    self.collectionView.dataSource = nil;
    [self removeCoreDataListener];
}


- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    self.view.backgroundColor = [UIColor whiteColor];
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.sectionInset = UIEdgeInsetsMake(16.0, 16.0, 16.0, 16.0);
    layout.minimumLineSpacing = 16.0;
    layout.minimumInteritemSpacing = 16.0;
    self.collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds
                                             collectionViewLayout:layout];
    self.collectionView.allowsMultipleSelection = YES;
    self.collectionView.allowsSelection = NO;
    self.collectionView.alwaysBounceVertical = YES;
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    // For some reason this collection view doesn't pick up the appearance automatically, so manually set it
    self.collectionView.backgroundColor = [UICollectionView appearance].backgroundColor;
    [self.collectionView registerClass:[CLScreenshotCell class] forCellWithReuseIdentifier:@"ScreenshotCell"];
    [self.view addSubview:self.collectionView];
    self.collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    if (self.folderName) {
        self.folder = [ScreenshotStorage sharedInstance].screenshotFoldersByFolderName[self.folderName];
        self.screenshotFiles = [self.folder.files mutableCopy];
    }

    self.collectionTitle = NSLocalizedStringWithDefaultValue(@"screenshotList.title.allScreenshots",
                                                             nil,
                                                             [NSBundle mainBundle],
                                                             @"All Screenshots",
                                                             @"Navigation title, for 'All Screenshots'");
    if (self.folder) {
        self.collectionTitle = self.folder.folderName;
    } else if (self.tagToFilter) {
        if (self.tagToFilter == [ScreenshotCatalog sharedCatalog].trashTag) {
            self.collectionTitle = NSLocalizedStringWithDefaultValue(@"screenshotList.title.trashFolder",
                                                                     nil,
                                                                     [NSBundle mainBundle],
                                                                     @"In Folders",
                                                                     @"Navigation title, explaining that these screenshots are already 'in folders'");
        } else {
            self.collectionTitle = self.tagToFilter.name;
        }
    } else if (!self.showAllScreenshots) {
        self.collectionTitle = NSLocalizedStringWithDefaultValue(@"screenshotList.title.screenshots",
                                                                 nil,
                                                                 [NSBundle mainBundle],
                                                                 @"Screenshots",
                                                                 @"Navigation title, for 'Screenshots'");
    }
    [self updateNavigationTitle];
    NSString *selectTitle = NSLocalizedStringWithDefaultValue(@"screenshotList.selectButton",
                                                              nil,
                                                              [NSBundle mainBundle],
                                                              @"Select",
                                                              @"Bar button title for 'Select'ing screenshots");
    self.selectBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:selectTitle style:UIBarButtonItemStylePlain target:self action:@selector(onSelectBarButtonItemTapped:)];
    NSString *cancelTitle = NSLocalizedStringWithDefaultValue(@"screenshotList.cancelSelectButton",
                                                              nil,
                                                              [NSBundle mainBundle],
                                                              @"Cancel",
                                                              @"Bar button title for cancelling selecting screenshots");
    self.cancelSelectionBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:cancelTitle style:UIBarButtonItemStyleDone target:self action:@selector(onCancelSelectionBarButtonItemTapped:)];
    self.shareSelectionBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(onShareSelectionBarButtonItemTapped:)];

    self.navigationItem.leftBarButtonItem = self.splitViewController.displayModeButtonItem;
    self.navigationItem.leftItemsSupplementBackButton = YES;
    self.navigationItem.rightBarButtonItem = self.selectBarButtonItem;

    self.tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap:)];
    self.tapGestureRecognizer.delegate = self;
    [self.collectionView addGestureRecognizer:self.tapGestureRecognizer];

    self.longPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                    action:@selector(handleLongPress:)];
    self.longPressGestureRecognizer.delegate = self;
    [self.collectionView addGestureRecognizer:self.longPressGestureRecognizer];

    // Toolbar
    self.barItemsDuringSelection = [NSMutableArray arrayWithCapacity:5];
    // Delete icon
    if (self.tagToFilter != nil) {
        // Only screenshots tagged with self.tagToFilter
        if (self.tagToFilter.type.intValue == TagTypeTrash) {
            // Is in trash
            // Bottom left should be "Unarchive"
            NSString *unarchiveButton = NSLocalizedStringWithDefaultValue(@"screenshotList.toolbar.unarchive",
                                                                          nil,
                                                                          [NSBundle mainBundle],
                                                                          @"Unarchive",
                                                                          @"Toolbar button title to unarchive");
            self.iconAndLabelButtonForTagOrUntag = [self createButtonForBarWithTitle:unarchiveButton andIconNamed:@"icon_folder"];
            [self.iconAndLabelButtonForTagOrUntag addTarget:self action:@selector(onToolbarUntrashItemTapped:) forControlEvents:UIControlEventTouchUpInside];
            self.toolbarUntrashItem = [[UIBarButtonItem alloc] initWithCustomView:self.iconAndLabelButtonForTagOrUntag];
            [self.barItemsDuringSelection addObject:self.toolbarUntrashItem];
        } else {
            NSString *removeFromFolder = NSLocalizedStringWithDefaultValue(@"screenshotList.toolbar.removeFromFolder",
                                                                           nil,
                                                                           [NSBundle mainBundle],
                                                                           @"Remove from Folder",
                                                                           @"Toolbar button title to 'Remove from folder'");
            self.iconAndLabelButtonForTagOrUntag = [self createButtonForBarWithTitle:removeFromFolder andIconNamed:@"icon_folder"];
            [self.iconAndLabelButtonForTagOrUntag addTarget:self action:@selector(onToolbarUntagItemTapped:) forControlEvents:UIControlEventTouchUpInside];
            self.toolbarUntagItem = [[UIBarButtonItem alloc] initWithCustomView:self.iconAndLabelButtonForTagOrUntag];
            [self.barItemsDuringSelection addObject:self.toolbarUntagItem];
        }
    } else {
        // All screenshots, tagged or not, or in ScreenshotFolder
        NSString *moveToFolder = NSLocalizedStringWithDefaultValue(@"screenshotList.toolbar.moveToFolder",
                                                                   nil,
                                                                   [NSBundle mainBundle],
                                                                   @"Move to Folder",
                                                                   @"Toolbar button title to 'Move to folder'");
        self.iconAndLabelButtonForTagOrUntag = [self createButtonForBarWithTitle:moveToFolder andIconNamed:@"icon_folder"];
        [self.iconAndLabelButtonForTagOrUntag addTarget:self action:@selector(onToolbarTagItemTapped:) forControlEvents:UIControlEventTouchUpInside];
        self.toolbarTagItem = [[UIBarButtonItem alloc] initWithCustomView:self.iconAndLabelButtonForTagOrUntag];
        [self.barItemsDuringSelection addObject:self.toolbarTagItem];
    }
    // Add another spacer
    [self.barItemsDuringSelection addObject:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                                          target:nil
                                                                                          action:nil]];
    // Trashable
    if (MARK_SCREENSHOTS_AS_ARCHIVE_INSTEAD_OF_DELETE) {
        self.toolbarTrashItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"icon_archive"]
                                                   landscapeImagePhone:nil
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(onToolbarTrashItemTapped:)];
    } else {
        self.toolbarTrashItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"icon_trash"]
                                                   landscapeImagePhone:nil
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(onToolbarTrashItemTapped:)];
    }
    [self.barItemsDuringSelection addObject:self.toolbarTrashItem];

    self.barItemsDuringScroll = self.barItemsDuringSelection; // Default, they are the same
    if (self.tagToFilter != nil && self.tagToFilter.type.intValue == TagTypeTrash) {
        self.barItemsDuringScroll = [NSMutableArray arrayWithCapacity:3];
        NSString *deleteAll = NSLocalizedStringWithDefaultValue(@"screenshotList.toolbar.deleteAll",
                                                                nil,
                                                                [NSBundle mainBundle],
                                                                @"Delete All",
                                                                @"Toolbar button title to 'Delete All'");
        self.iconAndLabelButtonForTrashAll = [self createButtonForBarWithTitle:deleteAll andIconNamed:@"icon_trash"];
        [self.iconAndLabelButtonForTrashAll setTitleColor:[UIColor colorWithRGBHex:0xCC0000] forState:UIControlStateNormal];
        self.iconAndLabelButtonForTrashAll.tintColor = [UIColor colorWithRGBHex:0xCC0000];
        [self.iconAndLabelButtonForTrashAll addTarget:self action:@selector(onToolbarTrashAllItemTapped:) forControlEvents:UIControlEventTouchUpInside];
        self.toolbarTrashAllItem = [[UIBarButtonItem alloc] initWithCustomView:self.iconAndLabelButtonForTrashAll];

        [self.barItemsDuringScroll addObject:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil]];
        [self.barItemsDuringScroll addObject:self.toolbarTrashAllItem];
        [self.barItemsDuringScroll addObject:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil]];
    }

    self.toolbarItems = self.barItemsDuringScroll;
    [self updateToolbarItemsAnimated:NO];
    [self updateEmptyUI];
}

- (UIButton *)createButtonForBarWithTitle:(NSString *)title andIconNamed:(NSString *)iconName
{
    TintColorButton *button = [[TintColorButton alloc] initWithFrame:CGRectZero];
    UIImage *tintedImage = [[UIImage imageNamed:iconName] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [button setTitleEdgeInsets:UIEdgeInsetsMake(0, 10.0, 0, -10)];
    [button setImage:tintedImage forState:UIControlStateNormal];
    [button setTitleColor:self.navigationController.toolbar.tintColor forState:UIControlStateNormal];
    UIColor *disabledColor = [UIColor lightGrayColor];
    [button setTitleColor:disabledColor forState:UIControlStateDisabled];
    [button setTitle:title forState:UIControlStateNormal];
    [button sizeToFit];

    return button;
}


- (void)updateMaxWidthForScreenshots
{
    CGFloat numScreenshotsPerRow = 2;
    CGFloat xPadding = 16.0;
    CGFloat idealWidth = 136.0;

    CGFloat availableWidth = CGRectGetWidth(self.collectionView.bounds);
    CGFloat leftoverWidth = availableWidth - (idealWidth * numScreenshotsPerRow) - (xPadding * 2.0) - (xPadding * (numScreenshotsPerRow-1));
    while (leftoverWidth >= (idealWidth/2.0)) {
        numScreenshotsPerRow++;
        leftoverWidth = availableWidth - (idealWidth * numScreenshotsPerRow) - (xPadding * 2.0) - (xPadding * (numScreenshotsPerRow-1));
    }

    CGFloat calculatedWidth = availableWidth - (xPadding * 2.0) - (xPadding * (numScreenshotsPerRow-1));
    calculatedWidth = floor(calculatedWidth/numScreenshotsPerRow);

    CGFloat oldWidth = _maxCellWidth;
    _maxCellWidth = MAX(10, calculatedWidth);
    if (_maxCellWidth != oldWidth) {
        // This is especially needed when presenting this UI initially
        // within a collapsed split view
        // (especially animating from intro root VC to split root VC)
        [self.collectionView.collectionViewLayout invalidateLayout];
    }

}


- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    if (!HIDE_SHOW_TOOLBAR_WITH_SELECTION) {
        self.navigationController.toolbarHidden = NO;
    }
    [self updateEmptyUI];
    if (self.shouldReloadFromSource) {
        // When re-appearing load as many screenshots as we had before (if not in a folder)
        // (reload as much as we need to update our UI)
        self.customBatchSize = self.screenshots.count;
        [self loadScreenshotsLoadMore:NO];
        self.customBatchSize = 0;
        self.shouldReloadFromSource = NO;
    }

    [[Analytics sharedInstance] registerScreen:@"Shots"];

    self.beingShown = YES;
}


- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    [self updateMaxWidthForScreenshots];
    if (self.shouldScrollToBottom) {
        [self scrollToBottomOfCollectionView:self.collectionView animated:NO];
    }
}


- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [self.collectionView.collectionViewLayout invalidateLayout];
}


- (void)viewWillDisappear:(BOOL)animated
{
    self.beingShown = NO;
}


- (void)removeCoreDataListener
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSManagedObjectContextDidSaveNotification
                                                  object:[ScreenshotCatalog sharedCatalog].managedObjectContext];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (void)reloadDataReselectItems:(NSArray *)itemsToSelect maintainOffset:(BOOL)maintainOffset
{
    if (self.updatingCollectionViewContentSize) {
        return;
    }
    // reloading the collection view loses the index paths


    // We have older screenshots, so reset to adjusted content offset so it doesn't jump around
    CGFloat oldContentOffset = self.collectionView.contentOffset.y;
    CGFloat previousHeight = self.maxScrollY;
    [self.collectionView reloadData];

    if (maintainOffset) {
        self.updatingCollectionViewContentSize = YES;
        [self.collectionView performBatchUpdates:nil completion:^(BOOL finished) {
            self.updatingCollectionViewContentSize = NO;
        }];
    }
    CGFloat newHeight = self.maxScrollY;

    if (maintainOffset) {
        // Try and keep our place
        CGFloat heightDiff = newHeight - previousHeight;
        /*
         NSLog(@"Prev Height: %f, New height: %f. Diff: %f, new offset: %f",
         previousHeight,
         newHeight,
         heightDiff,
         (oldContentOffset + heightDiff));
         */
        self.collectionView.contentOffset = CGPointMake(0, oldContentOffset + heightDiff);
    }
    if (itemsToSelect.count) {
        NSMutableArray *selectedIndexPaths = [NSMutableArray arrayWithCapacity:itemsToSelect.count];
        if (itemsToSelect) {
            NSArray *sourceList = self.screenshots;
            if (self.folder) {
                sourceList = self.screenshotFiles;
            }
            for (id item in itemsToSelect) {
                NSInteger index = [sourceList indexOfObject:item];
                if (index != NSNotFound) {
                    [selectedIndexPaths addObject:[NSIndexPath indexPathForItem:index inSection:0]];
                }
            }
        }
        for (NSIndexPath *selectedIndexPath in selectedIndexPaths) {
            [self.collectionView selectItemAtIndexPath:selectedIndexPath
                                              animated:NO
                                        scrollPosition:UICollectionViewScrollPositionNone];
        }
    }
    [self updateEmptyUI];
    [self updateToolbarItemsAnimated:NO];
}


- (void)onCatalogUpdated:(NSNotification *)notification
{
    if (self.folder != nil) {
        return; // we don't care about the syncing in the local db
    }
    if (self.beingShown && !self.ignoreCatalogChanges) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.customBatchSize = self.screenshots.count;
            CLLog(@"Received catalog update, re-retrieving up to %lu screenshots", (unsigned long)self.customBatchSize);
            [self loadScreenshotsLoadMore:NO];
            self.customBatchSize = 0;
        });
    } else {
        CLLog(@"Received catalog update, will reload from source later (ignoreCatalogChanges = %d", self.ignoreCatalogChanges);
        self.shouldReloadFromSource = YES;
    }
}


- (void)onScreeenshotCatalogDidBeginSyncing:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateNavigationTitle];
    });
}


- (void)onScreenshotCatalogDidFinishSyncing:(NSNotification *)notification
{
    if (self.folder != nil) {
        return; // we don't care about the syncing in the local db
    }
    if (self.ignoreCatalogChanges) {
        self.shouldReloadFromSource = YES;
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        NSUInteger numScreenshots = [[ScreenshotCatalog sharedCatalog] countOfAllScreenshots];
        if (self.screenshots.count == 0 && numScreenshots > 0) {
            [self loadScreenshotsLoadMore:NO];
        }
        if ((!self.emptyUIView.hidden && numScreenshots == 0) ||
            (self.screenshots.count == 0)) {
            [self updateEmptyUI];
        }
        [self updateNavigationTitle];
    });
}


#pragma mark - Single Taps (only when selection is disabled


- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    if (self.collectionView.allowsSelection) {
        return NO;
    }
    return YES;
}


- (void)handleSingleTap:(UITapGestureRecognizer *)gestureRecognizer
{
    CGPoint touchPoint = [gestureRecognizer locationInView:self.collectionView];
    NSIndexPath *touchedIndexPath = [self.collectionView indexPathForItemAtPoint:touchPoint];
    if (touchedIndexPath == nil) {
        return;
    }
    if (self.folder) {
        CLLog(@"Tapped screenshot file at indexPath: %@", touchedIndexPath);
    } else {
        CLLog(@"Tapped screenshot at indexPath: %@", touchedIndexPath);
    }

    [self startSlideshowStartingFromIndexPath:touchedIndexPath animated:YES];
}


- (void)handleLongPress:(UILongPressGestureRecognizer *)gestureRecognizer
{
    CGPoint touchPoint = [gestureRecognizer locationInView:self.collectionView];
    NSIndexPath *touchedIndexPath = [self.collectionView indexPathForItemAtPoint:touchPoint];
    [self beginSelectingItemsAnimated:NO];
    [self.collectionView selectItemAtIndexPath:touchedIndexPath animated:YES scrollPosition:UICollectionViewScrollPositionNone];
    [self collectionView:self.collectionView didSelectItemAtIndexPath:touchedIndexPath];
}


#pragma mark - GenericSlideshowViewControllerDelegate and Slideshow


- (void)startSlideshowStartingFromIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated
{

    self.slideshowViewController = [[GenericSlideshowViewController alloc] initWithFrame:self.view.frame];
    self.slideshowViewController.delegate = self;
    self.slideshowViewController.itemIndex = indexPath.item;
    self.slideshowViewController.controlsVisible = NO;
    self.slideshowViewController.singleTapAction = GenericSlideshowSingleTapActionDismiss;

    /*
    // Add our own 'Done' button to dismiss for now
    UIBarButtonItem *slideshowDoneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(onSlideshowDoneBarButtonTapped:)];
    NSMutableDictionary *boldTextAttributes = [[slideshowDoneButton titleTextAttributesForState:UIControlStateNormal] mutableCopy];
    boldTextAttributes[NSFontAttributeName] = [UIFont fontWithName:@"HelveticaNeue-Light" size:22.0];
    [slideshowDoneButton setTitleTextAttributes:boldTextAttributes forState:UIControlStateNormal];
    self.slideshowViewController.navigationItem.leftBarButtonItem = slideshowDoneButton;
     */
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:self.slideshowViewController];
    if (animated) {

        self.transitionManager = [[CLQuickLookTransitionManager alloc] init];
        self.transitionManager.quickLookSourceDelegate = self;
        if (self.folder) {
            ScreenshotFileInfo *screenshotFile = self.screenshotFiles[indexPath.item];
            self.transitionManager.screenshotFile = screenshotFile;
        } else {
            Screenshot *screenshot = self.screenshots[indexPath.item];
            PHAsset *asset = self.screenshotAssetsById[screenshot.localAssetURL];
            self.transitionManager.screenshot = screenshot;
            self.transitionManager.phAsset = asset;
        }
        CLScreenshotCell *screenshotCell = (CLScreenshotCell *)[self.collectionView cellForItemAtIndexPath:indexPath];
        self.transitionManager.screenshotView = screenshotCell.screenshotView;
    }
    nav.transitioningDelegate = self;
    [self presentViewController:nav animated:animated completion:^{
        self.transitionManager = nil;
    }];
    /*
    CLQuickLookViewController *quickLook = [[CLQuickLookViewController alloc] initWithNibName:nil bundle:nil];
    quickLook.delegate = self;
    if (self.folder) {
        ScreenshotFileInfo *screenshotFile = self.screenshotFiles[indexPath.item];
        CLLog(@"Tapped screenshot file at indexPath: %@", indexPath);
        [quickLook setScreenshotFile:screenshotFile loadImmediately:YES];
    } else {
        Screenshot *screenshot = self.screenshots[indexPath.item];
        PHAsset *asset = self.screenshotAssetsById[screenshot.localAssetURL];
        CLLog(@"Tapped screenshot at indexPath: %@ (asset: %@)", indexPath, asset);
        [quickLook setScreenshot:screenshot andAsset:asset];
    }
    quickLook.transitioningDelegate = self;

    quickLook.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:quickLook animated:YES completion:nil];
     */
}


- (void)dismissSlideshowAnimated:(BOOL)animated
{
    UIViewController *currentSlideshowItemViewController = [self.slideshowViewController currentItemViewController];
    if ([currentSlideshowItemViewController isKindOfClass:[CLQuickLookViewController class]]) {

        CLQuickLookViewController *currentQuickLookController = (CLQuickLookViewController *)currentSlideshowItemViewController;
        self.transitionManager = [[CLQuickLookTransitionManager alloc] init];
        self.transitionManager.quickLookSourceDelegate = self;
        self.transitionManager.screenshot = currentQuickLookController.screenshot;
        self.transitionManager.phAsset = currentQuickLookController.phAsset;
        self.transitionManager.screenshotFile = currentQuickLookController.screenshotFile;
        self.transitionManager.screenshotView = currentQuickLookController.screenshotView;

        // Also, scroll down so that the thumbnail for the current screenshot is visible (nicer animation :) )
        NSInteger itemIndex = self.slideshowViewController.itemIndex;
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:itemIndex inSection:0];
        // is indexPath already visible? if not, scroll to it
        if (![self.collectionView.indexPathsForVisibleItems containsObject:indexPath]) {
            [self.collectionView scrollToItemAtIndexPath:indexPath
                                        atScrollPosition:UICollectionViewScrollPositionCenteredVertically
                                                animated:NO];
        }
    }
    [self dismissViewControllerAnimated:animated completion:^{
        self.transitionManager = nil;
        self.slideshowViewController.transitioningDelegate = nil;
        self.slideshowViewController = nil;
    }];
}


- (NSUInteger) numberOfItemsInSlideshow:(GenericSlideshowViewController *)controller
{
    if (self.folder) {
        return self.screenshotFiles.count;
    } else {
        //return self.screenshots.count;
        if (self.tagToFilter) {
            return self.tagToFilter.screenshots.count;
        } else if (self.showAllScreenshots) {
            return [ScreenshotCatalog sharedCatalog].countOfAllScreenshots;
        } else {
            return [ScreenshotCatalog sharedCatalog].countOfAllUnfiledScreenshots;
        }
    }
}


- (UIViewController *) viewControllerForItemAtIndex:(NSInteger)index
{
    CLQuickLookViewController *quickLook = [[CLQuickLookViewController alloc] initWithNibName:nil bundle:nil];
    quickLook.delegate = self;
    quickLook.dismissOnSingleTap = NO;
    if (self.folder) {
        ScreenshotFileInfo *screenshotFile = self.screenshotFiles[index];
        [quickLook setScreenshotFile:screenshotFile loadImmediately:YES];
    } else {
        Screenshot *screenshot = self.screenshots[index];
        PHAsset *asset = self.screenshotAssetsById[screenshot.localAssetURL];
        [quickLook setScreenshot:screenshot andAsset:asset];
    }
    return quickLook;
    //quickLook.transitioningDelegate = self;

    //quickLook.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    //[self presentViewController:quickLook animated:YES completion:nil];
}


- (void) slideshowDidRequestDismiss:(GenericSlideshowViewController *)controller animated:(BOOL)animated
{
    [self dismissSlideshowAnimated:animated];
}


- (void) genericSlideShowViewController:(GenericSlideshowViewController *)controller
                  didDisplayItemAtIndex:(NSUInteger)index
{
    CLLog(@"Displayed slide show item at index: %lu", (unsigned long)index);
    if (self.folder) {
        return;
    }

    // We might be able to page some more, so check where we are
    if (self.screenshots.count - index == 2) {
        [self loadScreenshotsLoadMore:YES];
    }
}


- (void) onSlideshowDoneBarButtonTapped:(id)sender
{
    CLLog(@"Tapped slideshow Done");
    [self dismissSlideshowAnimated:YES];
}

#pragma mark - UICollectionViewDataSource


- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return 1;
}


- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    if (self.folder) {
        return self.screenshotFiles.count;
    } else {
        return self.screenshots.count;
    }
}


- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    CLScreenshotCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ScreenshotCell" forIndexPath:indexPath];
    if (self.folder) {
        ScreenshotFileInfo *screenshotFile = self.screenshotFiles[indexPath.item];
        [cell setScreenshotFile:screenshotFile loadImmediately:NO];
    } else {
        Screenshot *screenshot = self.screenshots[indexPath.item];
        PHAsset *asset = self.screenshotAssetsById[screenshot.localAssetURL];
        if (asset == nil) {
            CLLog(@"Couldn't find screenshot asset matching localAssetUrl: %@", screenshot.localAssetURL);
        }
        [cell setScreenshot:screenshot andAsset:asset];
    }
    return cell;
}


#pragma mark - UICollectionViewDelegate


- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    CLLog(@"Selected item at index: %ld (%lu/%lu selected)",
            (long)indexPath.item,
            (unsigned long)collectionView.indexPathsForSelectedItems.count,
            (unsigned long)[collectionView numberOfItemsInSection:indexPath.section]);
    [self updateNavigationTitle];
    [self updateToolbarItemsAnimated:YES];
}


- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath
{
    CLLog(@"Unselected item at index: %ld (%lu/%lu selected)",
            (long)indexPath.item,
            (unsigned long)collectionView.indexPathsForSelectedItems.count,
            (unsigned long)[collectionView numberOfItemsInSection:indexPath.section]);
    [self updateNavigationTitle];
    [self updateToolbarItemsAnimated:YES];
}


- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}


- (BOOL)collectionView:(UICollectionView *)collectionView shouldDeselectItemAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}


#pragma mark - UICollectionViewDelegateFlowLayout


- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    CGSize imageDimensions = [UIScreen mainScreen].bounds.size;
    if (self.folder) {
        ScreenshotFileInfo *screenshotFile = self.screenshotFiles[indexPath.item];
        CGSize dimensions = [ScreenshotFileInfo imageDimensionsFromFileAtUrl:screenshotFile.fileUrl];
        if (!CGSizeEqualToSize(dimensions, CGSizeZero)) {
            imageDimensions = dimensions;
        }
    } else {
        Screenshot *screenshot = self.screenshots[indexPath.item];
        imageDimensions = CGSizeMake(screenshot.width.doubleValue, screenshot.height.doubleValue);
    }
    // Lower down to max width
    CGFloat aspectRatio = imageDimensions.height / imageDimensions.width;
    imageDimensions.width = _maxCellWidth;
    imageDimensions.height = imageDimensions.width * aspectRatio;

    return imageDimensions;
}


#pragma mark - UIScrollViewDelegate


- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    self.shouldScrollToBottom = NO;
    self.userHasDraggedCollectionView = YES;
}


- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    if (self.beingShown) {
        [self maybeLoadMore];
    }
}


- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if (self.beingShown) {
        [self maybeLoadMore];
    }
}


- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    if (self.beingShown) {
        [self maybeLoadMore];
    }
}


- (void)maybeLoadMore
{
    if (self.loadingScreenshots ||
        self.screenshots.count == 0 ||
        self.allScreenshotsLoaded ||
        !self.userHasDraggedCollectionView) {
        return;
    }

    UICollectionView *view = self.collectionView;;
    if (SORT_ASCENDING) {
        if (view.contentOffset.y <= CGRectGetHeight(view.bounds)) {
            [self loadScreenshotsLoadMore:YES];
        }
    } else {
        CGFloat height = view.contentSize.height;
        CGFloat top = view.contentOffset.y + CGRectGetHeight(view.bounds);
        if (height - top < self.loadMoreThreshold) {
            [self loadScreenshotsLoadMore:YES];
        }
    }
}


#pragma mark - Scollview calculations


- (CGFloat)scrollY
{
    return self.collectionView.contentOffset.y;
}


- (CGFloat)maxScrollY
{
    CGFloat contentHeight = self.collectionView.contentSize.height;
    CGFloat maxY = contentHeight-self.collectionView.contentInset.top-self.collectionView.contentInset.bottom-self.collectionView.bounds.size.height;
    return maxY;
}


- (CGFloat)scrollYPercent
{
    return ([self scrollY] / [self maxScrollY]);
}


#pragma mark - Actions


- (void)onSelectBarButtonItemTapped:(id)sender
{
    CLLog(@"Tapped Select");
    [self beginSelectingItemsAnimated:YES];
}


- (void)onCancelSelectionBarButtonItemTapped:(id)sender
{
    CLLog(@"Tapped 'Cancel' during selection");
    [self finishSelectingItems];
}


- (void)onShareSelectionBarButtonItemTapped:(id)sender
{
    // When we finally extract the assets, we'll call this block
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    [spinner startAnimating];
    UIBarButtonItem *spinnerBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];
    [self.navigationItem setRightBarButtonItem:spinnerBarButtonItem animated:NO];
    void (^showActivityViewControllerWithItems)(NSArray *) = ^(NSArray *assets) {
        [self.navigationItem setRightBarButtonItem:self.shareSelectionBarButtonItem animated:YES];
        UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:assets
                                                                                             applicationActivities:nil];
        activityViewController.completionWithItemsHandler = ^(NSString *activityType, BOOL completed, NSArray *returnedItems, NSError *activityError) {
            if (completed) {
                CLLog(@"Shared Screenshots with activity: %@", activityType);
                [[Analytics sharedInstance] track:@"share_shots"
                                       properties:@{@"activity_type" : activityType,
                                                    @"num_shots" : @(assets.count)}];
                [self finishSelectingItems];
            } else {
                CLLog(@"Cancelled sharing");
            }
        };
        activityViewController.popoverPresentationController.barButtonItem = sender;
        [self presentViewController:activityViewController
                           animated:YES
                         completion:nil];
    };


    if (self.screenshotFiles) {
        // Convert screenshotFiles into selectedAssets
        NSArray *selectedScreenshotFiles = [self selectedScreenshotFiles];
        if (selectedScreenshotFiles.count == 0) {
            return;
        }
        CLLog(@"Sharing %ld screenshot files", (long)selectedScreenshotFiles.count);
        NSMutableArray *selectedFileUrls = [NSMutableArray arrayWithCapacity:selectedScreenshotFiles.count];
        for (ScreenshotFileInfo *screenshotFile in selectedScreenshotFiles) {
            [selectedFileUrls addObject:screenshotFile.fileUrl];
        }
        showActivityViewControllerWithItems(selectedFileUrls);
    } else {
        // We have core-data items
        NSArray *selectedScreenshots = [self selectedScreenshots];
        if (selectedScreenshots.count == 0) {
            return;
        }

        CLLog(@"Sharing %ld screenshots", (long)selectedScreenshots.count);
        // Convert selectedScreenshots --> selectedAssetDatas
        NSMutableArray *selectedAssetDatas = [NSMutableArray arrayWithCapacity:selectedScreenshots.count];
        __block NSUInteger numAssetsToLoad = selectedScreenshots.count;
        PHImageRequestOptions *requestOptions = [[PHImageRequestOptions alloc] init];
        requestOptions.version = PHImageRequestOptionsVersionUnadjusted;
        requestOptions.networkAccessAllowed = YES;
        for (Screenshot *screenshot in selectedScreenshots) {
            PHAsset *phAsset = self.screenshotAssetsById[screenshot.localAssetURL];
            if (phAsset) {
                [[PHImageManager defaultManager] requestImageDataForAsset:phAsset options:requestOptions resultHandler:^(NSData *imageData,
                                                                                                                         NSString *dataUTI,
                                                                                                                         UIImageOrientation orientation,
                                                                                                                         NSDictionary *info) {
                    if (imageData) {
                        [selectedAssetDatas addObject:imageData];
                    } else {
                        CLLog(@"Missing imageData for asset: %@,, dataUTI: %@, info: %@", phAsset, dataUTI, info);
                    }
                    numAssetsToLoad--;
                    if (numAssetsToLoad == 0) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            showActivityViewControllerWithItems(selectedAssetDatas);
                        });
                    }
                }];
            } else {
                CLLog(@"Didn't fine phAsset for screenshot asset id: %@, skipping.", screenshot.localAssetURL);
                numAssetsToLoad--;
            }
        }
    }
}


#pragma mark - Going in/out of selection mode


- (void)beginSelectingItemsAnimated:(BOOL)animated
{
    [self.navigationItem setHidesBackButton:YES animated:animated];
    [self.navigationItem setLeftBarButtonItem:self.cancelSelectionBarButtonItem animated:animated];
    [self.navigationItem setRightBarButtonItem:self.shareSelectionBarButtonItem animated:animated];
    self.collectionView.allowsSelection = YES;
    self.toolbarItems = self.barItemsDuringSelection;
    if (HIDE_SHOW_TOOLBAR_WITH_SELECTION) {
        [self.navigationController setToolbarHidden:NO animated:YES];
    }
    [self updateNavigationTitle];
    [self updateToolbarItemsAnimated:YES];
}


- (void)finishSelectingItems
{
    [self.navigationItem setLeftBarButtonItem:self.splitViewController.displayModeButtonItem animated:YES];
    [self.navigationItem setRightBarButtonItem:self.selectBarButtonItem animated:YES];
    [self.navigationItem setHidesBackButton:NO animated:YES];
    NSArray *selectedIndexPaths = [self.collectionView indexPathsForSelectedItems];
    for (NSIndexPath *indexPath in selectedIndexPaths) {
        [self.collectionView deselectItemAtIndexPath:indexPath animated:NO];
    }
    self.collectionView.allowsSelection = NO;
    self.toolbarItems = self.barItemsDuringScroll; // Usually the same ref as 'duringSelection'
    if (HIDE_SHOW_TOOLBAR_WITH_SELECTION) {
        [self.navigationController setToolbarHidden:YES animated:YES];
    }
    [self updateNavigationTitle];
    [self updateToolbarItemsAnimated:NO];
}


- (void)updateNavigationTitle
{
    if (self.collectionView.allowsSelection) {
        self.navigationItem.titleView = nil;
        NSInteger numSelected = self.collectionView.indexPathsForSelectedItems.count;
        if (numSelected == 0) {
            self.navigationItem.title = NSLocalizedStringWithDefaultValue(@"screenshotList.title.selectItems",
                                                                          nil,
                                                                          [NSBundle mainBundle],
                                                                          @"Select Items",
                                                                          @"'Select Items' in English, prompting user to select items. Title of navigation bar.");
        } else {
            NSString *formatString = NSLocalizedStringWithDefaultValue(@"screenshotList.title.nSelected",
                                                                       nil,
                                                                       [NSBundle mainBundle],
                                                                       @"%ld Item(s) Selected",
                                                                       "(See .stringsdict) 'N Item(s) selected', in English. Title of navigation bar.");
            self.navigationItem.title = [NSString localizedStringWithFormat:formatString, (long)numSelected];
        }
    } else if (self.folder == nil && !self.showAllScreenshots && [ScreenshotCatalog sharedCatalog].syncingDatabase) {
        if (!self.collectionTitleViewDuringUpdate) {
            self.collectionTitleViewDuringUpdate = [[UIView alloc] initWithFrame:CGRectZero];
            NSDictionary *titleTextAttributes = [UINavigationBar appearance].titleTextAttributes;

            UILabel *updatingLabel = [[UILabel alloc] initWithFrame:CGRectZero];
            NSString *updatingText = NSLocalizedStringWithDefaultValue(@"screenshotList.title.updating",
                                                                       nil,
                                                                       [NSBundle mainBundle],
                                                                       @"Updating...",
                                                                       @"Progress message as title on navigation bar. 'Updating...' in English");
            updatingLabel.attributedText = [[NSAttributedString alloc] initWithString:updatingText attributes:titleTextAttributes];
            updatingLabel.translatesAutoresizingMaskIntoConstraints = NO;
            [updatingLabel sizeToFit];

            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
            [spinner startAnimating];
            spinner.translatesAutoresizingMaskIntoConstraints = NO;

            [self.collectionTitleViewDuringUpdate addSubview:spinner];
            [self.collectionTitleViewDuringUpdate addSubview:updatingLabel];

            // Make updating label and spinner horizontally attached
            [self.collectionTitleViewDuringUpdate addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[spinner]-[updatingLabel]|"
                                                                                                         options:0
                                                                                                         metrics:nil
                                                                                                           views:NSDictionaryOfVariableBindings(updatingLabel, spinner)]];
            // Set size of view to height of updatingLabel
            [self.collectionTitleViewDuringUpdate addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[updatingLabel]|"
                                                                                                         options:0
                                                                                                         metrics:nil
                                                                                                           views:NSDictionaryOfVariableBindings(updatingLabel)]];
            // Center spinner to updating label
            [self.collectionTitleViewDuringUpdate addConstraint:[NSLayoutConstraint constraintWithItem:spinner
                                                                                             attribute:NSLayoutAttributeCenterY
                                                                                             relatedBy:NSLayoutRelationEqual
                                                                                                toItem:updatingLabel
                                                                                             attribute:NSLayoutAttributeCenterY
                                                                                            multiplier:1.0
                                                                                              constant:0.0]];
            [self.collectionTitleViewDuringUpdate sizeToFit];
            CGRect titleViewRect = self.collectionTitleViewDuringUpdate.frame;
            titleViewRect.size.width = CGRectGetWidth(updatingLabel.bounds) + 8 + CGRectGetWidth(spinner.bounds);
            titleViewRect.size.height = CGRectGetHeight(updatingLabel.bounds);
            self.collectionTitleViewDuringUpdate.frame = titleViewRect;
        }

        self.navigationItem.title = nil;
        self.navigationItem.titleView = self.collectionTitleViewDuringUpdate;
    } else {
        self.navigationItem.titleView = nil;
        self.navigationItem.title = self.collectionTitle;
    }
}


- (void)updateToolbarItemsAnimated:(BOOL)animated
{
    NSInteger numSelected = self.collectionView.indexPathsForSelectedItems.count;
    self.toolbarTrashAllItem.enabled = (numSelected == 0 && (self.screenshots.count > 0 || self.screenshotFiles.count > 0)); // only active if nothing selected and we have items in our collection
    BOOL itemsEnabled = numSelected > 0;
    self.toolbarTagItem.enabled = itemsEnabled;
    self.toolbarUntagItem.enabled = itemsEnabled;
    self.toolbarTrashItem.enabled = itemsEnabled;
    self.toolbarUntrashItem.enabled = itemsEnabled;
    self.shareSelectionBarButtonItem.enabled = itemsEnabled;
    if (itemsEnabled) {
        //self.navigationController.toolbar.tintColor = [UIColor whiteColor];
    } else {
        //self.navigationController.toolbar.tintColor = [UIColor colorWithWhite:1.0 alpha:0.7];
    }
    self.iconAndLabelButtonForTagOrUntag.tintColor = self.navigationController.toolbar.tintColor;
}


#pragma mark - indexPath calculation


- (NSArray *)indexPathsForScreenshots:(NSArray *)screenshots
{
    if (screenshots.count == 0) {
        return @[];
    }
    NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:screenshots.count];
    for (Screenshot *screenshot in screenshots) {
        NSInteger index = [self.screenshots indexOfObject:screenshot];
        if (index != NSNotFound) {
            [indexPaths addObject:[NSIndexPath indexPathForItem:index inSection:0]];
        }
    }

    return indexPaths;
}


- (NSArray *)indexPathsForScreenshotFiles:(NSArray *)screenshotFiles
{
    if (self.screenshotFiles.count == 0) {
        return @[];
    }
    NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:screenshotFiles.count];
    for (ScreenshotFileInfo *screenshotFile in screenshotFiles) {
        NSInteger index = [self.screenshotFiles indexOfObject:screenshotFile];
        if (index != NSNotFound) {
            [indexPaths addObject:[NSIndexPath indexPathForItem:index inSection:0]];
        }
    }

    return indexPaths;
}


#pragma mark - CLQuickLookViewControllerDelegate


- (void)quickLookViewControllerDidRequestDismiss:(CLQuickLookViewController *)controller
{
    self.transitionManager = [[CLQuickLookTransitionManager alloc] init];
    self.transitionManager.quickLookSourceDelegate = self;
    self.transitionManager.screenshot = controller.screenshot;
    self.transitionManager.phAsset = controller.phAsset;
    self.transitionManager.screenshotFile = controller.screenshotFile;
    self.transitionManager.screenshotView = controller.screenshotView;

    [self dismissViewControllerAnimated:YES completion:^{
        self.transitionManager = nil;
        controller.transitioningDelegate = nil;
    }];
}


#pragma mark - Loading Screenshots from Assets Library


- (void)loadScreenshotsLoadMore:(BOOL)loadMore
{
    if (loadMore && self.allScreenshotsLoaded) {
        return; // Early shortcut here;
    }

    if (self.folder) {
        return; // no need to load screenshots by paging (at least not yet)
    }

    CLLog(@"Loading screenshots, load more = %d", loadMore);

    self.loadingScreenshots = YES;

    NSManagedObjectContext *context = [ScreenshotCatalog sharedCatalog].managedObjectContext;
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"Screenshot"];
    if (self.tagToFilter) {
        request.predicate = [NSPredicate predicateWithFormat:@"(tags CONTAINS %@)", self.tagToFilter];
    } else if (!self.showAllScreenshots) {
        // Unfiled, so only screenshots without tags
        request.predicate = [NSPredicate predicateWithFormat:@"(tags.@count == 0)", self.tagToFilter];
    }
    NSSortDescriptor *timestampSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"timestamp" ascending:SORT_ASCENDING];
    request.sortDescriptors = @[timestampSortDescriptor];

    NSInteger batchSize = self.customBatchSize > 0 ? self.customBatchSize : 30;

    NSError *countError;
    NSUInteger numTotalResults = [context countForFetchRequest:request error:&countError];
    NSInteger offset = 0;
    if (loadMore) {
        if (SORT_ASCENDING) {
            offset = numTotalResults - self.lastAssetOffset - batchSize;
        } else {
            offset = self.lastAssetOffset;
        }
    } else {
        if (SORT_ASCENDING) {
            // Clean load starts N back from end
            offset = numTotalResults - batchSize;
        } else {
            offset = 0;
        }
    }

    if (offset < 0) {
        // Protect against going negative, and adjust our batch size too
        batchSize += offset;
        offset = 0;
    }

    request.fetchOffset = offset;
    request.fetchBatchSize = batchSize;

    NSError *fetchError;
    NSArray *results = [context executeFetchRequest:request error:&fetchError];
    self.loadingScreenshots = NO;
    if (fetchError == nil) {
        NSArray *previouslySelectedItems = nil;
        if (self.collectionView.indexPathsForSelectedItems.count > 0) {
            if (self.folder) {
                previouslySelectedItems = [self selectedScreenshotFiles];
            } else {
                previouslySelectedItems = [self selectedScreenshots];
            }
        }
        if (!loadMore) {
            [self.screenshots removeAllObjects];
            [self.screenshotAssetsById removeAllObjects];
            self.lastAssetOffset = 0;
        }

        // Create PHAssets out of the assetUrls/localIdentifiers

        // Because the results are batched, asking for more than the batch
        // will do an internal fetch. So, let's only add in
        // what we said the batch should be (or less)
        NSInteger numToAdd = MIN(request.fetchBatchSize, results.count);
        NSArray *resultsNotNeedingAdditionalFetch = results;
        if (numToAdd < results.count) {
            resultsNotNeedingAdditionalFetch = [results subarrayWithRange:NSMakeRange(0, numToAdd)];
        }
        if (numToAdd > 0) {
            NSDictionary *newScreenshotAssetsById = [self screenshotAssetsByIdFromScreenshots:resultsNotNeedingAdditionalFetch];
            if (newScreenshotAssetsById.count != resultsNotNeedingAdditionalFetch.count) {
                CLLog(@"Got %lu results, but only %lu assets, adding only matching screenshots",
                      (unsigned long)resultsNotNeedingAdditionalFetch.count,
                      (unsigned long)newScreenshotAssetsById.count);
                resultsNotNeedingAdditionalFetch = [self screenshotsContainingAssetIds:[NSSet setWithArray:newScreenshotAssetsById.allKeys]
                                                                       fromScreenshots:resultsNotNeedingAdditionalFetch];
            }
            NSInteger startingIndex = SORT_ASCENDING ? 0 : self.screenshots.count;
            [self.screenshots insertObjects:resultsNotNeedingAdditionalFetch
                                  atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(startingIndex, resultsNotNeedingAdditionalFetch.count)]];

            [self.screenshotAssetsById addEntriesFromDictionary:newScreenshotAssetsById];

            // Now we can reload the collection view
            [self reloadDataReselectItems:previouslySelectedItems maintainOffset:(SORT_ASCENDING && loadMore)];

            if (SORT_ASCENDING) {
                if (!loadMore) {
                    if (self.beingShown) {
                        [self scrollToBottomOfCollectionView:self.collectionView animated:NO];
                    } else {
                        self.shouldScrollToBottom = YES;
                    }
                }
            }
        } else {
            // Often we end up here if the the last remaining screenshots were filed and then we did a -loadScreenshots
            [self reloadDataReselectItems:previouslySelectedItems maintainOffset:(SORT_ASCENDING && loadMore)];
        }
    }
    self.allScreenshotsLoaded = results.count == 0;
    self.lastAssetOffset = self.screenshots.count;
    [self.slideshowViewController invalidateItemCount];
}


- (NSDictionary *)screenshotAssetsByIdFromScreenshots:(NSArray *)screenshots
{
    // Sort screenshots by timestamp first, to ensure that they are in the same order as what we'll ask from assets
    screenshots = [screenshots sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        Screenshot *screenshot1 = (Screenshot *)obj1;
        Screenshot *screenshot2 = (Screenshot *)obj2;
        if (SORT_ASCENDING) {
            return [screenshot1.timestamp compare:screenshot2.timestamp];
        } else {
            return [screenshot2.timestamp compare:screenshot1.timestamp];
        }
    }];
    NSMutableDictionary *screenshotAssetsById = [NSMutableDictionary dictionaryWithCapacity:screenshots.count];

    // Fetch and hold onto all the PHAssets in a dictionary, referenced by screenshot.localAssetUrl
    NSMutableArray *screenshotsWithAssetURLs = [NSMutableArray arrayWithCapacity:screenshots.count];
    NSMutableArray *assetURLs = [NSMutableArray arrayWithCapacity:screenshots.count];
    NSMutableArray *assetLocalIdentifiers = [NSMutableArray arrayWithCapacity:screenshots.count];
    for (Screenshot *screenshot in screenshots) {
        if ([screenshot.localAssetURL hasPrefix:@"assets-library://"]) {
            [screenshotsWithAssetURLs addObject:screenshot];
            [assetURLs addObject:[NSURL URLWithString:screenshot.localAssetURL]];
        } else {
            [assetLocalIdentifiers addObject:screenshot.localAssetURL];
        }
    }
    PHFetchResult *assetResults = nil;
    PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
    fetchOptions.wantsIncrementalChangeDetails = NO;
    fetchOptions.includeHiddenAssets = YES;
    // This sort has to match the sort in our screenshots fetch, otherwise the assets and assetURLs are mismatched
    fetchOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:SORT_ASCENDING]];
    if (assetURLs.count > 0) {
        // We have some assets with urls
        NSInteger screenshotIndex = 0;
        assetResults = [PHAsset fetchAssetsWithALAssetURLs:assetURLs options:fetchOptions];
        for (PHAsset *asset in assetResults) {
            Screenshot *screenshot = screenshotsWithAssetURLs[screenshotIndex++];
            screenshotAssetsById[screenshot.localAssetURL] = asset;
        }
    }
    if (assetLocalIdentifiers.count > 0) {
        // We have some assets with local identifiers
        assetResults = [PHAsset fetchAssetsWithLocalIdentifiers:assetLocalIdentifiers options:fetchOptions];
        for (PHAsset *asset in assetResults) {
            screenshotAssetsById[asset.localIdentifier] = asset;
        }
    }

    return screenshotAssetsById;
}


- (void) scrollToBottomOfCollectionView:(UICollectionView *)collectionView animated:(BOOL)animated
{
    NSInteger section = [self numberOfSectionsInCollectionView:collectionView] - 1;
    NSInteger item = [self collectionView:collectionView numberOfItemsInSection:section] - 1;
    NSIndexPath *lastIndexPath = [NSIndexPath indexPathForItem:item inSection:section];
    //[collectionView scrollToItemAtIndexPath:lastIndexPath atScrollPosition:UICollectionViewScrollPositionBottom animated:animated];

    CGRect lastCellRect = [collectionView layoutAttributesForItemAtIndexPath:lastIndexPath].frame;
    //lastCellRect.origin.y += 64.0;
    //[collectionView scrollRectToVisible:CGRectInset(lastCellRect, 0, 0) animated:animated];
    [collectionView setContentOffset:CGPointMake(0, CGRectGetMaxY(lastCellRect)) animated:animated];
}


#pragma mark - Tagging Screenshots


- (NSArray *)selectedScreenshots
{
    NSArray *selectedIndexPaths = self.collectionView.indexPathsForSelectedItems;
    if (selectedIndexPaths.count == 0) {
        return @[];
    }

    NSMutableArray *selectedScreenshots = [NSMutableArray arrayWithCapacity:selectedIndexPaths.count];
    for (NSIndexPath *selectedIndexPath in selectedIndexPaths) {
        [selectedScreenshots addObject:self.screenshots[selectedIndexPath.item]];
    }
    return selectedScreenshots;
}


- (NSArray *)selectedScreenshotFiles
{
    NSArray *selectedIndexPaths = self.collectionView.indexPathsForSelectedItems;
    if (selectedIndexPaths.count == 0) {
        return @[];
    }

    NSMutableArray *selectedFiles = [NSMutableArray arrayWithCapacity:selectedIndexPaths.count];
    for (NSIndexPath *selectedIndexPath in selectedIndexPaths) {
        [selectedFiles addObject:self.screenshotFiles[selectedIndexPath.item]];
    }
    return selectedFiles;
}


- (NSArray *)assetsForScreenshots:(NSArray *)screenshots
{
    NSMutableArray *assets = [NSMutableArray arrayWithCapacity:screenshots.count];
    for (Screenshot *screenshot in screenshots) {
        PHAsset *asset = self.screenshotAssetsById[screenshot.localAssetURL];
        if (asset) {
            [assets addObject:asset];
        } else {
            CLLog(@"Unable to get asset for screenshot id: %@", screenshot.localAssetURL);
        }
    }
    return assets;
}


- (NSArray *)screenshotsContainingAssetIds:(NSSet *)assetIds fromScreenshots:(NSArray *)screenshots
{
    if (!screenshots) {
        screenshots = self.screenshots;
    }
    NSPredicate *matchingPredicate = [NSPredicate predicateWithFormat:@"(localAssetURL IN %@)", assetIds];
    NSArray *matchingScreenshots = [screenshots filteredArrayUsingPredicate:matchingPredicate];
    return matchingScreenshots;
}


- (void)tagSelectedScreenshotsWithTag:(NSString *)tagName
{
    if (tagName.length == 0) {
        return;
    }
    NSArray *selectedScreenshots = [self selectedScreenshots];
    if (selectedScreenshots.count == 0) {
        return;
    }

    Tag *tag = [[ScreenshotCatalog sharedCatalog] tagScreenshots:selectedScreenshots withTagName:tagName];

    [self notifyUserOfSuccessfulTaggingOfNumberOfScreenshots:selectedScreenshots.count toFolderName:tag.name];
}


- (void)notifyUserOfSuccessfulTaggingOfNumberOfScreenshots:(NSUInteger)numScreenshots toFolderName:(NSString *)folderName
{
    NSString *format = NSLocalizedStringWithDefaultValue(@"screenshotList.banner.nScreenshotsMoved",
                                                         nil,
                                                         [NSBundle mainBundle],
                                                         @"%lu screenshot(s) were moved",
                                                         @"(See .stringsdict) Single-line banner message below navigation bar, informing user of how many (N) screenshots were moved");
    //NSString *format = numScreenshots == 1 ? @"%ld screenshot was moved" : @"%ld screenshots were moved";
    NSString *message = [NSString localizedStringWithFormat:format, (unsigned long)numScreenshots];
    [self showBannerMessage:message];
}


- (void)reallyUntagSelectedScreenshotsAnimated:(BOOL)animated
{
    NSArray *selectedScreenshots = [self selectedScreenshots];
    if (selectedScreenshots.count == 0) {
        return;
    }
    [self removeScreenshots:selectedScreenshots fromCollectionViewWithCompletion:^{

        NSSet *emptyTags = [NSSet set];
        for (Screenshot *screenshot in selectedScreenshots) {
            screenshot.tags = emptyTags;
        }
        NSLog(@"WARNING: NEED to invalidate unfiled screenshot count here");
        [[ScreenshotCatalog sharedCatalog] saveContext];

        [[Analytics sharedInstance] track:@"untag_shots"
                               properties:@{@"num_shots" : @(selectedScreenshots.count)}];
        if (self.screenshots.count == 0) {
            [self.delegate screenshotListViewControllerDidRequestDismiss:self didDeleteTagOrFolder:NO animated:animated];
        }
    } animated:animated];
}


- (void)removeScreenshots:(NSArray *)screenshotsToRemove fromCollectionViewWithCompletion:(void (^)())completionHandler animated:(BOOL)animated
{
    if (screenshotsToRemove.count == 0) {
        if (completionHandler) {
            completionHandler();
        }
        return;
    }


    self.ignoreCatalogChanges = YES;

    __weak CLScreenshotListViewController *_weakSelf = self;
    void (^afterTableItemsRemoved)() = ^{
        if (_weakSelf.shouldReloadFromSource) {
            // We received catalog updates while animating, so reload
            // our existing set
            _weakSelf.customBatchSize = _weakSelf.screenshots.count;
            [_weakSelf loadScreenshotsLoadMore:NO];
            _weakSelf.customBatchSize = 0;
        }
        _weakSelf.ignoreCatalogChanges = NO;
        if (completionHandler) {
            completionHandler();
        }
    };

    // Mark the selected index paths too
    NSArray *indexPathsToRemove = [self indexPathsForScreenshots:screenshotsToRemove];

    if (indexPathsToRemove.count == 0 || indexPathsToRemove.count != screenshotsToRemove.count) {
        CLLog(@"Couldn't match any or all screenshotsToRemove (%lu) with indexPathsToRemove (%lu), reloading everything", (unsigned long)screenshotsToRemove.count, (unsigned long)indexPathsToRemove.count);
        afterTableItemsRemoved();
        return;
    }

    NSIndexPath *firstIndexPath = indexPathsToRemove[0];
    UICollectionViewLayoutAttributes *firstItemAttributes = [self.collectionView layoutAttributesForItemAtIndexPath:firstIndexPath];
    CGRect firstItemRect = CGRectNull;
    if (firstItemAttributes) {
        firstItemRect = firstItemAttributes.frame;
    }
    // Maintain scroll position, if possible
    NSTimeInterval deleteAnimationDelay = 0.0;
    if (!CGRectIsNull(firstItemRect)) {
        // Try to get the original position near the center of the screen (hardcoded 320, yadda yadda)
        CGRect expandedRect = CGRectInset(firstItemRect, 0, -((320-CGRectGetHeight(firstItemRect))/2.0));
        expandedRect.origin.y = MAX(0.0, expandedRect.origin.y); // Don't scroll too far up if image is at/near the top already
        [self.collectionView scrollRectToVisible:expandedRect animated:YES];
        deleteAnimationDelay = animated ? 0.350 : 0.0;
    }

    CLLog(@"Removing %lu screenshots from collection view, with delay: %.2f", (unsigned long)screenshotsToRemove.count, deleteAnimationDelay);

    // Wait for scroll animation and then do delete
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(deleteAnimationDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

        // Remove from local list
        NSInteger numScreenshotsBeforeRemove = self.screenshots.count;
        for (Screenshot *screenshot in screenshotsToRemove) {
            [self.screenshots removeObject:screenshot];
        }
        NSInteger numScreenshotsRemoved = numScreenshotsBeforeRemove - self.screenshots.count;
        CLLog(@"%ld screenshots removed, "
                "%ld indexPaths to animate deletion", (long)numScreenshotsRemoved, (long)indexPathsToRemove.count);

        if (numScreenshotsRemoved != indexPathsToRemove.count) {
            CLLog(@"Num screenshots to remove didn't match indexpaths found, doing full reload");
            [self.collectionView reloadData];
            afterTableItemsRemoved();
        } else {
            // We can animate
            [self       removeSelectedIndexPaths:indexPathsToRemove
                fromCollectionViewWithCompletion:afterTableItemsRemoved
                                        animated:animated];
        }


    });
}




- (void)removeSelectedIndexPaths:(NSArray *)indexPaths fromCollectionViewWithCompletion:(void (^)())completionHandler animated:(BOOL)animated
{
    [self finishSelectingItems];
    if (animated) {
        [self.collectionView performBatchUpdates:^{
            [self.collectionView deleteItemsAtIndexPaths:indexPaths];
        } completion:^(BOOL finished) {
            if (completionHandler) {
                completionHandler();
            }
        }];
    } else {
        [self reloadDataReselectItems:nil maintainOffset:YES];
        if (completionHandler) {
            completionHandler();
        }
    }
}


- (void)reallyDeleteFolder
{
    if (self.folder) {
        NSString *folderName = self.folder.folderName;
        __weak CLScreenshotListViewController *_weakSelf = self;
        [[ScreenshotStorage sharedInstance] deleteScreenshotFolder:self.folder completion:^(BOOL success, NSError *error) {
            [_weakSelf.delegate screenshotListViewControllerDidRequestDismiss:_weakSelf didDeleteTagOrFolder:YES animated:YES];
        }];
        [[Analytics sharedInstance] track:@"delete_folder"
                               properties:@{@"folder_name" : folderName}];
    } else if (self.tagToFilter) {
        NSString *tagName = self.tagToFilter.name;
        [[ScreenshotCatalog sharedCatalog] deleteTag:self.tagToFilter];

        [[Analytics sharedInstance] track:@"delete_tag"
                               properties:@{@"tag_name" : tagName}];
        [self.delegate screenshotListViewControllerDidRequestDismiss:self didDeleteTagOrFolder:YES animated:YES];
    }

}


#pragma mar - Trashing/Untrashing Screenshots


- (void)askUserToConfirmTrashingItems:(NSArray *)itemsToTrash fromSender:(id)sender
{
    NSString *destructiveTitle = nil;
    NSString *message = nil;
    if (self.folder) {
        if ([ScreenshotStorage sharedInstance].iCloudEnabled) {
            destructiveTitle = NSLocalizedStringWithDefaultValue(@"screenshotList.deleteConfirmation.title.iCloudFolder",
                                                                 nil,
                                                                 [NSBundle mainBundle],
                                                                 @"Delete from iCloud",
                                                                 @"Button title to confirm deleting screenshot(s) from iCloud");
            message = NSLocalizedStringWithDefaultValue(@"screenshotList.deleteConfirmation.message.iCloudFolder",
                                                        nil,
                                                        [NSBundle mainBundle],
                                                        @"This screenshot will be deleted from iCloud Drive and your other iCloud devices.",
                                                        @"Message for action sheet, explaining that the screenshot will be deleted from iCloud Drive and all other iCloud devices.");
        } else {
            // Local documents
            destructiveTitle = NSLocalizedStringWithDefaultValue(@"screenshotList.deleteConfirmation.title.localFolder",
                                                                 nil,
                                                                 [NSBundle mainBundle],
                                                                 @"Delete",
                                                                 @"Button title to delete screenshot(s) from a local folder.");
        }
    } else if (MARK_SCREENSHOTS_AS_ARCHIVE_INSTEAD_OF_DELETE) {
        destructiveTitle = NSLocalizedStringWithDefaultValue(@"screenshotList.deleteConfirmation.title.cameraRoll.archive",
                                                             nil,
                                                             [NSBundle mainBundle],
                                                             @"Archive",
                                                             @"Button title to archive screenshot(s) from camera roll");
    } else {
        destructiveTitle = NSLocalizedStringWithDefaultValue(@"screenshotList.deleteConfirmation.title.cameraRoll",
                                                             nil,
                                                             [NSBundle mainBundle],
                                                             @"Delete from Camera Roll",
                                                             @"Button title to delete screenshot(s) from camera roll. Camera roll should be mentioned here, because it is a permanent delete.");
    }
    UIAlertController *confirmation = [UIAlertController alertControllerWithTitle:nil
                                                                          message:message
                                                                   preferredStyle:UIAlertControllerStyleActionSheet];
    __weak CLScreenshotListViewController *_weakSelf = self;
    [confirmation addAction:[UIAlertAction actionWithTitle:destructiveTitle style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [_weakSelf trashScreenshotItems:itemsToTrash animated:YES];
    }]];
    NSString *cancelTitle = NSLocalizedStringWithDefaultValue(@"screenshotList.deleteConfirmation.cancel",
                                                              nil,
                                                              [NSBundle mainBundle],
                                                              @"Cancel",
                                                              @"Button title to cancel the screenshot delete confirmation action sheet");
    [confirmation addAction:[UIAlertAction actionWithTitle:cancelTitle style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        CLLog(@"Cancelled delete on action sheet");
    }]];
    if ([sender isKindOfClass:[UIBarButtonItem class]]) {
        confirmation.popoverPresentationController.barButtonItem = self.toolbarTrashItem;
    } else if ([sender isKindOfClass:[UIView class]]){
        confirmation.popoverPresentationController.sourceView = sender;
        confirmation.popoverPresentationController.sourceRect = ((UIView *)sender).bounds;
    }
    [self presentViewController:confirmation animated:YES completion:nil];
}


- (void)removeScreenshotFilesAndUpdateUI:(NSArray *)screenshotFilesToRemove
{
    NSArray *indexPaths = [self indexPathsForScreenshotFiles:screenshotFilesToRemove];
    [self.screenshotFiles removeObjectsInArray:screenshotFilesToRemove];
    // Animate items being removed if we have items to remove, and we are still left with some items
    if (indexPaths.count > 0 && self.screenshotFiles.count > 0) {
        [self removeSelectedIndexPaths:indexPaths fromCollectionViewWithCompletion:^{
            [self finishSelectingItems];
        } animated:YES];
    } else {
        [self.collectionView reloadData];
        [self finishSelectingItems];
        [self updateEmptyUI];
    }
}


- (void)trashScreenshotItems:(NSArray *)itemsToTrash animated:(BOOL)animated
{
    if (itemsToTrash.count == 0) {
        return;
    }
    if (self.folder) {
        NSArray *screenshotFilesTotrash = itemsToTrash;//[self selectedScreenshotFiles];
        [[ScreenshotStorage sharedInstance] deleteScreenshotFiles:screenshotFilesTotrash completion:^(BOOL success, NSError *error) {
            [[Analytics sharedInstance] track:@"delete_icoud_shots"
                                   properties:@{@"num_shots" : @(screenshotFilesTotrash.count)}];
            [self removeScreenshotFilesAndUpdateUI:screenshotFilesTotrash];
        }];
    } else {
        NSArray *screenshotsToTrash = itemsToTrash;//[self selectedScreenshots];
        if (MARK_SCREENSHOTS_AS_ARCHIVE_INSTEAD_OF_DELETE) {
            // Just "tag" them in our local DB
            Tag *trashTag = [[ScreenshotCatalog sharedCatalog] createTrashTagIfNeeded];
            [self removeScreenshots:screenshotsToTrash fromCollectionViewWithCompletion:^{

                NSSet *trashTagSet = [NSSet setWithObject:trashTag];
                for (Screenshot *screenshot in screenshotsToTrash) {
                    screenshot.tags = trashTagSet;
                }
                [[ScreenshotCatalog sharedCatalog] saveContext];

                [[Analytics sharedInstance] track:@"archive_shots"
                                       properties:@{@"num_shots" : @(screenshotsToTrash.count)}];
                if (self.screenshots.count == 0) {
                    [self.delegate screenshotListViewControllerDidRequestDismiss:self didDeleteTagOrFolder:NO animated:animated];
                }
            } animated:animated];

        } else {
            // Actual Delete images from camera roll
            NSArray *assetsToDelete = [self assetsForScreenshots:screenshotsToTrash];

            NSMutableSet *assetIdsToDelete = [NSMutableSet setWithCapacity:assetsToDelete.count];
            for (PHAsset *asset in assetsToDelete) {
                [assetIdsToDelete addObject:asset.localIdentifier];
            }

            void (^handleDeleteResponse)(BOOL, NSError *) = ^(BOOL success, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (success) {
                        CLLog(@"Success completion handler for PHPhotoLibrary performChanges:");
                        // Assets were deleted, refresh
                        // Particularly with deleted assets, it's a race condition whether or not the 'screenshotsToTrash'
                        // have already been deleted (and therefore don't have an assetId), so use our assetIds and re-create
                        // the screenshots to delete from our current data modal
                        NSArray *existingScreenshotsToTrash = [self screenshotsContainingAssetIds:assetIdsToDelete fromScreenshots:self.screenshots];
                        if (existingScreenshotsToTrash.count != screenshotsToTrash.count) {
                            CLLog(@"Existing screenshots to trash (%lu) is less than the original amount (%lu)", (unsigned long)existingScreenshotsToTrash.count, (unsigned long)screenshotsToTrash.count);
                        }
                        [self removeScreenshots:existingScreenshotsToTrash fromCollectionViewWithCompletion:^{
                            [self finishSelectingItems];

                            [[ScreenshotCatalog sharedCatalog] deleteScreenshots:screenshotsToTrash];

                            [[Analytics sharedInstance] track:@"delete_device_shots"
                                                   properties:@{@"num_shots" : @(screenshotsToTrash.count)}];
                            if (self.screenshots.count == 0) {
                                [self.delegate screenshotListViewControllerDidRequestDismiss:self didDeleteTagOrFolder:NO animated:animated];
                            }
                        } animated:YES];
                    } else {
                        if (error.code == -1) {
                            CLLog(@"Cancelled delete on PHPhotoLibrary prompt");
                        } else {
                            CLLog(@"Error from PHPhotoLibrary: %@", error);
                        }
                    }
                });
            };

            BOOL fakeDelete = NO;
            if (fakeDelete) {
                [[ScreenshotCatalog sharedCatalog] fakeRemoveScreenshotsWithAssetIds:assetIdsToDelete
                                                                          completion:handleDeleteResponse];
            } else {
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    [PHAssetChangeRequest deleteAssets:assetsToDelete];
                } completionHandler:handleDeleteResponse];
            }
        }
    }
}


- (void)untrashSelectedScreenshots
{
    // For now, just untagging screenshots removes them from being in 'Trash'
    [self reallyUntagSelectedScreenshotsAnimated:YES];
}


#pragma mark - Toolbar Actions


- (void)logUserTapOnToolbarItem:(id)sender
{
    NSString *title = nil;
    if ([sender isKindOfClass:[UIButton class]]) {
        title = ((TintColorButton *)sender).titleLabel.text;
    } else if ([sender isKindOfClass:[UIBarButtonItem class]]) {
        UIBarButtonItem *barItem = (UIBarButtonItem *)sender;
        title = barItem.title;
    }
    CLLog(@"Tapped bar button: %@", title);
}


- (void)onToolbarTagItemTapped:(id)sender
{
    [self logUserTapOnToolbarItem:sender];
    CLTaggingViewController *taggingViewController = nil;
    if (self.folder) {
        NSArray *selectedScreenshotFiles = [self selectedScreenshotFiles];
        if (selectedScreenshotFiles.count == 0) {
            return;
        }
        taggingViewController = [[CLTaggingViewController alloc] initWithScreenshotFiles:selectedScreenshotFiles initialTag:nil delegate:self];
    } else {
        NSArray *selectedScreenshots = [self selectedScreenshots];
        if (selectedScreenshots.count == 0) {
            return;
        }
        NSArray *assets = [self assetsForScreenshots:selectedScreenshots];
        taggingViewController = [[CLTaggingViewController alloc] initWithScreenshots:selectedScreenshots assets:assets initialTag:nil delegate:self];
    }
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:taggingViewController];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;

    NSMutableArray *selectionBarItemsWithSpinner = [self.barItemsDuringSelection mutableCopy];
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    [spinner startAnimating];
    UIBarButtonItem *spinnerBarItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];
    [selectionBarItemsWithSpinner replaceObjectAtIndex:[selectionBarItemsWithSpinner indexOfObject:self.toolbarTagItem] withObject:spinnerBarItem];
    self.toolbarItems = selectionBarItemsWithSpinner;
    [self presentViewController:nav animated:YES completion:^{
        self.toolbarItems = self.barItemsDuringSelection;
    }];
}


- (void)onToolbarUntagItemTapped:(id)sender
{
    [self logUserTapOnToolbarItem:sender];
    NSString *format = NSLocalizedStringWithDefaultValue(@"screenshotList.untagConfirmation.title",
                                                         nil,
                                                         [NSBundle mainBundle],
                                                         @"Remove from '%@' folder?",
                                                         @"Title on action sheet, to confirm removing from the named folder");
    NSString *title = [NSString stringWithFormat:format, self.tagToFilter.name];
    NSString *cancelTitle = NSLocalizedStringWithDefaultValue(@"screenshotList.untagConfirmation.cancel",
                                                              nil,
                                                              [NSBundle mainBundle],
                                                              @"Cancel",
                                                              @"Cancel button title on remove-from-folder action sheet");
    NSString *removeTitle = NSLocalizedStringWithDefaultValue(@"screenshotList.untagConfirmation.remove",
                                                              nil,
                                                              [NSBundle mainBundle],
                                                              @"Remove",
                                                              @"Remove button title on remove-from-folder action sheet. This is the destructive action.");
    self.screenshotUntaggingActionSheet = [[UIActionSheet alloc] initWithTitle:title
                                                                      delegate:self
                                                             cancelButtonTitle:cancelTitle
                                                        destructiveButtonTitle:removeTitle
                                                             otherButtonTitles:nil];
    [self.screenshotUntaggingActionSheet showFromBarButtonItem:self.toolbarUntagItem
                                                      animated:YES];
}


- (void)onToolbarTrashItemTapped:(id)sender
{
    CLLog(@"Tapped trash bar button");
    BOOL hasShownHintBefore = [[NSUserDefaults standardUserDefaults] boolForKey:HAS_SHOWN_ARCHIVE_HINT_BEFORE_KEY];
    Tag *trashTag = [[ScreenshotCatalog sharedCatalog] trashTag];
    if (MARK_SCREENSHOTS_AS_ARCHIVE_INSTEAD_OF_DELETE && !hasShownHintBefore && trashTag == nil && !self.folder) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:HAS_SHOWN_ARCHIVE_HINT_BEFORE_KEY];
        NSString *message = @"This just puts these screenshots into a folder called Archive to get them out of the way.";
        self.firstTimeScreenshotTrashingAlertView = [[UIAlertView alloc] initWithTitle:@"What is Archive?"
                                                                               message:message
                                                                              delegate:self
                                                                     cancelButtonTitle:nil
                                                                     otherButtonTitles:@"Got It", nil];
        [self.firstTimeScreenshotTrashingAlertView show];
    } else {

        NSArray *items = nil;
        if (self.folder) {
            items = [self selectedScreenshotFiles];
        } else {
            items =  [self selectedScreenshots];
        }
        [self askUserToConfirmTrashingItems:items fromSender:sender];
    }
}


- (void)onToolbarTrashAllItemTapped:(id)sender
{
    [self logUserTapOnToolbarItem:sender];
    if (self.tagToFilter) {
        // *ALL* screenshots in our list
        // Since we are being asked to delete *ALL* screenshots, we need to
        // potentially load all screenshots first, and then confirm trashing
        NSUInteger numAllScreenshots = self.tagToFilter.screenshots.count;
        if (self.screenshots.count < numAllScreenshots) {
            CLLog(@"Loading *ALL* %lu screenshots before showing delete-all confirmation", (unsigned long)numAllScreenshots);
            self.customBatchSize = numAllScreenshots;
            [self loadScreenshotsLoadMore:NO];
            self.customBatchSize = 0;
        }
        [self askUserToConfirmTrashingItems:[self.screenshots copy] fromSender:sender];

    } else if (self.folder) {
        // *ALL* screenshot files in our list
        [self askUserToConfirmTrashingItems:[self.screenshotFiles copy] fromSender:sender];
    }
}


- (void)onToolbarUntrashItemTapped:(id)sender
{
    [self logUserTapOnToolbarItem:sender];
    [self untrashSelectedScreenshots];
}


#pragma mark - Button Actions


- (void)onDeleteTagButtonTapped:(id)sender
{
    [self logUserTapOnToolbarItem:sender];
    __weak CLScreenshotListViewController *_weakSelf = self;

    NSString *folderName = self.tagToFilter.name;
    NSString *message = nil;
    if (self.folder) {
        folderName = self.folder.folderName;
        if ([ScreenshotStorage sharedInstance].iCloudEnabled) {
            message = NSLocalizedStringWithDefaultValue(@"screenshotList.deleteFolderConfirmation.message.iCloud",
                                                        nil,
                                                        [NSBundle mainBundle],
                                                        @"This folder will be deleted from iCloud Drive and your other iCloud devices.",
                                                        @"message over action sheet, explaining that the folder will be deleted from iCloud Drive and all other iCloud devices.");
        }
    }
    NSString *titleFormat = NSLocalizedStringWithDefaultValue(@"screenshotList.deleteFolderConfirmation.title",
                                                              nil,
                                                              [NSBundle mainBundle],
                                                              @"Remove '%@'?",
                                                              @"Title on action sheet, confirmation whether to delete the named folder, written very concisely.");
    NSString *title = [NSString localizedStringWithFormat:titleFormat, folderName];
    UIAlertController *confirmDelete = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleActionSheet];

    NSString *removeTitle = NSLocalizedStringWithDefaultValue(@"screenshotList.deleteFolderConfirmation.remove",
                                                              nil,
                                                              [NSBundle mainBundle],
                                                              @"Remove",
                                                              @"Remove button title on remove-folder action sheet. This is the destructive action.");
    [confirmDelete addAction:[UIAlertAction actionWithTitle:removeTitle style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [_weakSelf reallyDeleteFolder];
    }]];

    NSString *cancelTitle = NSLocalizedStringWithDefaultValue(@"screenshotList.deleteFolderConfirmation.cancel",
                                                              nil,
                                                              [NSBundle mainBundle],
                                                              @"Cancel",
                                                              @"Cancel button title on remove-folder action sheet");
    [confirmDelete addAction:[UIAlertAction actionWithTitle:cancelTitle style:UIAlertActionStyleCancel handler:nil]];

    confirmDelete.popoverPresentationController.sourceView = (UIView *)sender;
    confirmDelete.popoverPresentationController.sourceRect = ((UIView *)sender).bounds;
    [self presentViewController:confirmDelete animated:YES completion:nil];
}


#pragma mark - CLTaggingViewControllerDelegate


- (void)taggingViewControllerDidCancel:(CLTaggingViewController *)controller
{
    [self dismissViewControllerAnimated:YES completion:nil];
}


- (void)taggingViewController:(CLTaggingViewController *)controller didSaveItemsToFolder:(ScreenshotFolder *)folder alsoAddedToTag:(Tag *)tag
{
    NSIndexPath *firstSelectedIndexPath = self.collectionView.indexPathsForSelectedItems.firstObject;
    if (firstSelectedIndexPath) {
        [self.collectionView scrollToItemAtIndexPath:firstSelectedIndexPath atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:NO];
    }
    [self finishSelectingItems];
    [self dismissViewControllerAnimated:YES completion:^{
        if (controller.screenshotFiles) {
            [self removeScreenshotFilesAndUpdateUI:controller.screenshotFiles];
        }
        NSUInteger numScreenshots = controller.screenshotFiles ? controller.screenshotFiles.count : controller.screenshots.count;
        NSString *folderName = folder ? folder.folderName : tag.name;
        [self notifyUserOfSuccessfulTaggingOfNumberOfScreenshots:numScreenshots toFolderName:folderName];
    }];
}


#pragma mark - Empty UI


- (void)buildEmptyUI
{
    CGFloat emptyUIWidth = 260.0;
    self.emptyUIView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, emptyUIWidth, 480.0)];
    self.emptyUIView.translatesAutoresizingMaskIntoConstraints = NO;

    // Title
    self.emptyUITitle = [[UILabel alloc] initWithFrame:CGRectZero];
    self.emptyUITitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyUITitle.numberOfLines = 5;
    self.emptyUITitle.lineBreakMode = NSLineBreakByWordWrapping;
    self.emptyUITitle.font = [UIFont boldSystemFontOfSize:18.0];
    self.emptyUITitle.textColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    self.emptyUITitle.preferredMaxLayoutWidth = emptyUIWidth;
    self.emptyUITitle.textAlignment = NSTextAlignmentCenter;
    self.emptyUITitle.text = [self noScreenshotsFoundEmptyTitle];

    [self.emptyUIView addSubview:self.emptyUITitle];

    // Message
    self.emptyUIMessage = [[UILabel alloc] initWithFrame:CGRectZero];
    self.emptyUIMessage.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyUIMessage.numberOfLines = 5;
    self.emptyUIMessage.lineBreakMode = NSLineBreakByWordWrapping;
    self.emptyUIMessage.font = [UIFont systemFontOfSize:14.0];
    self.emptyUIMessage.textColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    self.emptyUIMessage.preferredMaxLayoutWidth = emptyUIWidth;
    self.emptyUIMessage.textAlignment = NSTextAlignmentCenter;
    self.emptyUIMessage.text = [self noScreenshotsTakeAScreenshotMessage];

    [self.emptyUIView addSubview:self.emptyUIMessage];

    // Indicator
    self.emptyUISyncingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.emptyUISyncingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyUISyncingIndicator.hidesWhenStopped = YES;

    [self.emptyUIView addSubview:self.emptyUISyncingIndicator];

    // Delete Tag Button
    self.emptyUIDeleteTagButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.emptyUIDeleteTagButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.emptyUIDeleteTagButton setTitle:NSLocalizedStringWithDefaultValue(@"screenshotList.removeFolderButton",
                                                                            nil,
                                                                            [NSBundle mainBundle],
                                                                            @"Remove Folder",
                                                                            @"Toolbar button title for removing the folder")
                                 forState:UIControlStateNormal];

    [self.emptyUIDeleteTagButton setTitleColor:[UIColor colorWithRed:0.8 green:0.0 blue:0.0 alpha:1.0] forState:UIControlStateNormal];
    [self.emptyUIDeleteTagButton setTitleColor:[UIColor colorWithRed:0.5 green:0.0 blue:0.0 alpha:1.0] forState:UIControlStateHighlighted];
    self.emptyUIDeleteTagButton.backgroundColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.05];
    self.emptyUIDeleteTagButton.layer.cornerRadius = 5.0;
    [self.emptyUIDeleteTagButton addTarget:self action:@selector(onDeleteTagButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    [self.emptyUIView addSubview:self.emptyUIDeleteTagButton];

    // Finally, add emptyUIView to our view hierarchy
    [self.view insertSubview:self.emptyUIView aboveSubview:self.collectionView];

    // Now add all the constraints
    // (emptyUIWidth)
    self.emptyUIWidthConstraint = [NSLayoutConstraint constraintWithItem:self.emptyUIView
                                                               attribute:NSLayoutAttributeWidth
                                                               relatedBy:NSLayoutRelationEqual
                                                                  toItem:nil
                                                               attribute:NSLayoutAttributeNotAnAttribute
                                                              multiplier:1.0 constant:emptyUIWidth];
    [self.emptyUIView addConstraint:self.emptyUIWidthConstraint];
    // Center emptyUIView in parent
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.emptyUIView
                                                          attribute:NSLayoutAttributeCenterX
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeCenterX
                                                         multiplier:1.0
                                                           constant:0.0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.emptyUIView
                                                          attribute:NSLayoutAttributeCenterY
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeCenterY
                                                         multiplier:1.0
                                                           constant:0.0]];

    // Center title in x
    [self.emptyUIView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"|-0-[_emptyUITitle]-0-|"
                                                                             options:0
                                                                             metrics:nil
                                                                               views:NSDictionaryOfVariableBindings(_emptyUITitle)]];
    // Center message in x
    [self.emptyUIView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"|-0-[_emptyUIMessage]-0-|"
                                                                             options:0
                                                                             metrics:nil
                                                                               views:NSDictionaryOfVariableBindings(_emptyUIMessage)]];
    // Center activity indicator in x
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.emptyUISyncingIndicator
                                                          attribute:NSLayoutAttributeCenterX
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.emptyUIView
                                                          attribute:NSLayoutAttributeCenterX
                                                         multiplier:1.0
                                                           constant:0.0]];
    // Center delete button in x
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.emptyUIDeleteTagButton
                                                          attribute:NSLayoutAttributeCenterX
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.emptyUIView
                                                          attribute:NSLayoutAttributeCenterX
                                                         multiplier:1.0
                                                           constant:0.0]];
    // Provide width and height to delete tag button
    [self.emptyUIDeleteTagButton addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"[_emptyUIDeleteTagButton(==200)]"
                                                                                        options:0
                                                                                        metrics:nil
                                                                                          views:NSDictionaryOfVariableBindings(_emptyUIDeleteTagButton)]];
    [self.emptyUIDeleteTagButton addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[_emptyUIDeleteTagButton(==50)]"
                                                                                        options:0
                                                                                        metrics:nil
                                                                                          views:NSDictionaryOfVariableBindings(_emptyUIDeleteTagButton)]];

    // Stack all the elements vertically (at a lower priority, which we will override later with more specific instructions)
    NSString *allStackFormat = @"V:|"
                                "-NO_SPACE@700-[_emptyUITitle]"
                                "-SINGLE_VSPACE@700-[_emptyUIMessage]"
                                "-DOUBLE_VSPACE@700-[_emptyUISyncingIndicator]"
                                "-DOUBLE_VSPACE@700-[_emptyUIDeleteTagButton]"
                                "-NO_SPACE@700-|";
    NSArray *lowerPriorityConstraints =
    [NSLayoutConstraint constraintsWithVisualFormat:allStackFormat
                                            options:0
                                            metrics:@{@"NO_SPACE" : @(.0), @"SINGLE_VSPACE" : @(8.0), @"DOUBLE_VSPACE" : @(16.0)}
                                              views:NSDictionaryOfVariableBindings(_emptyUITitle,
                                                                                   _emptyUIMessage,
                                                                                   _emptyUISyncingIndicator,
                                                                                   _emptyUIDeleteTagButton)];
    [self.emptyUIView addConstraints:lowerPriorityConstraints];

}


- (NSString *)noScreenshotsFoundEmptyTitle
{
    return NSLocalizedStringWithDefaultValue(@"screenshotList.empty.title",
                                             nil,
                                             [NSBundle mainBundle],
                                             @"No screenshots found.",
                                             @"Short title saying 'no screenshots found'");
}

- (NSString *)noScreenshotsTakeAScreenshotMessage
{
    return NSLocalizedStringWithDefaultValue(@"screenshotList.empty.message",
                                             nil,
                                             [NSBundle mainBundle],
                                             @"Take a screenshot by pressing the Power button and the Home button at the same time.",
                                             @"Small message explaining how to take a screenshot with the iDevice");
}


- (NSString *)noScreenshotsFoundInFolderMessageForName:(NSString *)name
{
    NSString *format =  NSLocalizedStringWithDefaultValue(@"screenshotList.empty.message.noScreenshotsInFolder",
                                                          nil,
                                                          [NSBundle mainBundle],
                                                          @"No screenshots found in the folder '%@'",
                                                          @"Message explaining no screenshots found in the named folder");
    return [NSString stringWithFormat:format, name];
}


- (void)updateEmptyUI
{
    BOOL shouldShowEmptyUI = (self.screenshots.count == 0 && self.screenshotFiles.count == 0);
    if (shouldShowEmptyUI && !self.emptyUIView) {
        [self buildEmptyUI];
    }

    self.collectionView.hidden = shouldShowEmptyUI;
    self.emptyUIView.hidden = !shouldShowEmptyUI;

    if (shouldShowEmptyUI) {
        self.navigationItem.rightBarButtonItem = nil;
    } else {
        if (self.collectionView.allowsSelection) {
            self.navigationItem.rightBarButtonItem = self.shareSelectionBarButtonItem;
        } else {
            self.navigationItem.rightBarButtonItem = self.selectBarButtonItem;
        }
    }
    if (shouldShowEmptyUI && !self.collectionView.allowsSelection) {
        self.navigationItem.rightBarButtonItem = nil;
    } else if (!shouldShowEmptyUI) {

    }

    // Configure empty UI
    if (self.emptyUIView) {
        BOOL showSpinner = NO;
        if ([ScreenshotCatalog sharedCatalog].syncingDatabase) {
            // We're syncing the database, show a spinner
            self.emptyUITitle.text = NSLocalizedStringWithDefaultValue(@"screenshotList.empty.title.collecting",
                                                                       nil,
                                                                       [NSBundle mainBundle],
                                                                       @"Collecting Screenshots...",
                                                                       @"Title on centered empty UI shown while we are collecting screenshots");
            self.emptyUITitle.hidden = NO;
            self.emptyUIMessage.hidden = YES;
            showSpinner = YES;
            self.emptyUIDeleteTagButton.hidden = YES;
        } else if (self.folder != nil) {
            // we have no screenshots in this folder
            // Show message + delete folder button
            self.emptyUITitle.text = [self noScreenshotsFoundEmptyTitle];
            self.emptyUITitle.hidden = NO;
            self.emptyUIMessage.text = [self noScreenshotsFoundInFolderMessageForName:self.folder.folderName];
            self.emptyUIMessage.hidden = NO;
            showSpinner = NO;
            self.emptyUIDeleteTagButton.hidden = NO;
        } else if (self.tagToFilter != nil) {
            // we have no screenshots, but we have a tag
            if (self.tagToFilter == [ScreenshotCatalog sharedCatalog].trashTag) {
                // Show message, but no delete button
                self.emptyUITitle.text = NSLocalizedStringWithDefaultValue(@"screenshotList.empty.title.noFiled",
                                                                           nil,
                                                                           [NSBundle mainBundle],
                                                                           @"No Filed Screenshots.",
                                                                           @"Short title saying 'no filed screenshots'");

                self.emptyUIMessage.text = NSLocalizedStringWithDefaultValue(@"screenshotList.empty.message.noFiled",
                                                                             nil,
                                                                             [NSBundle mainBundle],
                                                                             @"Screenshots you have already filed in folders will also appear here.\n\nDeleting them from here will remove them from your Camera Roll.",
                                                                             @"Short title explaining the 'trash' folder, that filed screenshots will appear here, and deleting screenshots from here will permanently delete");;
                self.emptyUIDeleteTagButton.hidden = YES;
            } else {
                // Show message + delete tag button
                self.emptyUITitle.text = [self noScreenshotsFoundEmptyTitle];
                self.emptyUIMessage.text = [self noScreenshotsFoundInFolderMessageForName:self.tagToFilter.name];
                self.emptyUIDeleteTagButton.hidden = NO;
            }
            self.emptyUITitle.hidden = NO;
            self.emptyUIMessage.hidden = NO;
            showSpinner = NO;
        } else {
            NSUInteger totalScreenshots = [ScreenshotCatalog sharedCatalog].countOfAllScreenshots;
            if (!self.showAllScreenshots && totalScreenshots > 0) {
                // We are 'Unfiled' but no screenshots here, though we have screenshots elsewhere
                self.emptyUITitle.text = NSLocalizedStringWithDefaultValue(@"screenshotList.empty.title.allFiled",
                                                                           nil,
                                                                           [NSBundle mainBundle],
                                                                           @"All Screenshots Filed. Nice!",
                                                                           @"Short title saying that all screenshots are filed");;
                self.emptyUIMessage.text = [self noScreenshotsTakeAScreenshotMessage];
            } else {
                // Generic message with instructions on how
                // to take a screenshot
                self.emptyUITitle.text = [self noScreenshotsFoundEmptyTitle];
                self.emptyUIMessage.text = [self noScreenshotsTakeAScreenshotMessage];
            }
            self.emptyUITitle.hidden = NO;
            self.emptyUIMessage.hidden = NO;
            showSpinner = NO;
            self.emptyUIDeleteTagButton.hidden = YES;
        }
        if (showSpinner) {
            [self.emptyUISyncingIndicator startAnimating];
        } else {
            [self.emptyUISyncingIndicator stopAnimating];
        }
        [self updateEmptyUIStackingConstrainsBasedOnVisibility];
    }
}


- (void)updateEmptyUIStackingConstrainsBasedOnVisibility
{
    if (!self.emptyUIView) {
        return; // we haven't built the empty UI yet
    }
    NSMutableString *visualFormat = [NSMutableString stringWithString:@"V:|"];
    NSString *noSpacing = @"-0@800-";
    NSString *spacingAbove = noSpacing;
    BOOL firstElementAdded = NO;

    if (!self.emptyUITitle.hidden) {
        [visualFormat appendFormat:@"%@[_emptyUITitle]", spacingAbove];
        firstElementAdded = YES;
    }

    if (!self.emptyUIMessage.hidden) {
        spacingAbove = firstElementAdded ? @"-SINGLE_VSPACE@800-" : noSpacing;
        [visualFormat appendFormat:@"%@[_emptyUIMessage]", spacingAbove];
        firstElementAdded = YES;
    }

    if (!self.emptyUISyncingIndicator.hidden) {
        spacingAbove = firstElementAdded ? @"-DOUBLE_VSPACE@800-" : noSpacing;
        [visualFormat appendFormat:@"%@[_emptyUISyncingIndicator]", spacingAbove];
        firstElementAdded = YES;
    }

    if (!self.emptyUIDeleteTagButton.hidden) {
        spacingAbove = firstElementAdded ? @"-DOUBLE_VSPACE@800-" : noSpacing;
        [visualFormat appendFormat:@"%@[_emptyUIDeleteTagButton]", spacingAbove];
        firstElementAdded = YES;
    }

    [visualFormat appendString:@"-0-|"];

    if (!firstElementAdded) {
        // Not a single element is visible, just return, no more constraints to add
        return;
    }

    if ([self.lastUsedStackingVisualFormat isEqualToString:visualFormat]) {
        // same as before, abort!
        return;
    }

    // Remove the existing stacking overrides (if any)
    if (self.emptyUIVerticallyStackingContraints.count > 0) {
        [self.emptyUIView removeConstraints:self.emptyUIVerticallyStackingContraints];
    }

    //NSLog(@"Setting vertically stacking constraints: %@", visualFormat);

    self.emptyUIVerticallyStackingContraints = [NSLayoutConstraint constraintsWithVisualFormat:visualFormat
                                                                                       options:0
                                                                                       metrics:@{@"NO_SPACE" : @(0.0), @"SINGLE_VSPACE" : @(8.0), @"DOUBLE_VSPACE" : @(16.0)}
                                                                                         views:NSDictionaryOfVariableBindings(_emptyUITitle,
                                                                                                                              _emptyUIMessage,
                                                                                                                              _emptyUISyncingIndicator,
                                                                                                                              _emptyUIDeleteTagButton)];
    [self.emptyUIView addConstraints:self.emptyUIVerticallyStackingContraints];
    [self.view setNeedsUpdateConstraints];
    self.lastUsedStackingVisualFormat = visualFormat;

}


#pragma mark - Transitions


- (CGRect)rectForScreenshot:(Screenshot *)screenshot inView:(UIView*)view
{
    if ([self.screenshots containsObject:screenshot]) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:[self.screenshots indexOfObject:screenshot] inSection:0];
        UICollectionViewLayoutAttributes *attributes = [self.collectionView.collectionViewLayout layoutAttributesForItemAtIndexPath:indexPath];
        CGRect rect = attributes.frame;
        rect = [self.collectionView convertRect:rect toView:view];
        return rect;
    }

    return CGRectNull;
}


- (CGRect)rectForScreenshotFile:(ScreenshotFileInfo *)screenshotFile inView:(UIView *)view
{
    if ([self.screenshotFiles containsObject:screenshotFile]) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:[self.screenshotFiles indexOfObject:screenshotFile] inSection:0];
        UICollectionViewLayoutAttributes *attributes = [self.collectionView.collectionViewLayout layoutAttributesForItemAtIndexPath:indexPath];
        CGRect rect = attributes.frame;
        rect = [self.collectionView convertRect:rect toView:view];
        return rect;
    }

    return CGRectNull;
}


- (void)setVisibilityOfScreenshot:(Screenshot *)screenshot toVisible:(BOOL)visible
{
    if ([self.screenshots containsObject:screenshot]) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:[self.screenshots indexOfObject:screenshot] inSection:0];
        [self setVisibilityOfIndexPath:indexPath toVisible:visible];
    }
}


- (void)setVisibilityOfScreenshotFile:(ScreenshotFileInfo *)screenshotFile toVisible:(BOOL)visible
{
    if ([self.screenshotFiles containsObject:screenshotFile]) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:[self.screenshotFiles indexOfObject:screenshotFile] inSection:0];
        [self setVisibilityOfIndexPath:indexPath toVisible:visible];
    }
}


- (void)setVisibilityOfIndexPath:(NSIndexPath *)indexPath toVisible:(BOOL)visible
{
    if (!indexPath) {
        return;
    }
    UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:indexPath];
    cell.contentView.hidden = !visible;
}


#pragma mark - Info Banners


- (void) showBannerMessage:(NSString *)bannerMessage
{
    if (!self.bannerView) {
        self.bannerView = [[CLBannerView alloc] initWithFrame:self.view.bounds];
    }
    self.bannerView.label.text = bannerMessage;

    // Prepare to animate in from the top
    CGFloat startingOffset = 0.0;
    BOOL animateAlpha = YES;
    if (self.navigationController) {
        startingOffset = self.collectionView.contentInset.top;
        animateAlpha = NO; // we want to show the error through the translucency a bit more :-D
    }
    [self.view addSubview:self.bannerView];
    __block CGRect errorFrame = self.bannerView.frame;
    errorFrame.origin.x = 0;
    errorFrame.origin.y = -errorFrame.size.height;
    errorFrame.size.width = self.view.bounds.size.width;
    self.bannerView.frame = errorFrame;
    if (animateAlpha) {
        self.bannerView.alpha = 0.0;
    }

    [UIView animateWithDuration:BANNER_ANIMATE_DURATION animations:^{
        errorFrame.origin.y = startingOffset;
        self.bannerView.frame = errorFrame;
        if (animateAlpha) {
            self.bannerView.alpha = 1.0;
        }
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:BANNER_ANIMATE_DURATION delay:BANNER_DISPLAY_DURATION options:0 animations:^{
            errorFrame.origin.y = -errorFrame.size.height;
            self.bannerView.frame = errorFrame;
            if (animateAlpha) {
                self.bannerView.alpha = 0.0;
            }
        } completion:^(BOOL finished) {
            [self.bannerView removeFromSuperview];
        }];
    }];
}


#pragma mark - UIAlertViewDelegate


- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (alertView == self.firstTimeScreenshotTrashingAlertView) {
        if (buttonIndex == 0) {
            // "Got it!"
            // Actually "trash" it
            NSArray *items = nil;
            if (self.folder) {
                items = [self selectedScreenshotFiles];
            } else {
                items =  [self selectedScreenshots];
            }
            [self askUserToConfirmTrashingItems:items fromSender:self.toolbarTrashItem];
        }

        self.firstTimeScreenshotTrashingAlertView = nil;
    }
}


#pragma mark - UIActionSheetDelegate


- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (actionSheet == self.screenshotUntaggingActionSheet) {
        if (buttonIndex != actionSheet.cancelButtonIndex) {
            [self reallyUntagSelectedScreenshotsAnimated:YES];
        }
        self.screenshotUntaggingActionSheet = nil;
    }
}


#pragma mark - Custom Transition for QuickLook


- (id <UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source
{
    UIViewController *actuallyPresented = presented;
    if ([presented isKindOfClass:[UINavigationController class]]) {
        UIViewController *topViewController = ((UINavigationController *)presented).topViewController;
        if ([topViewController isKindOfClass:[GenericSlideshowViewController class]]) {
            actuallyPresented = topViewController;
        }
    }
    if ([actuallyPresented isKindOfClass:[CLQuickLookViewController class]] ||
        [actuallyPresented isKindOfClass:[GenericSlideshowViewController class]]) {
        return self.transitionManager;
    }
    return nil;
}

- (id <UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed
{
    UIViewController *actuallyDismissed = dismissed;
    if ([dismissed isKindOfClass:[UINavigationController class]]) {
        UIViewController *topViewController = ((UINavigationController *)dismissed).topViewController;
        if ([topViewController isKindOfClass:[GenericSlideshowViewController class]]) {
            actuallyDismissed = topViewController;
        }
    }
    if ([actuallyDismissed isKindOfClass:[CLQuickLookViewController class]] ||
        [actuallyDismissed isKindOfClass:[GenericSlideshowViewController class]]) {
        return self.transitionManager;
    }
    return nil;
}
@end
