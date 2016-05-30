//
//  ScreenshotCatalog.h
//  Screenshotter
//
//  Created by Rizwan Sattar on 2/12/14.
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

#import <Foundation/Foundation.h>

#import "Tag.h"

NSString * const ScreenshotCatalogDidBeginSyncingNotification;
NSString * const ScreenshotCatalogDidFinishSyncingNotification;

// This class acts sort of like the central hub for making
// changes to the database
@interface ScreenshotCatalog : NSObject


+ (instancetype)sharedCatalog;

@property (readonly, strong, nonatomic) NSManagedObjectContext *managedObjectContext;
@property (readonly, strong, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (readonly, strong, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;

@property (readonly, nonatomic) BOOL syncingDatabase;
@property (readonly, nonatomic) NSUInteger countOfAllScreenshots;
@property (readonly, nonatomic) NSUInteger countOfAllUnfiledScreenshots;

#pragma mark - Keep Camera Roll photos in sync
- (void)beginSyncingWithCameraRoll;
- (void)beginListeningForPhotoLibraryChanges;
- (void)fakeRemoveScreenshotsWithAssetIds:(NSSet *)assetIds completion:(void (^)(BOOL success, NSError *error))completion;
#pragma mark - Tags
- (NSArray *)retrieveAllTagsIncludeTrash:(BOOL)includeTrash;
- (Tag *)tagScreenshots:(NSArray *)screenshots withTagName:(NSString *)tagName;
- (void)tagScreenshots:(NSArray *)screenshots withTag:(Tag *)tag;
- (void)deleteScreenshots:(NSArray *)screenshotsToDelete;
- (Tag *)trashTag;
- (Tag *)createTrashTagIfNeeded;
- (void)mergeTag:(Tag *)tagToMergeFrom intoTag:(Tag *)tagToMergeInfo deleteMergedTag:(BOOL)deleteMergedTag;
- (void)deleteTag:(Tag *)tagToDelete;
#pragma mark - Screenshots
- (NSDate *)dateOfMostRecentScreenshot;

- (void)saveContext;
- (NSURL *)applicationDocumentsDirectory;

#pragma mark - Migrating to Folder-based screenshots
- (void)migrateToFolderBasedScreenshotFilesWithCompletion:(void (^)(BOOL succeeded, NSError *error))completionHandler;

@end
