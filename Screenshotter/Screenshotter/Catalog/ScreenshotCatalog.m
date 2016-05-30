//
//  ScreenshotCatalog.m
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

#import "ScreenshotCatalog.h"

#import <AssetsLibrary/AssetsLibrary.h>
#import "CLScreenshotsLoader.h"
#import <Photos/Photos.h>
#import "Screenshot.h"
#import "Tag.h"
#import "TagType.h"


static BOOL const USE_PHOTOS_FRAMEWORK = YES;
static BOOL const SORT_ASCENDING = NO;

NSString * const ScreenshotCatalogDidBeginSyncingNotification = @"ScreenshotCatalogDidBeginSyncingNotification";
NSString * const ScreenshotCatalogDidFinishSyncingNotification = @"ScreenshotCatalogDidFinishSyncingNotification";


@interface ScreenshotCatalog () <PHPhotoLibraryChangeObserver>

@property (strong, nonatomic) NSIndexPath *currentCameraRollReadOffset;
@property (assign, nonatomic) BOOL likelyHasMoreScreenshots;
@property (strong, nonatomic) ALAssetsGroup *cameraRollAssetsGroup;

@property (strong, nonatomic) NSMutableArray *assetsInCameraRoll;

// String-based sets which make comparing them later easier
@property (strong, nonatomic) NSMutableSet *assetIdsInCameraRoll;
@property (strong, nonatomic) NSMutableSet *assetIdsInCatalog;

// Tracking counts
@property (assign, nonatomic) NSInteger screenshotsCount;
@property (assign, nonatomic) NSInteger unfiledScreenshotsCount;

@property (assign, nonatomic) BOOL syncingDatabase;

@property (strong, nonatomic) PHFetchResult *allPHAssetImages;

@end

@implementation ScreenshotCatalog

@synthesize managedObjectContext = _managedObjectContext;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;

+ (instancetype)sharedCatalog
{
    static ScreenshotCatalog *_catalog;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _catalog = [[ScreenshotCatalog alloc] init];
    });
    return _catalog;
}


- (id)init
{
    self = [super init];
    if (self) {
        _screenshotsCount = NSNotFound;
        _unfiledScreenshotsCount = NSNotFound;
    }
    return self;
}


- (void)dealloc
{
    if (USE_PHOTOS_FRAMEWORK) {
        [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:ALAssetsLibraryChangedNotification
                                                      object:[CLScreenshotsLoader assetsLibrary]];
    }
}


#pragma mark - Keep Camera Roll photos in sync


- (void)beginSyncingWithCameraRoll
{
    if (self.syncingDatabase) {
        CLLog(@"Already syncing with camera roll, so skipping");
        return;
    }
    CLLog(@"Starting sync with Camera roll");
    if (USE_PHOTOS_FRAMEWORK) {
        [self convertCatalogScreenshotsToUsePHAssetIds];
    }
    self.syncingDatabase = YES;
    self.assetsInCameraRoll = [NSMutableArray arrayWithCapacity:500];
    self.assetIdsInCameraRoll = [NSMutableSet setWithCapacity:500];

    self.likelyHasMoreScreenshots = YES;
    self.currentCameraRollReadOffset = nil;

    if (USE_PHOTOS_FRAMEWORK) {
        [self readIncrementalFromCameraRoll];
    } else {
        ALAssetsLibrary *library = [CLScreenshotsLoader assetsLibrary];
        [library enumerateGroupsWithTypes:ALAssetsGroupSavedPhotos usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
            if (group == nil) {
                return; // skip anything that's nil
            }
            self.cameraRollAssetsGroup = group;
            [self readIncrementalFromCameraRoll];
        } failureBlock:^(NSError *error) {

            self.syncingDatabase = NO;
            // TODO(Riz): Notify that catalog database sync failed
        }];
    }
}


- (void)readIncrementalFromCameraRoll
{
    void (^addScreenshotsAndContinue)(NSArray *screenshots, NSIndexPath *nextStartingIndexPath, NSError *error) = ^(NSArray *screenshots, NSIndexPath *nextStartingIndexPath, NSError *error) {
        if ([screenshots.firstObject isKindOfClass:[ALAsset class]]) {
            for (ALAsset *screenshot in screenshots) {
                if (screenshot.defaultRepresentation.url) {
                    [self.assetsInCameraRoll addObject:screenshot];
                    // Faster cache of these things
                    [self.assetIdsInCameraRoll addObject:screenshot.defaultRepresentation.url.absoluteString];
                }
            }
        } else if ([screenshots.firstObject isKindOfClass:[PHAsset class]]) {

            for (PHAsset *screenshot in screenshots) {
                [self.assetsInCameraRoll addObject:screenshot];
                [self.assetIdsInCameraRoll addObject:screenshot.localIdentifier];
            }
        }

        self.currentCameraRollReadOffset = nextStartingIndexPath;
        self.likelyHasMoreScreenshots = screenshots.count > 0;
        if (self.likelyHasMoreScreenshots) {
            double delayInSeconds = 0.01;
            dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
            dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                [self readIncrementalFromCameraRoll];
            });
        } else {
            // We've read in all the assets that are screenshots. Now compare them to what's in our DB
            [self loadExistingScreenshotRecords];
            [self invalidateCounts];
            NSUInteger numAdded = [self addScreenshotAssetsToDatabase:self.assetsInCameraRoll];
            NSUInteger numRemoved = [self removeMissingScreenshotsFromDatabase];
            CLLog(@"Database sync complete. %ld added, %ld removed.", (unsigned long)numAdded, (unsigned long)numRemoved);
            self.syncingDatabase = NO;
            [[NSNotificationCenter defaultCenter] postNotificationName:ScreenshotCatalogDidFinishSyncingNotification
                                                                object:self
                                                              userInfo:@{@"added" : @(numAdded),
                                                                         @"removed" : @(numRemoved)}];
            [self startMaintainingAllPHAssetImagesList];
            [self saveContext];
        }
    };
    BOOL useAssetsLibrary = !USE_PHOTOS_FRAMEWORK;
    if (useAssetsLibrary) {
        [CLScreenshotsLoader getScreenshotsInAssetsGroup:self.cameraRollAssetsGroup
                                     startingAtIndexPath:self.currentCameraRollReadOffset
                                      excludingAssetURLs:nil
                                         completionBlock:^(NSArray *screenshots, NSIndexPath *nextStartingIndexPath, NSError *error) {
                                             addScreenshotsAndContinue(screenshots, nextStartingIndexPath, error);
                                         }];
    } else {

        [CLScreenshotsLoader getScreenshotsStartingAtIndexPath:self.currentCameraRollReadOffset
                                                 sortAscending:SORT_ASCENDING
                                               completionBlock:^(NSArray *screenshots, NSIndexPath *nextStartingIndexPath, NSError *error) {
                                                   addScreenshotsAndContinue(screenshots, nextStartingIndexPath, error);
                                               }];
    }
}


- (void)loadExistingScreenshotRecords
{
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"Screenshot"];
    fetchRequest.propertiesToFetch = @[@"localAssetURL"];
    fetchRequest.resultType = NSDictionaryResultType;
    NSError *fetchError;
    NSArray *results = [self.managedObjectContext executeFetchRequest:fetchRequest error:&fetchError];
    // results is a NSDictionary with the property name as 'localAssetURL'
    self.assetIdsInCatalog = [NSMutableSet setWithCapacity:results.count];
    for (NSDictionary *resultDict in results) {
        [self.assetIdsInCatalog addObject:resultDict[@"localAssetURL"]];
    }
}


- (NSUInteger)addScreenshotAssetsToDatabase:(NSArray *)screenshotAssets
{
    NSUInteger numAdded = 0;
    for (id screenshotAsset in screenshotAssets) {
        NSString *assetId = nil;
        PHAsset *phAsset = nil;
        ALAsset *alAsset = nil;

        if ([screenshotAsset isKindOfClass:[PHAsset class]]) {
            phAsset = ((PHAsset *)screenshotAsset);
            assetId = phAsset.localIdentifier;
        } else if ([screenshotAsset isKindOfClass:[ALAsset class]]) {
            alAsset = ((ALAsset *)screenshotAsset);
            assetId = alAsset.defaultRepresentation.url.absoluteString;
        }

        if (assetId && ![self.assetIdsInCatalog member:assetId]) {
            // Keep our local set up-to-date
            [self.assetIdsInCatalog addObject:assetId];

            Screenshot *screenshot = [NSEntityDescription insertNewObjectForEntityForName:@"Screenshot"
                                                                   inManagedObjectContext:self.managedObjectContext];

            screenshot.localAssetURL = assetId;
            if (phAsset) {
                screenshot.width = @(phAsset.pixelWidth);
                screenshot.height = @(phAsset.pixelHeight);
                screenshot.timestamp = phAsset.creationDate;
            } else if (alAsset) {
                ALAssetRepresentation *representation = alAsset.defaultRepresentation;
                // For debugging with a breakpoint to see which screenshot was added
                // UIImage *thumbnail = [UIImage imageWithCGImage:screenshotAsset.aspectRatioThumbnail];
                CGSize dimensions = representation.dimensions;
                screenshot.width = @(dimensions.width);
                screenshot.height = @(dimensions.height);
                screenshot.timestamp = [screenshotAsset valueForProperty:ALAssetPropertyDate];
            }

            numAdded++;
        }
    }
    if (numAdded > 0) {
        [self invalidateCounts];
    }
    return numAdded;
}


- (NSUInteger)removeScreenshotsFromDatabaseWithAssetIds:(NSSet *)screenshotAssetIds
{
    NSUInteger numRemoved = 0;
    // Get Screenshots matching these ids
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"Screenshot"];
    request.predicate = [NSPredicate predicateWithFormat:@"(localAssetURL IN %@)", screenshotAssetIds];
    NSArray *screenshots = [self.managedObjectContext executeFetchRequest:request error:NULL];
    NSMutableSet *foundAssetIds = [NSMutableSet setWithCapacity:screenshotAssetIds.count];
    for (Screenshot *screenshot in screenshots) {
        if (screenshot.localAssetURL) {
            [foundAssetIds addObject:screenshot.localAssetURL];
        } else {
            CLLog(@"Deleting screenshot, but it had a nil 'localAssetUrl'");
        }
        [self.managedObjectContext deleteObject:screenshot];
        numRemoved++;
    }
    if (foundAssetIds.count < screenshotAssetIds.count) {
        CLLog(@"In removing screenshots matching asset ids, %lu assetIds were given, but %lu matching screenshots found in catalog.", (unsigned long)screenshotAssetIds.count, (unsigned long)screenshots.count);
        NSSet *notFoundAssetIds = [screenshotAssetIds objectsPassingTest:^BOOL(id obj, BOOL *stop) {
            return ![foundAssetIds containsObject:obj];
        }];
        CLLog(@"%lu asset ids not found in catalog: %@", (unsigned long)notFoundAssetIds.count, notFoundAssetIds);
    }
    if (numRemoved > 0) {
        [self invalidateCounts];
    }
    return numRemoved;
}


- (NSUInteger)removeMissingScreenshotsFromDatabase
{
    NSUInteger numRemoved = 0;
    NSMutableSet *assetIdsMissingInCameraRoll = [self.assetIdsInCatalog mutableCopy];
    [assetIdsMissingInCameraRoll minusSet:self.assetIdsInCameraRoll];
    if (assetIdsMissingInCameraRoll.count == 0) {
        return numRemoved;
    }
    CLLog(@"Found %ld screenshots to remove", (unsigned long)assetIdsMissingInCameraRoll.count);
    return [self removeScreenshotsFromDatabaseWithAssetIds:assetIdsMissingInCameraRoll];
}


- (void)beginListeningForPhotoLibraryChanges
{
    if (USE_PHOTOS_FRAMEWORK) {
        [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
    } else {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onAssetsLibraryDidChange:)
                                                     name:ALAssetsLibraryChangedNotification
                                                   object:[CLScreenshotsLoader assetsLibrary]];
    }
}


- (void)startMaintainingAllPHAssetImagesList
{
    if (USE_PHOTOS_FRAMEWORK) {
        PHFetchOptions *options = [[PHFetchOptions alloc] init];
        options.includeAllBurstAssets = NO;
        options.includeHiddenAssets = NO;
        options.wantsIncrementalChangeDetails = YES;
        self.allPHAssetImages = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:options];
    }
}


- (void)photoLibraryDidChange:(PHChange *)changeInstance
{
    if (!self.allPHAssetImages) {
        return;
    }
    PHFetchResultChangeDetails *changeDetails = [changeInstance changeDetailsForFetchResult:self.allPHAssetImages];
    if (changeDetails) {
        self.allPHAssetImages = changeDetails.fetchResultAfterChanges;
        if (!changeDetails.hasIncrementalChanges) {
            // The changes were too big and it requires a full reload
            CLLog(@"Change details are not incremental, indicating a full reload is recommend. Syncing with camera roll...");
            [self beginSyncingWithCameraRoll];
            return;
        }

        // Ensure we do CoreData changes in the main thread (or just the thread we created the context on)
        dispatch_async(dispatch_get_main_queue(), ^{
            CLLog(@"PHPhotoLibrary Change Details: Photos Inserted: %ld, Photos Deleted: %ld, Photos Changed: %ld",
                  (unsigned long)changeDetails.insertedObjects.count,
                  (unsigned long)changeDetails.removedObjects.count,
                  (unsigned long)changeDetails.changedObjects.count);

            NSUInteger numAdded = 0;
            NSUInteger numRemoved = 0;
            if (changeDetails.insertedObjects.count > 0) {
                NSMutableArray *addedScreenshotAssets = [NSMutableArray arrayWithCapacity:changeDetails.insertedObjects.count];
                for (PHAsset *addedAsset in changeDetails.insertedObjects) {
                    if ([CLScreenshotsLoader phAssetIsProbablyScreenshot:addedAsset]) {
                        [addedScreenshotAssets addObject:addedAsset];
                    }
                }
                numAdded = [self addScreenshotAssetsToDatabase:addedScreenshotAssets];
            }

            if (changeDetails.removedObjects.count > 0) {
                NSMutableSet *removedAssetIds = [NSMutableSet setWithCapacity:changeDetails.removedObjects.count];
                for (PHAsset *removedAsset in changeDetails.removedObjects) {
                    NSString *assetId = removedAsset.localIdentifier;
                    [removedAssetIds addObject:assetId];
                }
                numRemoved = [self removeScreenshotsFromDatabaseWithAssetIds:removedAssetIds];
            }
            CLLog(@"Catalog Update complete. %ld added, %ld removed.", (unsigned long)numAdded, (unsigned long)numRemoved);
            
            if (numAdded || numRemoved) {
                [self saveContext];
            }
        });
    }
}


- (void)fakeRemoveScreenshotsWithAssetIds:(NSSet *)assetIds completion:(void (^)(BOOL success, NSError *error))completion
{
    NSTimeInterval delay = 1.0 + (1.0/(NSTimeInterval)(arc4random() % 10));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (completion) {
            completion(YES, nil);
        }
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSUInteger numRemoved = [self removeScreenshotsFromDatabaseWithAssetIds:assetIds];
        CLLog(@"Update complete. %ld removed.", (unsigned long)numRemoved);
        if (numRemoved) {
            [self saveContext];
        }
    });
}


- (void)onAssetsLibraryDidChange:(NSNotification *)notification
{
    NSDictionary *userInfo = notification.userInfo;
    if (userInfo != nil && userInfo.count == 0) {
        // Empty non-nil dictionary. Do nothing, according to Apple docs
        return;
    }
    NSArray *keys = userInfo.allKeys;
    // NOTE(Riz): When taking an iOS screenshot, the notifications
    // seem to contain 'updated' group and assets, not
    // 'inserted', but check for 'insert' and 'deleted' anyway
    if (([keys containsObject:ALAssetLibraryUpdatedAssetGroupsKey] &&
        [keys containsObject:ALAssetLibraryUpdatedAssetsKey]) ||
        [keys containsObject:ALAssetLibraryInsertedAssetGroupsKey] ||
        [keys containsObject:ALAssetLibraryDeletedAssetGroupsKey]) {
        [self beginSyncingWithCameraRoll];
    }
}


- (void)invalidateCounts
{
    self.screenshotsCount = NSNotFound;
    self.unfiledScreenshotsCount = NSNotFound;
}


#pragma mark - PHAsset conversion


- (void)convertCatalogScreenshotsToUsePHAssetIds
{
    // Get all current screenshots from core data whose id starts with "assets-library://"
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"Screenshot"];
    //fetchRequest.propertiesToFetch = @[@"localAssetURL"];
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"(localAssetURL BEGINSWITH[c] %@)", @"assets-library://"];
    NSError *fetchError;
    NSArray *allScreenshotsWithALAssetURLs = [self.managedObjectContext executeFetchRequest:fetchRequest error:&fetchError];

    NSDictionary *dict = [self phAssetsByIdFromScreenshots:allScreenshotsWithALAssetURLs];

    NSInteger numConverted = 0;
    for (Screenshot *screenshot in allScreenshotsWithALAssetURLs) {
        PHAsset *asset = dict[screenshot.localAssetURL];
        // Change local asset url to ph asset local identifier
        if (asset) {
            screenshot.localAssetURL = asset.localIdentifier;
            numConverted++;
        }
    }

    CLLog(@"Converted %ld screenshot from asset URLS to phAsset ids", (long)numConverted);

    [self saveContext];
}


- (NSDictionary *)phAssetsByIdFromScreenshots:(NSArray *)screenshots
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


#pragma mark - Tags


- (NSArray *)retrieveAllTagsIncludeTrash:(BOOL)includeTrash
{
    NSFetchRequest *tagsRequest = [[NSFetchRequest alloc] initWithEntityName:@"Tag"];
    if (!includeTrash) {
        tagsRequest.predicate = [NSPredicate predicateWithFormat:@"type != %d", TagTypeTrash];
    }
    NSArray *results = [self.managedObjectContext executeFetchRequest:tagsRequest error:NULL];
    return results;
}


- (Tag *)tagScreenshots:(NSArray *)screenshots withTagName:(NSString *)tagName
{
    if (tagName.length == 0) {
        return nil;
    }
    if (screenshots.count == 0) {
        return nil;
    }

    NSManagedObjectContext *context = [ScreenshotCatalog sharedCatalog].managedObjectContext;

    // First see if we have a tag like that
    NSFetchRequest *tagCheckRequest = [[NSFetchRequest alloc] initWithEntityName:@"Tag"];
    tagCheckRequest.predicate = [NSPredicate predicateWithFormat:@"name ==[cd] %@", tagName];
    NSArray *tagCheckResults = [context executeFetchRequest:tagCheckRequest error:NULL];

    Tag *tagToSet;
    if (tagCheckResults.count > 0) {
        // We have a tag!
        tagToSet = tagCheckResults.lastObject;
    } else {
        // This tag doesn't exist; create it
        tagToSet = [NSEntityDescription insertNewObjectForEntityForName:@"Tag" inManagedObjectContext:context];
        tagToSet.name = tagName;
        tagToSet.timestamp = [NSDate date];
        tagToSet.type = @(TagTypeNormal);
    }

    [self tagScreenshots:screenshots withTag:tagToSet];
    return tagToSet;
}


- (void)tagScreenshots:(NSArray *)screenshots withTag:(Tag *)tag
{
    if (screenshots.count == 0 || tag == nil) {
        return;
    }
    // Ok now add the tag
    NSSet *tags = [NSSet setWithObject:tag];
    for (Screenshot *screenshot in screenshots) {
        screenshot.tags = tags;
    }
    _unfiledScreenshotsCount = NSNotFound;
    [[ScreenshotCatalog sharedCatalog] saveContext];
}


- (void)deleteScreenshots:(NSArray *)screenshotsToDelete
{
    if (screenshotsToDelete.count == 0) {
        return;
    }
    for (Screenshot *screenshotToDelete in screenshotsToDelete) {
        [[ScreenshotCatalog sharedCatalog].managedObjectContext deleteObject:screenshotToDelete];
    }
    [[ScreenshotCatalog sharedCatalog] saveContext];
}


- (Tag *)trashTag
{
    NSFetchRequest *trashTagRequest = [[NSFetchRequest alloc] initWithEntityName:@"Tag"];
    trashTagRequest.predicate = [NSPredicate predicateWithFormat:@"type == %d", TagTypeTrash];
    NSArray *results = [self.managedObjectContext executeFetchRequest:trashTagRequest error:NULL];
    if (results.count > 0) {
        return results[0];
    } else {
        return nil;
    }
}


- (Tag *)createTrashTagIfNeeded
{
    Tag *trashTag = [self trashTag];
    if (trashTag == nil) {
        // No trash tag found, create one
        trashTag = [NSEntityDescription insertNewObjectForEntityForName:@"Tag"
                                                 inManagedObjectContext:self.managedObjectContext];
        trashTag.name = @"Archive";
        trashTag.timestamp = [NSDate date];
        trashTag.type = @(TagTypeTrash);
    }
    return trashTag;
}


- (void)mergeTag:(Tag *)tagToMergeFrom intoTag:(Tag *)tagToMergeInfo deleteMergedTag:(BOOL)deleteMergedTag
{
    NSArray *screenshots = [tagToMergeFrom.screenshots copy];
    [self tagScreenshots:screenshots withTag:tagToMergeInfo];

    if (deleteMergedTag) {
        [self deleteTag:tagToMergeFrom];
    }
}


- (void)deleteTag:(Tag *)tagToDelete
{
    // "Untag" the screenshots (not sure if this is needed)
    NSSet *emptyTags = [NSSet set];
    BOOL didUpdateScreenshots = NO;
    NSArray *screenshotsToUntag = [tagToDelete.screenshots copy];
    for (Screenshot *screenshot in screenshotsToUntag) {
        screenshot.tags = emptyTags;
        didUpdateScreenshots = YES;
    }
    if (didUpdateScreenshots) {
        _unfiledScreenshotsCount = NSNotFound;
    }
    [[ScreenshotCatalog sharedCatalog].managedObjectContext deleteObject:tagToDelete];
    [[ScreenshotCatalog sharedCatalog] saveContext];
}


#pragma mark - Screenshots


- (NSUInteger)countOfAllScreenshots
{
    if (self.screenshotsCount == NSNotFound) {
        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Screenshot"];
        request.resultType = NSCountResultType;
        NSArray *results = [self.managedObjectContext executeFetchRequest:request error:NULL];
        self.screenshotsCount = [results[0] integerValue];
    }
    return self.screenshotsCount;
}


- (NSUInteger)countOfAllUnfiledScreenshots
{
    if (self.unfiledScreenshotsCount == NSNotFound) {
        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Screenshot"];
        request.predicate = [NSPredicate predicateWithFormat:@"tags.@count == 0"];
        request.resultType = NSCountResultType;
        NSArray *results = [self.managedObjectContext executeFetchRequest:request error:NULL];
        self.unfiledScreenshotsCount = [results[0] integerValue];
    }
    return self.unfiledScreenshotsCount;
}


- (NSDate *)dateOfMostRecentScreenshot
{
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"Screenshot"];
    request.fetchBatchSize = 1;
    request.fetchLimit = 1;
    request.propertiesToFetch = @[@"timestamp"];
    request.resultType = NSDictionaryResultType;
    NSSortDescriptor *sortByTimestamp = [NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:NO];
    request.sortDescriptors = @[sortByTimestamp];
    NSArray *results = [self.managedObjectContext executeFetchRequest:request error:NULL];
    if (results.count == 0) {
        // No screenshots
        return nil;
    } else {
        NSDate *timestamp = results.lastObject[@"timestamp"];
        return timestamp;
    }
}


#pragma mark - Updating Mixpanel Super Properties


- (void)updateMixpanelSuperProperties
{
    NSUInteger numTags = [self retrieveAllTagsIncludeTrash:NO].count;
    [[Analytics sharedInstance] set:@{@"num_device_shots" : @(self.countOfAllScreenshots),
                                      @"num_tags" : @(numTags)}];
}



#pragma mark - Saving the database

- (void)saveContext
{
    NSError *error = nil;
    NSManagedObjectContext *managedObjectContext = self.managedObjectContext;
    if (managedObjectContext != nil) {
        if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error]) {
            // Replace this implementation with code to handle the error appropriately.
            // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            CLLog(@"Unresolved error %@, %@", error, [error userInfo]);
            abort();
        }
        [self updateMixpanelSuperProperties];
    }
}

#pragma mark - Core Data stack

// Returns the managed object context for the application.
// If the context doesn't already exist, it is created and bound to the persistent store coordinator for the application.
- (NSManagedObjectContext *)managedObjectContext
{
    if (_managedObjectContext != nil) {
        return _managedObjectContext;
    }

    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (coordinator != nil) {
        // Use initWithConcurrencyType, according to:
        // http://www.objc.io/issue-4/full-core-data-application.html
        _managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        [_managedObjectContext setPersistentStoreCoordinator:coordinator];
        _managedObjectContext.undoManager = [[NSUndoManager alloc] init];
    }
    return _managedObjectContext;
}

// Returns the managed object model for the application.
// If the model doesn't already exist, it is created from the application's model.
- (NSManagedObjectModel *)managedObjectModel
{
    if (_managedObjectModel != nil) {
        return _managedObjectModel;
    }
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"Screenshotter" withExtension:@"momd"];
    _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return _managedObjectModel;
}

// Returns the persistent store coordinator for the application.
// If the coordinator doesn't already exist, it is created and the application's store added to it.
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    if (_persistentStoreCoordinator != nil) {
        return _persistentStoreCoordinator;
    }

    NSURL *storeURL = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:@"Screenshotter.sqlite"];

    NSError *error = nil;
    _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
    if (![_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error]) {
        /*
         Replace this implementation with code to handle the error appropriately.

         abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

         Typical reasons for an error here include:
         * The persistent store is not accessible;
         * The schema for the persistent store is incompatible with current managed object model.
         Check the error message to determine what the actual problem was.


         If the persistent store is not accessible, there is typically something wrong with the file path. Often, a file URL is pointing into the application's resources directory instead of a writeable directory.

         If you encounter schema incompatibility errors during development, you can reduce their frequency by:
         * Simply deleting the existing store:
         [[NSFileManager defaultManager] removeItemAtURL:storeURL error:nil]

         * Performing automatic lightweight migration by passing the following dictionary as the options parameter:
         @{NSMigratePersistentStoresAutomaticallyOption:@YES, NSInferMappingModelAutomaticallyOption:@YES}

         Lightweight migration will only work for a limited set of schema changes; consult "Core Data Model Versioning and Data Migration Programming Guide" for details.

         */
        CLLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }

    return _persistentStoreCoordinator;
}


#pragma mark - Application's Documents directory

// Returns the URL to the application's Documents directory.
- (NSURL *)applicationDocumentsDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}


#pragma mark - Migrating to Folder-based screenshots


- (void)migrateToFolderBasedScreenshotFilesWithCompletion:(void (^)(BOOL succeeded, NSError *error))completionHandler
{
    NSArray *nonTrashTags = [[ScreenshotCatalog sharedCatalog] retrieveAllTagsIncludeTrash:NO];
    if (nonTrashTags.count == 0) {
        if (completionHandler) {
            completionHandler(YES, nil);
        }
        return;
    }
    __block NSInteger numTagsLeftToMigrate = nonTrashTags.count;
    for (Tag *tag in nonTrashTags) {

        CLLog(@"Migrating tag '%@' to folder (%ld screenshots)", tag.name, (long)tag.screenshots.count);

        // Make separate assetURLs and assetLocalIdentifiers so we can fetch assets with them
        NSMutableArray *assetURLs = [NSMutableArray arrayWithCapacity:tag.screenshots.count];
        NSMutableArray *assetLocalIdentifiers = [NSMutableArray arrayWithCapacity:tag.screenshots.count];

        for (Screenshot *screenshot in tag.screenshots) {
            if ([screenshot.localAssetURL hasPrefix:@"assets-library://"]) {
                [assetURLs addObject:[NSURL URLWithString:screenshot.localAssetURL]];
            } else {
                [assetLocalIdentifiers addObject:screenshot.localAssetURL];
            }
        }

        PHFetchResult *assetResults = nil;
        PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
        fetchOptions.wantsIncrementalChangeDetails = NO;
        fetchOptions.includeHiddenAssets = YES;

        NSMutableSet *assetsToMigrate = [NSMutableSet setWithCapacity:tag.screenshots.count];

        if (assetURLs.count > 0) {
            // We have some assets with urls
            assetResults = [PHAsset fetchAssetsWithALAssetURLs:assetURLs options:fetchOptions];
            for (PHAsset *asset in assetResults) {
                [assetsToMigrate addObject:asset];
            }
        }
        if (assetLocalIdentifiers.count > 0) {
            // We have some assets with local identifiers
            assetResults = [PHAsset fetchAssetsWithLocalIdentifiers:assetLocalIdentifiers options:fetchOptions];
            for (PHAsset *asset in assetResults) {
                [assetsToMigrate addObject:asset];
            }
        }

        [[ScreenshotStorage sharedInstance] saveAssets:assetsToMigrate.allObjects toFolderWithName:tag.name progressHandler:nil completion:^(NSError *error) {
            if (error == nil) {
                // Delete that tag (which untags the screenshots)
                [[ScreenshotCatalog sharedCatalog] deleteTag:tag];
            } else {
                CLLog(@"Encountered error during saveAssets:toFolderWithName: %@", error);
            }
            numTagsLeftToMigrate--;


            if (numTagsLeftToMigrate == 0) {
                if (completionHandler) {
                    completionHandler(YES, error);
                }
            }
        }];
    }
}


@end
