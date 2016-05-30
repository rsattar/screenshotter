//
//  CLTaggingViewController.m
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

#import "CLTaggingViewController.h"

#import "CLScreenshotTagCell.h"
#import "ScreenshotCatalog.h"

static BOOL const MARK_SCREENSHOTS_AS_TRASH_IF_STORED_IN_FOLDER = YES;
static BOOL const TEXTFIELD_CREATES_TAG_NOT_FOLDER = NO;

@interface CLTaggingViewController () <UITextFieldDelegate>

@property (strong, nonatomic) NSMutableArray *sectionIds;
@property (strong, nonatomic) NSMutableDictionary *rowsBySectionId;

@property (strong, nonatomic) NSMutableArray *tags;
@property (strong, nonatomic) UITextField *tagTextField;
@property (strong, nonatomic) UITableViewCell *folderNameCell;

@property (strong, nonatomic) NSMutableArray *folders; // Actual ScreenshotFolder instances

@property (strong, nonatomic) UIBarButtonItem *saveBarButtonItem;

@property (strong, nonatomic) NSNumberFormatter *prettyNumberFormatter;

@end

@implementation CLTaggingViewController

- (void) commonInit
{
    self.sectionIds = [NSMutableArray arrayWithCapacity:2];
    self.rowsBySectionId = [NSMutableDictionary dictionaryWithCapacity:2];
    self.tags = [NSMutableArray arrayWithCapacity:5];
    self.rowsBySectionId[@"new"] = @[@"enterName"];
    self.rowsBySectionId[@"tags"] = self.tags; // So we can independently change the tags

    self.folders = [NSMutableArray arrayWithCapacity:10];
    self.rowsBySectionId[@"folders"] = self.folders;

    self.prettyNumberFormatter = [[NSNumberFormatter alloc] init];
    self.prettyNumberFormatter.numberStyle = NSNumberFormatterDecimalStyle;

    self.tagTextField = [[UITextField alloc] initWithFrame:CGRectMake(10.0, 20, 300, 48.0)];
    self.tagTextField.delegate = self;
    self.tagTextField.placeholder = @"Add New...";
    self.tagTextField.font = [UIFont systemFontOfSize:28.0];
    self.tagTextField.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tagTextField.returnKeyType = UIReturnKeyDone;
    self.tagTextField.enablesReturnKeyAutomatically = YES;
    self.tagTextField.autocorrectionType = UITextAutocorrectionTypeNo;

    [self.tableView registerClass:[CLScreenshotTagCell class] forCellReuseIdentifier:@"TagCell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"TextFieldCell"];

    self.navigationItem.title = @"Choose Folder";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(onCancelBarButtonItemTapped:)];
    self.saveBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(onSaveBarButtonItemTapped:)];
}

- (instancetype)initWithScreenshots:(NSArray *)screenshots assets:(NSArray *)assets initialTag:(Tag *)initialTag delegate:(NSObject <CLTaggingViewControllerDelegate>*)delegate
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        self.delegate = delegate;
        _screenshots = [screenshots copy];
        _assets = [assets copy];
        _initialTag = initialTag;

        [self commonInit];
    }
    return self;
}


- (instancetype)initWithScreenshotFiles:(NSArray *)screenshotFiles initialTag:(Tag *)initialTag delegate:(NSObject <CLTaggingViewControllerDelegate>*)delegate
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        self.delegate = delegate;
        _screenshotFiles = [screenshotFiles copy];
        _initialTag = initialTag;

        [self commonInit];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
 
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
    [self.tags removeAllObjects];
    NSMutableArray *tagsToShow = [[[ScreenshotCatalog sharedCatalog] retrieveAllTagsIncludeTrash:NO] mutableCopy];
    [tagsToShow sortWithOptions:0 usingComparator:^NSComparisonResult(id obj1, id obj2) {
        Tag *tag1 = (Tag *)obj1;
        Tag *tag2 = (Tag *)obj2;
        return [tag1.name compare:tag2.name];
    }];
    [self.tags addObjectsFromArray:tagsToShow];

    // Load Document folders
    [self.folders removeAllObjects];
    [self.folders addObjectsFromArray:[ScreenshotStorage sharedInstance].screenshotFolders];

    [self updateSections];
    [self.tableView reloadData];
}

- (void) updateSections
{
    [self.sectionIds removeAllObjects];
    [self.sectionIds addObject:@"new"];
    if (self.folders.count > 0) {
        [self.sectionIds addObject:@"folders"];
    }
    if (self.tags.count > 0) {
        [self.sectionIds addObject:@"tags"];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [self startListeningForKeyboardAppearances];
    if (self.tags.count == 0) {
        [self.tagTextField becomeFirstResponder];
    }
    [[Analytics sharedInstance] registerScreen:@"Move to Folder"];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [self stopListeningForKeyboardAppearances];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)onCancelBarButtonItemTapped:(id)sender
{
    if (self.tagTextField.isFirstResponder && self.tags.count > 0) {
        [self.tagTextField resignFirstResponder];
    } else {
        [self.delegate taggingViewControllerDidCancel:self];
    }
}

- (void)onSaveBarButtonItemTapped:(id)sender
{
    [self tagWithTextfieldText];
}

- (void)tagWithTextfieldText
{
    NSString *name = [self.tagTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length == 0) {
        return;
    }

    CLLog(@"Entered textfield text: %@", name);

    if (TEXTFIELD_CREATES_TAG_NOT_FOLDER) {
        Tag *tag = [[ScreenshotCatalog sharedCatalog] tagScreenshots:self.screenshots withTagName:name];

        [[Analytics sharedInstance] track:@"tag_shots"
                               properties:@{@"num_shots" : @(self.screenshots.count),
                                            @"tag_name" : name}];
        [self.delegate taggingViewController:self didSaveItemsToFolder:nil alsoAddedToTag:tag];
    } else {
        [[ScreenshotStorage sharedInstance] createFolderWithName:name completion:^(ScreenshotFolder *folder, NSError *error) {
            if (error == nil) {
                [[Analytics sharedInstance] track:@"file_shots"
                                       properties:@{@"num_shots" : @(self.screenshots.count),
                                                    @"folder_name" : name}];
                [self saveItemsToFolder:folder];
            } else {
                NSString *message = [NSString stringWithFormat:@"There was an error creating the folder '%@': %@ - %@", name, error, error.userInfo[@"message"]];
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Couldn't Create Folder"
                                                                                         message:message
                                                                                  preferredStyle:UIAlertControllerStyleAlert];
                [alertController addAction:[UIAlertAction actionWithTitle:@"Okay" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:alertController animated:YES completion:nil];
            }
        }];
    }

}

- (void) saveItemsToFolder:(ScreenshotFolder *)folder
{
    void (^displayErrorAlert)(NSString *message) = ^(NSString *message) {
        CLLog(@"Displaying error alert: %@", message);
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Oops"
                                                                                 message:message
                                                                          preferredStyle:UIAlertControllerStyleAlert];
        [alertController addAction:[UIAlertAction actionWithTitle:@"Okay" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alertController animated:YES completion:nil];
    };

    BOOL textFieldWasEditing = self.tagTextField.isFirstResponder;
    [self.tagTextField resignFirstResponder];

    if (self.screenshots.count && self.assets.count) {
        // We're moving "screenshot+asset" from CoreData/CameraRoll into folder
        Tag *trashTag = nil;
        if (MARK_SCREENSHOTS_AS_TRASH_IF_STORED_IN_FOLDER) {
            // Also "file" this screenshot into trash
            trashTag = [[ScreenshotCatalog sharedCatalog] createTrashTagIfNeeded];
            if (self.screenshots.count) {
                // We may not actually have screenshot objects, if we are moving
                // *BETWEEN* file-based folders
                [[ScreenshotCatalog sharedCatalog] tagScreenshots:self.screenshots withTag:trashTag];
            }
        }
        __block MBProgressHUD *hud = nil;
        hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        hud.userInteractionEnabled = NO;
        hud.graceTime = 1.0;
        hud.mode = MBProgressHUDModeDeterminateHorizontalBar;
        hud.labelText = @"Moving Screenshots...";
        self.view.userInteractionEnabled = NO;
        [[ScreenshotStorage sharedInstance] saveAssets:self.assets toFolderWithName:folder.folderName progressHandler:^(CGFloat progress) {
            hud.taskInProgress = YES;
            if (progress > 0.0 && progress < 1.0) {
                hud.labelText = @"Moving Screenshots...";
            } else if (progress >= 1.0) {
                hud.labelText = @"Finishing up...";
            }
            hud.progress = progress;
        } completion:^(NSError *error) {
            self.view.userInteractionEnabled = YES;
            hud.taskInProgress = NO;
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            if (error == nil) {
                [self.delegate taggingViewController:self didSaveItemsToFolder:folder alsoAddedToTag:trashTag];
            } else {
                displayErrorAlert([NSString stringWithFormat:@"Couldn't save screenshot assets to '%@': %@ - %@", folder.folderName, error, error.userInfo[@"message"]]);
                if (textFieldWasEditing) {
                    [self.tagTextField becomeFirstResponder];
                }
            }
        }];
    } else if (self.screenshotFiles.count) {
        // We're moving actual files between folders
        [[ScreenshotStorage sharedInstance] moveScreenshotFiles:self.screenshotFiles toFolder:folder progressHandler:nil completion:^(BOOL success, NSError *error) {
            if (error == nil) {
                [self.delegate taggingViewController:self didSaveItemsToFolder:folder alsoAddedToTag:nil];
            } else if (error.code == NSFileWriteFileExistsError) {
                if (self.screenshotFiles.count == 1) {
                    displayErrorAlert([NSString stringWithFormat:@"This screenshot is already in %@", folder.folderName]);
                } else {
                    displayErrorAlert([NSString stringWithFormat:@"One of the screenshots already exists in %@. Deselect that screenshot and try again.", folder.folderName]);
                }
            } else {
                displayErrorAlert([NSString stringWithFormat:@"Couldn't move screenshots to '%@': %@ - %@", folder.folderName, error, error.userInfo[@"message"]]);
            }
            if (textFieldWasEditing) {
                [self.tagTextField becomeFirstResponder];
            }
        }];
    } else {
        if (textFieldWasEditing) {
            [self.tagTextField becomeFirstResponder];
        }
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return self.sectionIds.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSArray *rows = self.rowsBySectionId[self.sectionIds[section]];
    return rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = nil;

    NSString *sectionId = self.sectionIds[indexPath.section];
    NSArray *rows = self.rowsBySectionId[sectionId];

    if ([sectionId isEqualToString:@"new"]) {
        NSString *rowId = rows[indexPath.row];
        if ([rowId isEqualToString:@"enterName"]) {
            // Create long-lasting cell, which gets returned every time
            if (!self.folderNameCell) {
                self.folderNameCell = [tableView dequeueReusableCellWithIdentifier:@"TextFieldCell" forIndexPath:indexPath];
                [self.folderNameCell.contentView addSubview:self.tagTextField];
            }
            CGRect textFieldRect = self.tagTextField.frame;
            textFieldRect.size.height = CGRectGetHeight(self.folderNameCell.contentView.bounds) - (CGRectGetMinY(textFieldRect) * 2.0);
            textFieldRect.size.width = CGRectGetWidth(self.folderNameCell.contentView.bounds) - (CGRectGetMinX(textFieldRect) * 2.0);
            self.tagTextField.frame = textFieldRect;
            cell = self.folderNameCell;
        } else {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"UnknownCell"];
            cell.textLabel.text = [NSString stringWithFormat:@"Unknown rowId: %@", rowId];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([sectionId isEqualToString:@"folders"]) {
        cell = [tableView dequeueReusableCellWithIdentifier:@"TagCell" forIndexPath:indexPath];
        ScreenshotFolder *folder = self.folders[indexPath.row];
        cell.textLabel.text = folder.folderName;
        cell.detailTextLabel.text = [self.prettyNumberFormatter stringFromNumber:@(folder.count)];
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
    } else {
        cell = [tableView dequeueReusableCellWithIdentifier:@"TagCell" forIndexPath:indexPath];
        CLScreenshotTagCell *tagCell = (CLScreenshotTagCell *)cell;
        Tag *tag = self.tags[indexPath.row];
        tagCell.textLabel.text = tag.name;
        tagCell.textLabel.textColor = [UIColor lightGrayColor];
        tagCell.detailTextLabel.text = [self.prettyNumberFormatter stringFromNumber:@(tag.screenshots.count)];
        if (self.initialTag != nil) {
            tagCell.selected = [tag.name isEqualToString:self.initialTag.name];
        } else {
            tagCell.selected = NO;
        }
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
    }
    
    return cell;
}


#pragma mark - UITableViewDelegate


- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 88.0;
}


- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString *sectionId = self.sectionIds[section];
    NSArray *rows = self.rowsBySectionId[sectionId];
    if ([sectionId isEqualToString:@"folders"]) {
        if (rows.count > 0) {
            return @"FOLDERS";
        }
    }
    if ([sectionId isEqualToString:@"tags"]) {
        if (rows.count > 0) {
            return @"TAGS";
        }
    }
    return nil;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *sectionId = self.sectionIds[indexPath.section];
    if ([sectionId isEqualToString:@"folders"]) {
        ScreenshotFolder *folder = self.folders[indexPath.row];
        CLLog(@"Selected existing folder: %@", folder.folderName);
        [self saveItemsToFolder:folder];
    } else if ([sectionId isEqualToString:@"tags"]) {
        Tag *selectedTag = self.tags[indexPath.row];
        CLLog(@"Selected existing tag: %@", selectedTag.name);
        [[ScreenshotCatalog sharedCatalog] tagScreenshots:self.screenshots withTag:selectedTag];
        [self.delegate taggingViewController:self didSaveItemsToFolder:nil alsoAddedToTag:selectedTag];
    }
}


#pragma mark - UITextFieldDelegate


- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
    NSString *proposedText = [textField.text stringByReplacingCharactersInRange:range withString:string];
    proposedText = [proposedText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (proposedText.length > 0 && !self.navigationItem.rightBarButtonItem) {
        [self.navigationItem setRightBarButtonItem:self.saveBarButtonItem animated:YES];
    } else if (proposedText.length == 0 && self.navigationItem.rightBarButtonItem) {
        [self.navigationItem setRightBarButtonItem:nil animated:NO];
    }
    return YES;
}


- (void)textFieldDidEndEditing:(UITextField *)textField
{
    if (self.navigationItem.rightBarButtonItem) {
        [self.navigationItem setRightBarButtonItem:nil animated:NO];
    }
}


- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [self tagWithTextfieldText];
    return YES;
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


- (void)adjustInsetsForKeyboardUserInfo:(NSDictionary *)info
{
    CGRect keyboardFrame = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat visibleKeyboardHeight = (CGRectGetHeight([UIScreen mainScreen].bounds)-CGRectGetMinY(keyboardFrame));

    UIEdgeInsets contentInset = self.tableView.contentInset;
    contentInset.bottom = visibleKeyboardHeight;
    self.tableView.contentInset = contentInset;
}


- (void)keyboardWillChangeFrame:(NSNotification *)notification
{
    NSDictionary *info = notification.userInfo;
    [self adjustInsetsForKeyboardUserInfo:info];
}


- (void)keyboardDidChangeFrame:(NSNotification *)notification
{
    NSDictionary *info = notification.userInfo;
    [self adjustInsetsForKeyboardUserInfo:info];
}

@end
