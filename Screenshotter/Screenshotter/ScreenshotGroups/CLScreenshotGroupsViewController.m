//
//  CLScreenshotGroupsViewController.m
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

#import "CLScreenshotGroupsViewController.h"

#import "CLAppDelegate.h"
#import "CLScreenshotListViewController.h"
#import "CLScreenshotTagCell.h"
#import "CLScreenshotterApplication.h"
#import <MBProgressHUD/MBProgressHUD.h>
#import <MessageUI/MessageUI.h>
#import "ScreenshotCatalog.h"
#import "SimpleWebViewController.h"
#import "Tag.h"
#import "TagType.h"

static BOOL const DEBUG_ALWAYS_SHOW_STORAGE_CONTAINER_SWITCH = NO;
static BOOL const SHOW_TRASH_TAG_AT_BOTTOM = NO;

@interface CLScreenshotGroupsViewController () <CLScreenshotListViewControllerDelegate, SimpleWebViewControllerDelegate, MFMailComposeViewControllerDelegate, UINavigationControllerDelegate, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UISplitViewControllerDelegate>

@property (strong, nonatomic) UITableView *tableView;
@property (assign, nonatomic) BOOL beingShown;

@property (strong, nonatomic) NSMutableArray *sectionIds;
@property (strong, nonatomic) NSMutableDictionary *rowsBySectionId;
@property (strong, nonatomic) NSMutableArray *metaRows;
@property (strong, nonatomic) NSMutableArray *tags; // Actual tags (also used as rows in rowsBySectionId)
@property (strong, nonatomic) NSMutableArray *folders; // Actual ScreenshotFolder instances

@property (assign, nonatomic) BOOL canClearSelectionAutomatically;

@property (strong, nonatomic) UIBarButtonItem *helpBarButton;

@property (strong, nonatomic) UIButton *byClusterButton;

@property (strong, nonatomic) UIBarButtonItem *editBarButton;
@property (strong, nonatomic) UIBarButtonItem *doneEditingBarButton;

@property (strong, nonatomic) UITextField *renamingTextField;
@property (strong, nonatomic) Tag *tagBeingEdited;
@property (strong, nonatomic) ScreenshotFolder *folderBeingEdited;
@property (weak, nonatomic) CLScreenshotTagCell *cellBeingRenamed;
@property (strong, nonatomic) UIBarButtonItem *cancelRenamingBarButton;
@property (strong, nonatomic) UIBarButtonItem *commitRenamingBarButton;

@property (strong, nonatomic) NSNumberFormatter *prettyNumberFormatter;

@property (strong, nonatomic) UISwitch *storageContainerSwitch;

@end

@implementation CLScreenshotGroupsViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
        self.sectionIds = [@[@"meta"] mutableCopy];
        self.rowsBySectionId = [NSMutableDictionary dictionaryWithCapacity:2];
        self.metaRows = [@[@"unfiled"] mutableCopy];
        self.rowsBySectionId[@"meta"] = self.metaRows;
        self.tags = [NSMutableArray arrayWithCapacity:10];
        self.rowsBySectionId[@"tags"] = self.tags;
        self.folders = [NSMutableArray arrayWithCapacity:10];
        self.rowsBySectionId[@"folders"] = self.folders;
        self.prettyNumberFormatter = [[NSNumberFormatter alloc] init];
        self.prettyNumberFormatter.numberStyle = NSNumberFormatterDecimalStyle;
        // Listen to this forever and ever
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onCatalogUpdated:)
                                                     name:NSManagedObjectContextDidSaveNotification
                                                   object:[ScreenshotCatalog sharedCatalog].managedObjectContext];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onDocumentsUpdated:)
                                                     name:[ScreenshotStorage sharedInstance].DOCUMENTS_WERE_UPDATED_NOTIFICATION
                                                   object:nil];

        UIBarButtonItem *useiCloudLabelItem = [[UIBarButtonItem alloc] initWithTitle:@"Sync with iCloud" style:UIBarButtonItemStylePlain target:nil action:nil];
        self.storageContainerSwitch = [[UISwitch alloc] init];
        self.storageContainerSwitch.on = [ScreenshotStorage sharedInstance].iCloudEnabled;
        [self.storageContainerSwitch addTarget:self action:@selector(onStorageContainerSwitchValueChanged:) forControlEvents:UIControlEventValueChanged];
        UIBarButtonItem *containerSwitchItem = [[UIBarButtonItem alloc] initWithCustomView:self.storageContainerSwitch];
        self.toolbarItems = @[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
                              useiCloudLabelItem,
                              containerSwitchItem,
                              [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil]];
    }
    return self;
}


- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSManagedObjectContextDidSaveNotification
                                                  object:[ScreenshotCatalog sharedCatalog].managedObjectContext];
}

- (void)onCatalogUpdated:(NSNotification *)notification
{
    if (self.beingShown) {
        [self reloadTags];
        [self updateSections];
    }
}

- (void)onDocumentsUpdated:(NSNotification *)notification
{
    if (self.tableView.editing) {
        CLLog(@"Documents were updated while editing, ignoring");
        return;
    }

    [self updateFolders];
    [self updateSections];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.allowsSelectionDuringEditing = YES;
    [self.view addSubview:self.tableView];
    
    self.title = NSLocalizedStringWithDefaultValue(@"screenshotGroups.title",
                                                   nil,
                                                   [NSBundle mainBundle],
                                                   @"Folders",
                                                   @"Tile of screenshot groups screen, typically 'Folders' in English");
    self.helpBarButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"icon_question"]
                                            landscapeImagePhone:nil
                                                          style:UIBarButtonItemStylePlain
                                                         target:self
                                                         action:@selector(onHelpBarButtonTapped:)];
    self.editBarButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit
                                                                       target:self
                                                                       action:@selector(onEditBarButtonTapped:)];
    self.doneEditingBarButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                              target:self
                                                                              action:@selector(onDoneEditingBarButtonTapped:)];
    NSMutableDictionary *boldTextAttributes = [[self.doneEditingBarButton titleTextAttributesForState:UIControlStateNormal] mutableCopy];
    boldTextAttributes[NSFontAttributeName] = [UIFont fontWithName:@"HelveticaNeue-Light" size:22.0];
    [self.doneEditingBarButton setTitleTextAttributes:boldTextAttributes forState:UIControlStateNormal];
    self.cancelRenamingBarButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                 target:self
                                                                                 action:@selector(onCancelRenamingBarButtonTapped:)];
    self.commitRenamingBarButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                                                 target:self
                                                                                 action:@selector(onCommitRenamingBarButtonTapped:)];
    [self.commitRenamingBarButton setTitleTextAttributes:boldTextAttributes forState:UIControlStateNormal];
    self.navigationItem.leftBarButtonItem = self.helpBarButton;
    self.navigationItem.rightBarButtonItem = self.editBarButton;

    [self.tableView registerClass:[CLScreenshotTagCell class] forCellReuseIdentifier:@"GroupCell"];


    self.renamingTextField = [[UITextField alloc] initWithFrame:CGRectMake(10.0, 20, 300, 10.0)];
    self.renamingTextField.delegate = self;
    self.renamingTextField.placeholder = @"Set Name...";
    self.renamingTextField.font = [UIFont systemFontOfSize:28.0];
    self.renamingTextField.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.renamingTextField.returnKeyType = UIReturnKeyDone;
    self.renamingTextField.enablesReturnKeyAutomatically = YES;
    self.renamingTextField.autocorrectionType = UITextAutocorrectionTypeNo;


    UIView *footerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320.0, 88.0)];
    self.byClusterButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.byClusterButton setImage:[UIImage imageNamed:@"by_cluster"] forState:UIControlStateNormal];
    [self.byClusterButton addTarget:self action:@selector(onByClusterButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    CGFloat buttonHeight = 33.0;
    CGFloat paddingBottom = 20.0;
    self.byClusterButton.frame = CGRectMake(0, CGRectGetHeight(footerView.frame)-buttonHeight-paddingBottom, 320.0, buttonHeight);
    self.byClusterButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;

    [footerView addSubview:self.byClusterButton];

    self.tableView.tableFooterView = footerView;

    UIEdgeInsets inset = self.tableView.contentInset;
    inset.bottom = 16.0;
    self.tableView.contentInset = inset;

    if (self.splitViewController) {
        self.splitViewController.delegate = self;
    }
    if (self.navigationController) {
        self.navigationController.delegate = self;
    }
}


- (NSIndexPath *)indexPathMatchingCurrentDetailViewController
{
    if ([self.currentDetailViewController isKindOfClass:[CLScreenshotListViewController class]]) {
        CLScreenshotListViewController *listViewController = (CLScreenshotListViewController *)self.currentDetailViewController;

        NSInteger section = NSNotFound;
        NSInteger row = NSNotFound;
        if (listViewController.folderName) {
            section = [self.sectionIds indexOfObject:@"folders"];
            for (ScreenshotFolder *folder in self.folders) {
                if ([folder.folderName isEqualToString:listViewController.folderName]) {
                    row = [self.folders indexOfObject:folder];
                    break;
                }
            }
        } else if (listViewController.tagToFilter) {
            Tag *tag = listViewController.tagToFilter;
            if (tag == [ScreenshotCatalog sharedCatalog].trashTag) {
                // Special trash tag, in meta section
                section = [self.sectionIds indexOfObject:@"meta"];
                row = [self.metaRows indexOfObject:@"alreadyFiled"];
            } else {
                // Normal tag, look in self.tags
                section = [self.sectionIds indexOfObject:@"tags"];
                row = [self.tags indexOfObject:listViewController.tagToFilter];
            }
        } else {
            // Must be in meta section
            section = [self.sectionIds indexOfObject:@"meta"];
            if (listViewController.showAllScreenshots) {
                row = [self.metaRows indexOfObject:@"all"];
            } else {
                row = [self.metaRows indexOfObject:@"unfiled"];
            }
        }

        if (section != NSNotFound && row != NSNotFound) {
            return [NSIndexPath indexPathForRow:row inSection:section];
        }
    }
    return nil;
}


- (void)selectRowMatchingDetailViewControllerAnimated:(BOOL)animated
{
    NSIndexPath *indexPathToSelect = [self indexPathMatchingCurrentDetailViewController];
    if (indexPathToSelect) {
        [self.tableView selectRowAtIndexPath:indexPathToSelect
                                    animated:animated
                              scrollPosition:UITableViewScrollPositionNone];
    }
}


- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    self.beingShown = YES;

    // Refresh the tags
    [self updateToolbarVisibilityAnimated:NO];
    [self reloadTags];
    [self updateFolders];
    [self updateSections];
    [self startListeningForKeyboardAppearances];

    [self selectRowMatchingDetailViewControllerAnimated:NO];
}


- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    CLLog(@"%@ did appear", NSStringFromClass([self class]));
    [[Analytics sharedInstance] registerScreen:@"Groups"];
}


- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    self.beingShown = NO;
    [self stopListeningForKeyboardAppearances];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (void)updateToolbarVisibilityAnimated:(BOOL)animated
{
    self.storageContainerSwitch.on = [ScreenshotStorage sharedInstance].iCloudEnabled;

    BOOL shouldBeShown = (DEBUG_ALWAYS_SHOW_STORAGE_CONTAINER_SWITCH || ![ScreenshotStorage sharedInstance].iCloudEnabled);
    [self.navigationController setToolbarHidden:!shouldBeShown animated:animated];
}


#pragma mark - UITableViewDataSource


- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return self.sectionIds.count;
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSString *sectionId = self.sectionIds[section];
    NSArray *rows = self.rowsBySectionId[sectionId];
    return rows.count;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CLScreenshotTagCell *cell = [tableView dequeueReusableCellWithIdentifier:@"GroupCell"];

    NSString *sectionId = self.sectionIds[indexPath.section];
    NSArray *rows = self.rowsBySectionId[sectionId];
    cell.textLabel.textColor = [UIColor blackColor];
    if ([sectionId isEqualToString:@"meta"]) {
        // Items under "meta" are string-based rows, that are just special ids
        NSString *rowId = rows[indexPath.row];
        if ([rowId isEqualToString:@"all"]) {
            cell.textLabel.text = NSLocalizedStringWithDefaultValue(@"screenshotGroups.all",
                                                                    nil,
                                                                    [NSBundle mainBundle],
                                                                    @"All",
                                                                    @"Row for choosing all screenshots. Typically 'All' in English");
            cell.detailTextLabel.text = [self.prettyNumberFormatter stringFromNumber:@([ScreenshotCatalog sharedCatalog].countOfAllScreenshots)];
        } else if ([rowId isEqualToString:@"unfiled"]) {
            cell.textLabel.text = NSLocalizedStringWithDefaultValue(@"screenshotGroups.unfiled",
                                                                    nil,
                                                                    [NSBundle mainBundle],
                                                                    @"Screenshots",
                                                                    @"Row for choosing all unfiled screenshots. Typically 'Screenshots' in English");
            cell.detailTextLabel.text = [self.prettyNumberFormatter stringFromNumber:@([ScreenshotCatalog sharedCatalog].countOfAllUnfiledScreenshots)];
        } else if ([rowId isEqualToString:@"alreadyFiled"]) {
            cell.textLabel.text = NSLocalizedStringWithDefaultValue(@"screenshotGroups.alreadyFiled",
                                                                    nil,
                                                                    [NSBundle mainBundle],
                                                                    @"Moved to Folders",
                                                                    @"Row for choosing screenshots already filed and moved to folders. Typically 'Moved to Folders' in English");
            Tag *trashTag = [ScreenshotCatalog sharedCatalog].trashTag;
            cell.detailTextLabel.text = [self.prettyNumberFormatter stringFromNumber:@(trashTag.screenshots.count)];
            cell.folderCellStyle = CLScreenshotFolderCellStyleCompact;
        } else {
            cell.textLabel.text = [NSString stringWithFormat:@"Unknown rowId: %@", rowId];
        }
    } else if ([sectionId isEqualToString:@"folders"]) {
        ScreenshotFolder *folder = self.folders[indexPath.row];
        cell.textLabel.text = folder.folderName;
        cell.detailTextLabel.text = [self.prettyNumberFormatter stringFromNumber:@(folder.count)];
    } else if([sectionId isEqualToString:@"tags"] || [sectionId isEqualToString:@"trash"]) {
        // Items under "tags" or "trash" are actual 'Tag' managed objects, so we can use them directly
        Tag *tag = rows[indexPath.row];
        cell.textLabel.text = tag.name;
        cell.textLabel.textColor = [UIColor lightGrayColor];
        cell.detailTextLabel.text = [self.prettyNumberFormatter stringFromNumber:@(tag.screenshots.count)];
    }

    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    return cell;
}


#pragma mark - UITableViewDelegate


- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *sectionId = self.sectionIds[indexPath.section];
    NSArray *rows = self.rowsBySectionId[sectionId];

    if ([sectionId isEqualToString:@"meta"]) {
        NSString *rowId = rows[indexPath.row];
        if ([rowId isEqualToString:@"alreadyFiled"]) {
            return 50.0;
        }
    }

    return 88.0;
}


- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString *sectionId = self.sectionIds[section];
    NSArray *rows = self.rowsBySectionId[sectionId];
    if ([sectionId isEqualToString:@"folders"]) {
        if (rows.count > 0) {
            if ([ScreenshotStorage sharedInstance].iCloudEnabled) {
                if ([ScreenshotStorage sharedInstance].iCloudDrivePossiblyNotAvailable) {
                    return @"iCLOUD DATA FOLDERS";
                } else {
                    return @"iCLOUD DRIVE FOLDERS";
                }
            } else {
                return @"LOCAL FOLDERS";
            }
        }
    }
    if ([sectionId isEqualToString:@"tags"]) {
        if (rows.count > 0) {
            return @"TAGS";
        }
    }
    return nil;
}


- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    NSString *sectionId = self.sectionIds[section];
    NSArray *rows = self.rowsBySectionId[sectionId];
    if ([sectionId isEqualToString:@"meta"]) {
        if ([rows.lastObject isEqualToString:@"alreadyFiled"]) {
            return @"Screenshots that have been moved to folders may be deleted from your Camera Roll.";
        }
    } else if ([sectionId isEqualToString:@"folders"]) {
        if ([ScreenshotStorage sharedInstance].iCloudDrivePossiblyNotAvailable) {
            return @"NOTE: You may not have upgraded to iCloud Drive on this device. In order to sync your filed screenshots, please upgrade to iCloud Drive.\n\nGo to Settings ➞ iCloud ➞ iCloud Drive";
        }
    }
    return nil;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *sectionId = self.sectionIds[indexPath.section];
    NSArray *rows = self.rowsBySectionId[sectionId];

    if (self.tableView.editing) {
        if ([sectionId isEqualToString:@"tags"] || [sectionId isEqualToString:@"folders"]) {
            // Allow editing the tag name
            CLLog(@"Selected cell to rename in section: %@", sectionId);
            [self beginRenamingItemCellAtIndexPath:indexPath];
        }
    } else {
        Tag *tagToFilter = nil;
        ScreenshotFolder *folder = nil;
        BOOL includeAllScreenshots = NO;
        if ([sectionId isEqualToString:@"meta"]) {
            // Items under "meta" are string-based rows, that are just special ids
            NSString *rowId = rows[indexPath.row];
            if ([rowId isEqualToString:@"all"] || [rowId isEqualToString:@"unfiled"]) {
                includeAllScreenshots = [rowId isEqualToString:@"all"];
            } else if ([rowId isEqualToString:@"alreadyFiled"]) {
                tagToFilter = [ScreenshotCatalog sharedCatalog].trashTag;
                includeAllScreenshots = YES;
            }
            CLLog(@"Selected meta rowId: %@", rowId);
        } else if ([sectionId isEqualToString:@"folders"]) {
            folder = [ScreenshotStorage sharedInstance].screenshotFolders[indexPath.row];
            CLLog(@"Selected folder: %@", folder.folderName);
        } else if([sectionId isEqualToString:@"tags"] || [sectionId isEqualToString:@"trash"]) {
            // Items under "tags" are actual 'Tag' managed objects, so we can use them directly
            tagToFilter = rows[indexPath.row];
            CLLog(@"Selected tag: %@", tagToFilter.name);
        } else {
            CLLog(@"Selected unknown sectionId: %@. Returning", sectionId);
            return;
        }
        [self showScreenshotsListFilteringWithFolder:folder orTag:tagToFilter includeAllScreenshots:includeAllScreenshots animated:YES];
    }
}


#pragma mark Editing

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *sectionId = self.sectionIds[indexPath.section];
    if ([sectionId isEqualToString:@"tags"] || [sectionId isEqualToString:@"folders"]) {
        return YES;
    }
    return NO;
}


- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *sectionId = self.sectionIds[indexPath.section];
    NSArray *rows = self.rowsBySectionId[sectionId];

    ScreenshotFolder *folder = nil;
    Tag *tagToDelete = nil;
    NSString *folderName = nil;
    BOOL hasScreenshots = NO;
    if ([sectionId isEqualToString:@"folders"]) {
        folder = self.folders[indexPath.row];
        folderName = folder.folderName;
        hasScreenshots = folder.count;
    } else {
        // Items under "tags" are actual 'Tag' managed objects, so we can use them directly
        tagToDelete = rows[indexPath.row];
        folderName = tagToDelete.name;
        hasScreenshots = tagToDelete.screenshots.count > 0;
    }

    if (hasScreenshots) {
        CLLog(@"Showing delete confirmation for %@", (folder ? @"folder" : @"tag"));
        NSString *title = [NSString stringWithFormat:@"Delete \"%@\"?", folderName];
        NSString *message = nil;
        if (folder != nil) {
            if ([ScreenshotStorage sharedInstance].iCloudEnabled) {
                message = @"It will be removed from iCloud Drive and your other iCloud devices. All files in it will also be deleted.";
            } else {
                // Local
                message = @"Any screenshots in it will also be deleted.";
            }

        } else {
            // Tag
            title = @"Any screenshots in it will become unfiled.";
        }
        __weak CLScreenshotGroupsViewController *_weakSelf = self;
        UIAlertController *confirmDelete = [UIAlertController alertControllerWithTitle:title
                                                                               message:message
                                                                        preferredStyle:UIAlertControllerStyleActionSheet];
        [confirmDelete addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            CLLog(@"Tapped '%@'", action.title);
            [_weakSelf actuallyDeleteFolderOrTagAtIndexPath:indexPath animated:YES];
        }]];
        [confirmDelete addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            CLLog(@"Tapped '%@'", action.title);
        }]];
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        UIView *sourceView = cell;
        CGRect sourceRect = cell.bounds;
        for (UIView *subview in cell.subviews) {
            NSString *className = NSStringFromClass([subview class]);
            if ([className isEqualToString:@"UITableViewCellDeleteConfirmationView"]) {
                sourceView = subview;
                sourceRect = subview.bounds;
            }
        }
        confirmDelete.popoverPresentationController.sourceView = sourceView;
        confirmDelete.popoverPresentationController.sourceRect = sourceRect;
        [self presentViewController:confirmDelete animated:YES completion:nil];
    } else {
        [self actuallyDeleteFolderOrTagAtIndexPath:indexPath animated:YES];
    }


}


#pragma mark - Editing a Tag


- (void)beginRenamingItemCellAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *sectionId = self.sectionIds[indexPath.section];
    NSArray *rows = self.rowsBySectionId[sectionId];
    if ([sectionId isEqualToString:@"folders"]) {
        self.folderBeingEdited = self.folders[indexPath.row];
    } else if ([sectionId isEqualToString:@"tags"]) {
        // Items under "tags" are actual 'Tag' managed objects, so we can use them directly
        self.tagBeingEdited = rows[indexPath.row];
    }

    CLScreenshotTagCell *cell = (CLScreenshotTagCell *)[self.tableView cellForRowAtIndexPath:indexPath];
    self.cellBeingRenamed = cell;
    [self.cellBeingRenamed.contentView addSubview:self.renamingTextField];
    CGRect textLabelFrame = self.cellBeingRenamed.textLabel.frame;
    // Stretch the width of the textfield to the end of contentView (-12.0 for a bit of right margin)
    textLabelFrame.size.width = (CGRectGetMaxX(self.cellBeingRenamed.contentView.bounds) - CGRectGetMinX(textLabelFrame)) - 12.0;
    self.renamingTextField.frame = textLabelFrame;
    self.renamingTextField.font = self.cellBeingRenamed.textLabel.font;

    if (self.tagBeingEdited) {
        self.renamingTextField.text = self.tagBeingEdited.name;
    } else {
        self.renamingTextField.text = self.folderBeingEdited.folderName;
    }
    [self.renamingTextField becomeFirstResponder];

    self.cellBeingRenamed.textLabel.text = @"";
    self.cellBeingRenamed.detailTextLabel.text = @"";

    [self.navigationItem setLeftBarButtonItem:self.cancelRenamingBarButton animated:YES];
    [self.navigationItem setRightBarButtonItem:self.commitRenamingBarButton animated:YES];
}


- (void)endRenamingItem
{
    // Remove the text field
    [self.renamingTextField removeFromSuperview];

    // Restore the textLabel/detailTextLabel of the cell
    if (self.tagBeingEdited) {
        self.cellBeingRenamed.textLabel.text = self.tagBeingEdited.name;
        self.cellBeingRenamed.detailTextLabel.text = [self.prettyNumberFormatter stringFromNumber:@(self.tagBeingEdited.screenshots.count)];
    } else {
        self.cellBeingRenamed.textLabel.text = self.folderBeingEdited.folderName;
        self.cellBeingRenamed.detailTextLabel.text = [self.prettyNumberFormatter stringFromNumber:@(self.folderBeingEdited.count)];
    }

    // Restore the 'Done' button for finishing editing
    [self.navigationItem setLeftBarButtonItem:nil animated:YES];
    [self.navigationItem setRightBarButtonItem:self.doneEditingBarButton animated:YES];
}

- (void)commitRenamingTo:(NSString *)proposedName
{
    NSString *currentName = self.folderBeingEdited.folderName;
    if (self.tagBeingEdited) {
        currentName = self.tagBeingEdited.name;
    }

    if ([currentName isEqualToString:proposedName]) {
        // Same name as before, do nothing
        [self endRenamingItem];
        return;
    }

    __weak CLScreenshotGroupsViewController *_weakSelf = self;

    // Search for existing item with the proposed name
    Tag *alreadyExistingTag = nil;
    ScreenshotFolder *alreadyExistingFolder = nil;
    if (self.tagBeingEdited) {
        // Search all tags to see if there's another tag that has this name
        for (Tag *tag in self.tags) {
            if ([tag.name isEqualToString:proposedName]) {
                alreadyExistingTag = tag;
                break;
            }
        }
    } else {
        // Search all folders
        for (ScreenshotFolder *existingFolder in self.folders) {
            if ([existingFolder.folderName isEqualToString:proposedName]) {
                alreadyExistingFolder = existingFolder;
                break;
            }
        }
    }

    if (alreadyExistingTag || alreadyExistingFolder) {
        // Ask to confirm merging
        NSString *title = nil;
        NSString *nameOfExisting = nil;
        if (alreadyExistingTag) {
            title = @"Tag Already Exists";
            nameOfExisting = alreadyExistingTag.name;
        } else {
            title = @"Folder Already Exists";
            nameOfExisting = alreadyExistingFolder.folderName;
        }
        NSString *message = [NSString stringWithFormat:@"Would you like to merge screenshots in \"%@\" into \"%@\"? This cannot be undone.", currentName, nameOfExisting];
        UIAlertController *mergeConfirm = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [mergeConfirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            [_weakSelf.renamingTextField becomeFirstResponder];
        }]];
        [mergeConfirm addAction:[UIAlertAction actionWithTitle:@"Merge" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            // Go merge
            [_weakSelf endRenamingItem];
            if (_weakSelf.tagBeingEdited) {
                [_weakSelf.tags removeObject:_weakSelf.tagBeingEdited];
                [[ScreenshotCatalog sharedCatalog] mergeTag:_weakSelf.tagBeingEdited
                                                    intoTag:alreadyExistingTag
                                            deleteMergedTag:YES];
                [_weakSelf reloadTableMaintainingSelection];
            } else {
                [[ScreenshotStorage sharedInstance] mergeScreenshotFolder:_weakSelf.folderBeingEdited intoFolder:alreadyExistingFolder completion:^(BOOL success, NSError *error) {
                    [_weakSelf reloadTableMaintainingSelection];
                }];
            }
        }]];
        [self presentViewController:mergeConfirm animated:YES completion:nil];
    } else {
        // Can safely rename, go ahead

        if (self.tagBeingEdited) {
            self.tagBeingEdited.name = proposedName;
            [[ScreenshotCatalog sharedCatalog] saveContext];
            [self endRenamingItem];
        } else {
            [[ScreenshotStorage sharedInstance] renameScreenshotFolder:self.folderBeingEdited toName:proposedName completion:^(BOOL success, NSError *error) {
                [self endRenamingItem];
            }];
        }
    }
}


#pragma mark - Showing a Screenshots List


- (void)showScreenshotsListFilteringWithFolder:(ScreenshotFolder *)folder orTag:(Tag *)tagToFilter includeAllScreenshots:(BOOL)includeAllScreenshots animated:(BOOL)animated
{
    CLScreenshotListViewController *listViewController = [self screenshotsListViewControllerWithFolder:folder
                                                                                                 orTag:tagToFilter
                                                                                 includeAllScreenshots:includeAllScreenshots];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:listViewController];
    [self showDetailViewController:nav sender:self];
    self.currentDetailViewController = listViewController;
}


- (CLScreenshotListViewController *)screenshotsListViewControllerWithFolder:(ScreenshotFolder *)folder orTag:(Tag *)tagToFilter includeAllScreenshots:(BOOL)includeAllScreenshots
{
    CLScreenshotListViewController *listViewController = [[CLScreenshotListViewController alloc] init];
    listViewController.tagToFilter = tagToFilter;
    listViewController.folderName = folder.folderName;
    listViewController.showAllScreenshots = includeAllScreenshots;
    listViewController.delegate = self;
    return listViewController;
}


- (UIViewController *)defaultDetailViewController
{
    return [self screenshotsListViewControllerWithFolder:nil orTag:nil includeAllScreenshots:NO];
}


#pragma mark - CLScreenshotListViewControllerDelegate


- (void)screenshotListViewControllerDidRequestDismiss:(CLScreenshotListViewController *)controller didDeleteTagOrFolder:(BOOL)didDeleteTagOrFolder animated:(BOOL)animated
{
    if (self.splitViewController.collapsed) {
        [self.navigationController popViewControllerAnimated:YES];
    } else if (didDeleteTagOrFolder) {
        // Select something else, because we are visible and there is nothing to "pop" to
        NSIndexPath *selectedIndexPath = [self indexPathMatchingCurrentDetailViewController];
        if (selectedIndexPath) {
            NSIndexPath *indexPathToSelect = [self indexPathToSelectAssumingDeletionOfIndexPath:selectedIndexPath];
            if (indexPathToSelect) {
                [self.tableView selectRowAtIndexPath:indexPathToSelect
                                            animated:NO
                                      scrollPosition:UITableViewScrollPositionNone];
                [self tableView:self.tableView didSelectRowAtIndexPath:indexPathToSelect];
            }
        }
    }
}


#pragma mark - Deleting a tag


- (NSIndexPath *)indexPathToSelectAssumingDeletionOfIndexPath:(NSIndexPath *)indexPath
{
    NSString *sectionId = self.sectionIds[indexPath.section];
    NSArray *rows = self.rowsBySectionId[sectionId];

    ScreenshotFolder *folder = nil;
    Tag *tagToDelete = nil;
    if ([sectionId isEqualToString:@"folders"]) {
        folder = self.folders[indexPath.row];
    } else {
        // Items under "tags" are actual 'Tag' managed objects, so we can use them directly
        tagToDelete = rows[indexPath.row];
    }

    // Based on the folder or tag, find the next suitable row (default being meta "unfiled")
    NSString *defaultMetaRowIdToSelect = @"unfiled";
    NSInteger sectionToSelect = [self.sectionIds indexOfObject:@"meta"];
    NSInteger indexToSelect = [self.metaRows indexOfObject:defaultMetaRowIdToSelect];
    if (folder) {
        NSInteger index = [self.folders indexOfObject:folder];
        if (index != NSNotFound && self.folders.count > 1) {
            indexToSelect = MIN(index, self.folders.count-2);

            sectionToSelect = [self.sectionIds indexOfObject:@"folders"];
        }
    } else if (tagToDelete) {
        if (tagToDelete != [ScreenshotCatalog sharedCatalog].trashTag) {
            NSInteger index = [self.tags indexOfObject:tagToDelete];
            if (index != NSNotFound && self.tags.count > 1) {
                indexToSelect = MIN(index, self.tags.count-2);
                sectionToSelect = [self.sectionIds indexOfObject:@"tags"];
            }
        }
    }

    NSIndexPath *indexPathToSelectAfter = [NSIndexPath indexPathForRow:indexToSelect inSection:sectionToSelect];
    return indexPathToSelectAfter;
}


- (void)actuallyDeleteFolderOrTagAtIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated
{
    NSString *sectionId = self.sectionIds[indexPath.section];
    NSArray *rows = self.rowsBySectionId[sectionId];

    ScreenshotFolder *folder = nil;
    Tag *tagToDelete = nil;
    NSString *folderName = nil;
    if ([sectionId isEqualToString:@"folders"]) {
        folder = self.folders[indexPath.row];
        folderName = folder.folderName;
    } else {
        // Items under "tags" are actual 'Tag' managed objects, so we can use them directly
        tagToDelete = rows[indexPath.row];
        folderName = tagToDelete.name;
    }

    // Figure out if can/should select the item after, or before, or the main screenshots cell
    NSIndexPath *indexPathToSelectAfter = nil;
    NSIndexPath *selectedIndexPath = [self indexPathMatchingCurrentDetailViewController];
    if (!self.splitViewController.collapsed && [selectedIndexPath isEqual:indexPath]) {
        // We are currently selected here, or we are unknown (but could still be displaying this in detail view)
        indexPathToSelectAfter = [self indexPathToSelectAssumingDeletionOfIndexPath:indexPath];
    }

    // Declare actual deletion as a block
    void (^actuallyDelete)() = ^{
        if (folder) {
            [[ScreenshotStorage sharedInstance] deleteScreenshotFolder:folder completion:^(BOOL success, NSError *error) {
                [[Analytics sharedInstance] track:@"delete_folder"
                                       properties:@{@"folder_name" : folderName}];
            }];
        } else if (tagToDelete) {
            [[ScreenshotCatalog sharedCatalog] deleteTag:tagToDelete];
        }
        if (indexPathToSelectAfter) {
            [self.tableView selectRowAtIndexPath:indexPathToSelectAfter
                                        animated:NO
                                  scrollPosition:UITableViewScrollPositionNone];
            [self tableView:self.tableView didSelectRowAtIndexPath:indexPathToSelectAfter];
        }
    };

    NSInteger numRowsBeforeDelete = [self.tableView numberOfRowsInSection:indexPath.section];

    // Delete from model
    if (folder) {
        [self.folders removeObject:folder];
    } else {
        [self.tags removeObject:tagToDelete];
    }

    // Delete from table
    if (animated) {
        // Determine the kind of delete animation we need
        if (numRowsBeforeDelete == 1) {
            [self.sectionIds removeObject:sectionId];
            // Delete the whole section
            [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:indexPath.section] withRowAnimation:UITableViewRowAnimationAutomatic];
        } else {
            // Can delete one row of multiple
            [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"'%@' was animated as deleted. After table animation, actually deleting...", folderName);
            actuallyDelete();
        });
    } else {
        actuallyDelete();
        [self reloadTableMaintainingSelection];
    }
}

#pragma mark - Loading Screenshot Tags


- (void)reloadTags
{
    NSArray *results = [[ScreenshotCatalog sharedCatalog] retrieveAllTagsIncludeTrash:YES];
    [self.tags removeAllObjects];
    Tag *trashTag = nil;
    for (Tag *tag in results) {
        if (tag.type.intValue == TagTypeTrash) {
            trashTag = tag;
        } else {
            [self.tags addObject:tag];
        }
    }

    [self.tags sortWithOptions:0 usingComparator:^NSComparisonResult(id obj1, id obj2) {
        Tag *tag1 = (Tag *)obj1;
        Tag *tag2 = (Tag *)obj2;
        return [tag1.name compare:tag2.name];
    }];
}

- (void) updateFolders
{
    [self.folders removeAllObjects];
    [self.folders addObjectsFromArray:[ScreenshotStorage sharedInstance].screenshotFolders];
}

- (void) updateSections {

    // Update meta section
    [self.metaRows removeAllObjects];
    [self.metaRows addObject:@"unfiled"];
    Tag *trashTag = [ScreenshotCatalog sharedCatalog].trashTag;
    if (!SHOW_TRASH_TAG_AT_BOTTOM && trashTag) {
        [self.metaRows addObject:@"alreadyFiled"];
    }

    NSInteger indexOfMetaSection = [self.sectionIds indexOfObject:@"meta"];

    BOOL alreadyHasTagsSection = [self.sectionIds containsObject:@"tags"];
    if (self.tags.count > 0 && !alreadyHasTagsSection) {
        [self.sectionIds insertObject:@"tags" atIndex:indexOfMetaSection+1];
    } else if (self.tags.count == 0 && alreadyHasTagsSection) {
        [self.sectionIds removeObject:@"tags"];
    }

    if (SHOW_TRASH_TAG_AT_BOTTOM) {
        BOOL alreadyHasTrashSection = [self.sectionIds containsObject:@"trash"];
        if (trashTag != nil && !alreadyHasTrashSection) {
            [self.sectionIds addObject:@"trash"];
            self.rowsBySectionId[@"trash"] = @[trashTag];
        } else if (trashTag == nil && alreadyHasTrashSection) {
            [self.sectionIds removeObject:@"trash"];
            [self.rowsBySectionId removeObjectForKey:@"trash"];
        }
    }

    // Check for File-based screenshots
    BOOL alreadyHasFoldersSection = [self.sectionIds containsObject:@"folders"];
    if (self.folders.count > 0 && !alreadyHasFoldersSection) {
        [self.sectionIds insertObject:@"folders" atIndex:indexOfMetaSection+1];
    } else if (self.folders.count == 0 && alreadyHasFoldersSection) {
        [self.sectionIds removeObject:@"folders"];
    }

    [self reloadTableMaintainingSelection];
}


- (void)reloadTableMaintainingSelection
{
    NSArray *previouslySelectedIndexPaths = self.tableView.indexPathsForSelectedRows;
    [self.tableView reloadData];

    NSUInteger numSections = self.tableView.numberOfSections;
    for (NSIndexPath *selectedIndexPath in previouslySelectedIndexPaths) {
        if (selectedIndexPath.section < numSections) {
            NSUInteger numRows = [self.tableView numberOfRowsInSection:selectedIndexPath.section];
            if (selectedIndexPath.row < numRows) {
                [self.tableView selectRowAtIndexPath:selectedIndexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
            }
        }
    }
}


#pragma mark - Help


- (void)onHelpBarButtonTapped:(id)sender
{
    CLLog(@"Tapped help bar button");
    //[self showWebPageAtURL:[NSURL URLWithString:@"http://screenshotter.net/faq.html"] title:@"Help" animated:YES];
    UIAlertController *helpActionSheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [helpActionSheet addAction:[UIAlertAction actionWithTitle:@"About Screenshotter" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        CLLog(@"Tapped '%@'", action.title);
        [self showWebPageAtURL:[NSURL URLWithString:@"http://screenshotter.net/about"] title:@"About" animated:YES];
    }]];
    [helpActionSheet addAction:[UIAlertAction actionWithTitle:@"Help" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        CLLog(@"Tapped '%@'", action.title);
        [self showWebPageAtURL:[NSURL URLWithString:@"http://screenshotter.net/faq"] title:@"Help" animated:YES];
    }]];
    [helpActionSheet addAction:[UIAlertAction actionWithTitle:@"Email Us" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        CLLog(@"Tapped '%@'", action.title);
        [self onEmailUsBarButtonTapped:nil];
    }]];
    [helpActionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        CLLog(@"Tapped '%@'", action.title);
    }]];
    [helpActionSheet setModalPresentationStyle:UIModalPresentationPopover];

    UIPopoverPresentationController *popPresenter = [helpActionSheet popoverPresentationController];
    popPresenter.barButtonItem = (UIBarButtonItem *)sender;

    [self presentViewController:helpActionSheet animated:YES completion:nil];
}


- (void)showWebPageAtURL:(NSURL *)url title:(NSString *)title animated:(BOOL)animated
{
    SimpleWebViewController *webView = [[SimpleWebViewController alloc] initWithTitle:title andURL:url];
    webView.delegate = self;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:webView];

    [self presentViewController:nav animated:YES completion:nil];
}


- (void)onEmailUsBarButtonTapped:(id)sender
{
    if (![MFMailComposeViewController canSendMail]) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Whoops!"
                                                        message:@"It doesn't look like you have email configured."
                                                       delegate:nil
                                              cancelButtonTitle:nil
                                              otherButtonTitles:@"Dismiss", nil];
        [alert show];
        return;
    }

    MFMailComposeViewController *compose = [[MFMailComposeViewController alloc] init];
    compose.modalPresentationStyle = UIModalPresentationPageSheet;
    compose.mailComposeDelegate = self;
    [compose setToRecipients:@[@"screenshotter@getcluster.com"]];
    [compose setSubject:@"Screenshotter Feedback"];

    NSMutableString *body = [@"\n\n\nAdditional Info:\n" mutableCopy];
    [body appendFormat:@"\nScreenshotter Version: %@", [CLScreenshotterApplication appVersionAndBuildNumber]];
    [body appendFormat:@"\niCloud Available: %@", [ScreenshotStorage sharedInstance].iCloudAvailable ? @"Yes" : @"No"];
    UsagePermissionState permission = [ScreenshotStorage iCloudUsagePermissionState];
    NSString *permissionString = nil;
    switch (permission) {
        case UsagePermissionStateNotDetermined:
            permissionString = @"Not Determined";
            break;
        case UsagePermissionStateShouldUse:
            permissionString = @"Should Use";
            break;
        case UsagePermissionStateShouldNotUse:
            permissionString = @"Should Not Use";
            break;
        default:
            break;
    }
    [body appendFormat:@"\niCloud Permission: %@", permissionString];
    [body appendFormat:@"\nDevice: %@", [CLScreenshotterApplication hardwareModel]];
    [body appendFormat:@"\niOS Version: %@", [CLScreenshotterApplication softwareVersion]];
    CGSize windowSize = [UIScreen mainScreen].bounds.size;
    [body appendFormat:@"\nScreen: %.0fx%.0f at %.0fx", windowSize.width, windowSize.height, [UIScreen mainScreen].scale];

    [compose setMessageBody:body isHTML:NO];

    if (self.presentedViewController) {
        // Dismiss the web view first,
        [self dismissViewControllerAnimated:YES completion:^{
            // Then show our email compose dialog
            [self presentViewController:compose animated:YES completion:nil];
        }];
    } else {
        [self presentViewController:compose animated:YES completion:nil];
    }


}


- (void)onByClusterButtonTapped:(id)sender
{
    CLLog(@"Tapped 'By Cluster' button in groups list");
    NSURL *clusterAppURL = [NSURL URLWithString:@"https://itunes.apple.com/us/app/cluster-private-spaces-for/id596595032?mt=8"];
    [[UIApplication sharedApplication] openURL:clusterAppURL];
}


- (void)onEditBarButtonTapped:(id)sender
{
    CLLog(@"Tapped 'Edit' in screenshot groups");
    [self.navigationItem setLeftBarButtonItem:nil animated:YES];
    [self.navigationItem setRightBarButtonItem:self.doneEditingBarButton animated:YES];

    [self.tableView setEditing:YES animated:YES];
}


- (void)onDoneEditingBarButtonTapped:(id)sender
{
    CLLog(@"Tapped 'Done' while editing groups");
    [self.navigationItem setLeftBarButtonItem:self.helpBarButton animated:YES];
    [self.navigationItem setRightBarButtonItem:self.editBarButton animated:YES];

    [self.tableView setEditing:NO animated:YES];
}


- (void)onCancelRenamingBarButtonTapped:(id)sender
{
    CLLog(@"Tapped 'Cancel' while renaming");
    [self endRenamingItem];
}


- (void)onCommitRenamingBarButtonTapped:(id)sender
{
    CLLog(@"Tapped 'Save' while renaming");
    NSString *proposedTagName = [self.renamingTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (proposedTagName.length > 0) {
        [self commitRenamingTo:proposedTagName];
    }
}


#pragma mark - Keyboard Notifications


- (void)startListeningForKeyboardAppearances
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [center addObserver:self selector:@selector(keyboardWillChangeFrame:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [center addObserver:self selector:@selector(keyboardDidChangeFrame:) name:UIKeyboardDidChangeFrameNotification object:nil];
}


- (void)stopListeningForKeyboardAppearances
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [center removeObserver:self name:UIKeyboardWillChangeFrameNotification object:nil];
    [center removeObserver:self name:UIKeyboardDidChangeFrameNotification object:nil];
}


- (void)adjustInsetsForKeyboardUserInfo:(NSDictionary *)info animated:(BOOL)animated
{
    CGRect keyboardFrame = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat visibleKeyboardHeight = (CGRectGetHeight([UIScreen mainScreen].bounds)-CGRectGetMinY(keyboardFrame));

    UIEdgeInsets contentInset = self.tableView.contentInset;
    contentInset.bottom = visibleKeyboardHeight;
    self.tableView.contentInset = contentInset;

    // Animate row to be visible (if needed)
    if (self.cellBeingRenamed) {
        NSIndexPath *renamingIndexPath = [self.tableView indexPathForCell:self.cellBeingRenamed];
        if (renamingIndexPath) {
            CGRect cellRect = [self.tableView rectForRowAtIndexPath:renamingIndexPath];
            CGRect cellRectInScreen = [self.tableView convertRect:cellRect
                                                           toView:[UIApplication sharedApplication].keyWindow];
            if (CGRectIntersectsRect(cellRectInScreen, keyboardFrame)) {

                if (animated) {
                    NSTimeInterval duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
                    UIViewAnimationCurve curve = [info[UIKeyboardAnimationCurveUserInfoKey] integerValue];

                    [UIView beginAnimations:@"keyboardAnimationTableViewAdjust" context:nil];
                    [UIView setAnimationCurve:curve];
                    [UIView setAnimationDuration:duration];
                }
                [self.tableView scrollToRowAtIndexPath:renamingIndexPath atScrollPosition:UITableViewScrollPositionBottom animated:NO];
                if (animated) {
                    [UIView commitAnimations];
                }
            }
        }
    }
}


- (void)keyboardWillChangeFrame:(NSNotification *)notification
{
    NSDictionary *info = notification.userInfo;
    [self adjustInsetsForKeyboardUserInfo:info animated:YES];
}


- (void)keyboardDidChangeFrame:(NSNotification *)notification
{
    NSDictionary *info = notification.userInfo;
    [self adjustInsetsForKeyboardUserInfo:info animated:YES];
}


#pragma mark - UITextFieldDelegate


- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
    NSString *proposedText = [textField.text stringByReplacingCharactersInRange:range withString:string];
    proposedText = [proposedText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.commitRenamingBarButton.enabled = (proposedText.length > 0);
    return YES;
}


- (void)textFieldDidEndEditing:(UITextField *)textField
{
    if (self.tableView.editing) {
        [self.navigationItem setLeftBarButtonItem:nil animated:YES];
        [self.navigationItem setRightBarButtonItem:self.doneEditingBarButton animated:YES];
    } else {
        [self.navigationItem setLeftBarButtonItem:self.helpBarButton animated:YES];
        [self.navigationItem setRightBarButtonItem:self.editBarButton animated:YES];
    }
}


- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    CLLog(@"Pressed Enter while renaming");
    NSString *proposedTagName = [textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (proposedTagName.length > 0) {
        [self commitRenamingTo:proposedTagName];
        return YES;
    } else {
        return NO;
    }
}


#pragma mark - SimpleWebViewControllerDelegate

- (void)simpleWebViewControllerDidRequestDismiss:(SimpleWebViewController *)controller
{
    [self dismissViewControllerAnimated:YES completion:nil];
}


#pragma mark - MFMailComposeViewControllerDelegate


// Dismisses the email composition interface when users tap Cancel or Send. Proceeds to update the
// message field with the result of the operation.
- (void)mailComposeController:(MFMailComposeViewController*)controller
          didFinishWithResult:(MFMailComposeResult)result
                        error:(NSError*)error
{
    if (error) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Whoops!"
                                                        message:@"There was an error sending your email."
                                                       delegate:nil
                                              cancelButtonTitle:nil
                                              otherButtonTitles:@"Dismiss", nil];
        [alert show];
    }
	[self dismissViewControllerAnimated:YES completion:nil];
}


#pragma mark - Debug

- (void)onStorageContainerSwitchValueChanged:(id)sender
{
    UISwitch *containerSwitch = (UISwitch *)sender;
    ScreenshotContainerType containerType = (containerSwitch.on ? ScreenshotContainerTypeCloud : ScreenshotContainerTypeLocal);
    [self onUserRequestedToSwitchToContainerType:containerType];
}


- (void)onUserRequestedToSwitchToContainerType:(ScreenshotContainerType)containerType
{
    __weak CLScreenshotGroupsViewController *_weakSelf = self;
    if (containerType == ScreenshotContainerTypeCloud) {
        // Attempt to use iCloud, we should generally just let it happen
        [self switchToScreenshotContainer:containerType withCompletion:^(BOOL success, NSError *error) {
            if (success) {
                [_weakSelf updateToolbarVisibilityAnimated:YES];
            } else if (error.code == 500) { // iCloud Not available
                ScreenshotStorage.iCloudUsagePermissionState = UsagePermissionStateShouldNotUse;
            }
        }];
    } else {
        // Warn the user sternly that they will lose syncing ability and it can cause conflicts in the future if they
        // change their mind.

        NSString * title = @"Stop syncing with iCloud?";
        NSString * message = @"This will move all current screenshots from iCloud into this device only. "
        "They will be removed from iCloud and all of your other devices and "
        "computers which sync to iCloud.\n\n"
        "If you uninstall Screenshotter, your screenshot folders will be deleted.";
        UIAlertController *confirmSwitchChange = [UIAlertController alertControllerWithTitle:title
                                                                                     message:message
                                                                              preferredStyle:UIAlertControllerStyleAlert];
        [confirmSwitchChange addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                                style:UIAlertActionStyleCancel
                                                              handler:^(UIAlertAction *action) {
                                                                  _weakSelf.storageContainerSwitch.on = YES;
                                                              }]];
        [confirmSwitchChange addAction:[UIAlertAction actionWithTitle:@"Continue"
                                                                style:UIAlertActionStyleDestructive
                                                              handler:^(UIAlertAction *action) {
                                                                  [_weakSelf switchToScreenshotContainer:containerType withCompletion:^(BOOL success, NSError *error) {
                                                                      [_weakSelf updateToolbarVisibilityAnimated:YES];
                                                                  }];
                                                              }]];
        
        [self presentViewController:confirmSwitchChange animated:YES completion:nil];
    }
}


#pragma mark - Switching Screenshot containers


- (void)switchToScreenshotContainer:(ScreenshotContainerType)containerType withCompletion:(void (^)(BOOL success, NSError *error))completion
{
    if (containerType == ScreenshotContainerTypeCloud) {
        // Use iCloud
        ScreenshotStorage.iCloudUsagePermissionState = UsagePermissionStateShouldUse;
    } else {
        ScreenshotStorage.iCloudUsagePermissionState = UsagePermissionStateShouldNotUse;
    }

    NSString *destinationName = (containerType == ScreenshotContainerTypeLocal ? @"Local Documents" : @"iCloud");

    MBProgressHUD *progressHUD = nil;
    progressHUD = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    progressHUD.labelText = [NSString stringWithFormat:@"Migrating to %@", destinationName];
    progressHUD.mode = MBProgressHUDModeIndeterminate;
    [[ScreenshotStorage sharedInstance] moveScreenshotsIntoContainer:containerType completion:^(BOOL succeeded, NSError *error) {
        NSLog(@"Moved screenshots into %@ container, succeeded: %d, error: %@", destinationName, succeeded, error);
        [[ScreenshotStorage sharedInstance] updateToCurrentStorageOption];
        progressHUD.mode = MBProgressHUDModeText;
        if (succeeded) {
            progressHUD.labelText = @"Migration Complete.";
        } else {
            progressHUD.labelText = @"Error";
            if (containerType == ScreenshotContainerTypeCloud && error.code == 500) {
                progressHUD.labelText = @"iCloud Not Available";
            }
        }
        [progressHUD hide:YES afterDelay:1.0];
        if (completion) {
            completion(succeeded, error);
        }
    }];
}


#pragma mark - UINavigationControllerDelegate


- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    if (viewController != self) {
        self.canClearSelectionAutomatically = YES;
    }
}


- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    if (viewController == self && self.canClearSelectionAutomatically && self.splitViewController.collapsed) {
        for (NSIndexPath *selectedIndexPath in self.tableView.indexPathsForSelectedRows) {
            [self.tableView deselectRowAtIndexPath:selectedIndexPath animated:animated];
        }
    }
}
@end
