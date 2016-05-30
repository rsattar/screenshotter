//
//  CLScreenshotsLoader.m
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

#import "CLScreenshotsLoader.h"

static NSSet *KNOWN_IPAD_DIMENSIONS;
static NSMutableSet *COMMON_IOS_DIMENSIONS;
// Threshold for when to stop loading screenshots.
static const NSUInteger STOP_LOADING_THRESHOLD = 36;

static PHImageRequestOptions *SCREENSHOT_DATA_REQUEST_OPTIONS;

@implementation CLScreenshotsLoader


+ (void) initialize
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // ENSURE THAT THE CGSIZE DIMENSIONS ALL HAVE WIDTH < HEIGHT
        KNOWN_IPAD_DIMENSIONS = [NSSet setWithArray:@[
                                                      // iPad
                                                      NSStringFromCGSize(CGSizeMake(768, 1024)),    // 1x
                                                      NSStringFromCGSize(CGSizeMake(1536, 2048)),   // 2x
                                                      // iPad Pro 12.9"
                                                      NSStringFromCGSize(CGSizeMake(2048, 2732)),   // 2x
                                                      ]];
        COMMON_IOS_DIMENSIONS = [NSMutableSet setWithArray:@[
                                                             // iPhone Classic
                                                             NSStringFromCGSize(CGSizeMake(320, 480)),     // 1x
                                                             NSStringFromCGSize(CGSizeMake(640, 960)),     // 2x
                                                             // iPhone Tall
                                                             NSStringFromCGSize(CGSizeMake(320, 568)),     // 1x
                                                             NSStringFromCGSize(CGSizeMake(640, 1136)),    // 2x
                                                             // iPhone 6
                                                             NSStringFromCGSize(CGSizeMake(375, 667)),     // 1x
                                                             NSStringFromCGSize(CGSizeMake(750, 1334)),    // 2x
                                                             NSStringFromCGSize(CGSizeMake(1125, 2001)),   // 3x (6 Plus in zoomed mode)
                                                             // iPhone 6 Plus
                                                             NSStringFromCGSize(CGSizeMake(414, 736)),     // 1x
                                                             NSStringFromCGSize(CGSizeMake(1242, 2208)),   // 3x
                                                             // Apple Watch
                                                             NSStringFromCGSize(CGSizeMake(272, 340)),     // 38mm (2x)
                                                             NSStringFromCGSize(CGSizeMake(312, 390)),     // 42mm (2x)
                                                             ]];
        [COMMON_IOS_DIMENSIONS addObjectsFromArray:KNOWN_IPAD_DIMENSIONS.allObjects];

        SCREENSHOT_DATA_REQUEST_OPTIONS = [[PHImageRequestOptions alloc] init];
        SCREENSHOT_DATA_REQUEST_OPTIONS.synchronous = YES;
        SCREENSHOT_DATA_REQUEST_OPTIONS.version = PHImageRequestOptionsVersionOriginal;
        // calls back only once, might be low quality
        SCREENSHOT_DATA_REQUEST_OPTIONS.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
        SCREENSHOT_DATA_REQUEST_OPTIONS.resizeMode = PHImageRequestOptionsResizeModeNone;
        SCREENSHOT_DATA_REQUEST_OPTIONS.networkAccessAllowed = NO;

    });
}


+ (ALAssetsLibrary *) assetsLibrary
{
    static ALAssetsLibrary *assetsLibrary;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        assetsLibrary = [[ALAssetsLibrary alloc] init];
    });
    return assetsLibrary;
}


+ (void) getScreenshotsInAssetsGroup:(ALAssetsGroup *)assetsGroup
                 startingAtIndexPath:(NSIndexPath *)initialIndexPath
                  excludingAssetURLs:(NSSet *)excludeAssetURLs
                     completionBlock:(void (^)(NSArray *screenshots, NSIndexPath *nextStartingIndexPath, NSError *error))completionBlock
{

    // Do this on a background thread so we don't block the main thread.
    // ALAssetsLibrary enumerateAssetsAt... will execute on the thread that it was called from,
    // so calling from the main thread means all that shit potentially blocks UI from advancing.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSIndexPath *nextStartingIndexPath = 0;
        NSArray *screenshots = [CLScreenshotsLoader _getScreenshotsInAssetsGroup:assetsGroup
                                                             startingAtIndexPath:initialIndexPath
                                                              excludingAssetURLs:excludeAssetURLs
                                                                   offsetReached:&nextStartingIndexPath];
        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(screenshots, nextStartingIndexPath, nil);
        });
    });
}


+ (NSArray *) _getScreenshotsInAssetsGroup:(ALAssetsGroup *)assetGroup
                       startingAtIndexPath:(NSIndexPath *)initialIndexPath
                        excludingAssetURLs:(NSSet *)excludeAssetURLs
                             offsetReached:(NSIndexPath **)nextStartingIndexPath
{

    // Within the group enumeration block, filter to enumerate just photos, no videos yet.
    [assetGroup setAssetsFilter:[ALAssetsFilter allPhotos]];
    NSInteger imageCount = [assetGroup numberOfAssets];

    // Make a range of ALL of them, but enumerate in reverse.
    NSInteger lastIndex = imageCount - initialIndexPath.item;
    if (!imageCount || lastIndex < 0) {
        return @[];
    }

    NSRange range = NSMakeRange(0, lastIndex);
    NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:range];

    __block NSUInteger count = 0;
    __block NSUInteger offsetCounter = initialIndexPath.item;

    NSMutableArray *photos = [NSMutableArray array];

    [assetGroup enumerateAssetsAtIndexes:indexes
                                 options:NSEnumerationReverse
                              usingBlock:
     ^(ALAsset *asset, NSUInteger index, BOOL *stop) {
         // The end of the enumeration is signaled by asset == nil.
         if (!asset) {
             // continue;
             return;
         }
         offsetCounter++;

         if (asset.defaultRepresentation.url == nil) {
             return;
         }
         if (![CLScreenshotsLoader assetIsProbablyScreenshot:asset]) {
             // continue;
             return;
         }

         count++;
         [photos addObject:asset];

         BOOL goodStoppingPoint = count >= STOP_LOADING_THRESHOLD;
         if (goodStoppingPoint) {
             // We don't have a matching photo. Potential stopping point.
             *stop = YES;
         }
     }];
    *nextStartingIndexPath = [NSIndexPath indexPathForItem:offsetCounter inSection:0];
    return photos;
}


+ (BOOL) assetIsProbablyScreenshot:(ALAsset *)asset
{

    NSString *filename = [asset.defaultRepresentation.url absoluteString];
    BOOL isPNG = [filename rangeOfString:@".PNG"].location != NSNotFound;
    BOOL isScreenshotDimension = NO;

    if (isPNG) {

        CGSize dimensions = asset.defaultRepresentation.dimensions;
        // Always make the WIDTH < HEIGHT, so we have to do less lookups
        if (dimensions.width > dimensions.height) {
            CGFloat temp = dimensions.width;
            dimensions.width = dimensions.height;
            dimensions.height = temp;
        }

        isScreenshotDimension = [COMMON_IOS_DIMENSIONS containsObject:NSStringFromCGSize(dimensions)];
    }

    return (isPNG && isScreenshotDimension);
}


#pragma mark - PHPHotoLibrary version


+ (BOOL) phAssetIsProbablyScreenshot:(PHAsset *)asset
{
    CGSize dimensions = CGSizeMake(asset.pixelWidth, asset.pixelHeight);
    // Always make the WIDTH < HEIGHT, so we have to do less lookups
    if (dimensions.width > dimensions.height) {
        CGFloat temp = dimensions.width;
        dimensions.width = dimensions.height;
        dimensions.height = temp;
    }

    NSString *sizeString = NSStringFromCGSize(dimensions);
    BOOL isScreenshotDimension = [COMMON_IOS_DIMENSIONS containsObject:sizeString];
    __block BOOL isPNG = NO;
    if (isScreenshotDimension) {
        // Now check if it's a png image
        // The biggest source of false positives from not checking file type is with iPad-sized JPEG images. So do an additional check for them
        // NOTE: This is an expensive operation, and loads the compressed image data into memory, AND fetches from the network.
        // So minimize its use as much as possible (wouldn't be needed if we could see the dataUTI in the asset, or the filename or something)
        BOOL isiPadDimension = [KNOWN_IPAD_DIMENSIONS containsObject:sizeString];
        if (isiPadDimension) {
            [[PHImageManager defaultManager] requestImageDataForAsset:asset options:SCREENSHOT_DATA_REQUEST_OPTIONS resultHandler:^(NSData *imageData, NSString *dataUTI, UIImageOrientation orientation, NSDictionary *info) {
                // For debugging:
                //BOOL isInCloud = [info[PHImageResultIsInCloudKey] boolValue];
                //BOOL isDegraded = [info[PHImageResultIsDegradedKey] boolValue];
                //UIImage *image = nil;
                //if (imageData) {
                //    image = [UIImage imageWithData:imageData];
                //}
                isPNG = [dataUTI isEqualToString:@"public.png"];
            }];
        } else {
            // For non-iPad dimensions let's just assume they are screenshots. We'll have some false positives, like wallpaper images.
            isPNG = YES;
        }
    }

    return isScreenshotDimension && isPNG;
}


+ (void) getScreenshotsStartingAtIndexPath:(NSIndexPath *)initialIndexPath
                             sortAscending:(BOOL)sortAscending
                           completionBlock:(void (^)(NSArray *screenshots, NSIndexPath *nextStartingIndexPath, NSError *error))completionBlock
{
    if (!completionBlock) {
        return;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [CLScreenshotsLoader _getScreenshotsStartingAtIndexPath:initialIndexPath
                                                  sortAscending:sortAscending
                                                completionBlock:
         ^(NSArray *screenshots, NSIndexPath *nextStartingIndexPath, NSError *error) {
             dispatch_async(dispatch_get_main_queue(), ^{
                 completionBlock(screenshots, nextStartingIndexPath, error);
             });

         }];

    });
}


+ (void) _getScreenshotsStartingAtIndexPath:(NSIndexPath *)initialIndexPath
                             sortAscending:(BOOL)sortAscending
                           completionBlock:(void (^)(NSArray *screenshots, NSIndexPath *nextStartingIndexPath, NSError *error))completionBlock
{
    NSMutableArray *screenshotGroups = [NSMutableArray arrayWithCapacity:500];
    NSMutableArray *screenshotAssets = [NSMutableArray arrayWithCapacity:1000];
    // Get moments, and assets within moments
    NSInteger momentOffset = initialIndexPath ? initialIndexPath.section : 0;
    __block NSIndexPath *nextStartingIndexPath = [NSIndexPath indexPathForItem:NSIntegerMax inSection:NSIntegerMax];;

    // Load moment collections (they do the time/location grouping for us)
    NSDate *startTime = [NSDate date];
    PHFetchOptions *momentsOptions = [[PHFetchOptions alloc] init];
    momentsOptions.includeAllBurstAssets = NO;
    momentsOptions.includeHiddenAssets = NO;
    momentsOptions.wantsIncrementalChangeDetails = NO;
    momentsOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"startDate" ascending:sortAscending]];
    PHFetchResult *momentCollections = [PHAssetCollection fetchMomentsWithOptions:momentsOptions];
    //NSLog(@"Retrieved %ld moment collections", momentCollections.count);
    __block NSInteger numPhotosCollected = 0;
    __block NSInteger numScreenshotsCollected = 0;
    NSRange momentCollectionRange = NSMakeRange(momentOffset, momentCollections.count-momentOffset);
    PHFetchOptions *assetFetchOptions = [CLScreenshotsLoader assetFetchOptionsWithSortAscending:sortAscending];
    [momentCollections enumerateObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:momentCollectionRange] options:0 usingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        PHAssetCollection *momentCollection = (PHAssetCollection *)obj;
        //NSLog(@"Retrieved moment collection: %@", momentCollection);

        PHFetchResult *assetsInMomentCollection = [PHAsset fetchAssetsInAssetCollection:momentCollection options:assetFetchOptions];

        NSMutableArray *screenshotsInGroup = [NSMutableArray arrayWithCapacity:assetsInMomentCollection.count];

        [assetsInMomentCollection enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            PHAsset *phAsset = (PHAsset *)obj;
            if ([CLScreenshotsLoader phAssetIsProbablyScreenshot:phAsset]) {
                [screenshotsInGroup addObject:phAsset];
            }
        }];

        numPhotosCollected += assetsInMomentCollection.count;

        if (screenshotsInGroup.count > 0) {
            // No screenshots in that group, so just skip
            [screenshotGroups addObject:screenshotsInGroup];
            [screenshotAssets addObjectsFromArray:screenshotsInGroup];
            numScreenshotsCollected += screenshotsInGroup.count;

            if (numScreenshotsCollected > STOP_LOADING_THRESHOLD) {
                *stop = YES;

                if ((idx+1) < momentCollections.count) {
                    // We have more moment blocks
                    nextStartingIndexPath = [NSIndexPath indexPathForItem:0 inSection:idx+1];
                }
            }
        }

    }];

    NSTimeInterval duration = -[startTime timeIntervalSinceNow];
    CLLog(@"Took %.2fms to fetch %ld photos, (%ld screenshots)", duration*1000.0, (long)numPhotosCollected, (long)numScreenshotsCollected);

    completionBlock(screenshotAssets, nextStartingIndexPath, nil);
}


+ (PHFetchOptions *)assetFetchOptionsWithSortAscending:(BOOL)sortAscending
{
    PHFetchOptions *assetFetchOptions = [[PHFetchOptions alloc] init];
    assetFetchOptions.predicate = [NSPredicate predicateWithFormat:@"mediaType == %d", PHAssetMediaTypeImage];
    assetFetchOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:sortAscending]];
    assetFetchOptions.includeAllBurstAssets = NO;
    assetFetchOptions.includeHiddenAssets = NO;
    assetFetchOptions.wantsIncrementalChangeDetails = NO;

    return assetFetchOptions;
}


@end
