//
//  CLScreenshotView.m
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

#import "CLScreenshotView.h"

#import "CLScreenshotterApplication.h"
#import <Photos/Photos.h>
#import <SDImageCache.h>

static PHFetchOptions *screenshotViewAssetFetchOptions;
static PHImageRequestOptions *screenshotViewImageRequestOptions;

static BOOL const CLEAR_SCREENSHOT_FILE_IMAGE_CACHE_ON_START = YES;
static NSOperationQueue *screenshotFileLoadingQueue;

@interface CLScreenshotView ()

@property (strong, nonatomic) Screenshot *screenshot;
@property (strong, nonatomic) PHAsset *phAsset;

@property (strong, nonatomic) UIImageView *imageView;

@property (assign, nonatomic) PHImageRequestID previousImageRequestId;
@property (strong, nonatomic) NSOperation *cacheLookupOperation;
@property (strong, nonatomic) NSString *previousScreenshotFileCacheURL;

@end

@implementation CLScreenshotView

+ (void)initialize
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        screenshotFileLoadingQueue = [[NSOperationQueue alloc] init];
        screenshotFileLoadingQueue.name = @"ScreenshotFileInfo Image Queue";
        screenshotFileLoadingQueue.maxConcurrentOperationCount = 4;

        if (CLEAR_SCREENSHOT_FILE_IMAGE_CACHE_ON_START) {
            [[SDImageCache sharedImageCache] clearMemory];
            [[SDImageCache sharedImageCache] clearDisk];
        }
    });
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
        self.backgroundColor = [UIColor clearColor];
        self.imageView = [[UIImageView alloc] initWithFrame:self.bounds];
        self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.imageView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:self.imageView];
    }
    return self;
}


- (void)dealloc
{
    [self prepareForReuse];
    self.cacheLookupOperation = nil;
}


- (void)prepareForReuse
{
    [self.cacheLookupOperation cancel];
    self.previousScreenshotFileCacheURL = nil;
    self.imageView.image = nil;
    _screenshot = nil;
    _phAsset = nil;
    _screenshotFile = nil;
}


- (void)setScreenshot:(Screenshot *)screenshot andAsset:(PHAsset *)phAsset
{
    if ([_screenshot.localAssetURL isEqualToString:screenshot.localAssetURL]) {
        return;
    }
    _screenshotFile = nil;
    _screenshot = screenshot;
    _phAsset = phAsset;

    if (_screenshot == nil) {
        CLLog(@"CLScreenshotView received nil screenshot, asset = %@. Not setting the image view", phAsset);
        self.imageView.image = nil;
        self.imageView.backgroundColor = [UIColor colorWithRGBHex:0xF5F5F5];
        return;
    }

    NSURL *assetURL = nil;
    if ([_screenshot.localAssetURL hasPrefix:@"assets-library://"]) {
        assetURL = [NSURL URLWithString:_screenshot.localAssetURL];
    }

    __weak CLScreenshotView *_weakSelf = self;

    // Cancel any previous image request id we may have
    [[PHImageManager defaultManager] cancelImageRequest:self.previousImageRequestId];

    if (!_phAsset) {
        // We need the asset first

        if (!screenshotViewAssetFetchOptions) {
            screenshotViewAssetFetchOptions = [[PHFetchOptions alloc] init];
            screenshotViewAssetFetchOptions.wantsIncrementalChangeDetails = NO;
            screenshotViewAssetFetchOptions.includeAllBurstAssets = NO;
            screenshotViewAssetFetchOptions.includeHiddenAssets = YES;
        }
        PHFetchResult *assets = nil;
        if (assetURL) {
            assets = [PHAsset fetchAssetsWithALAssetURLs:@[assetURL] options:screenshotViewAssetFetchOptions];
        } else {
            // Asset is a string
            NSString *localIdentifier = _screenshot.localAssetURL;
            if (localIdentifier.length == 0) {
                CLLog(@"CLScreenshotView: localIdentifier from screenshot was nil, skipping");
                self.imageView.image = nil;
                self.imageView.backgroundColor = [UIColor colorWithRGBHex:0xF5F5F5];
                return;
            }
            assets = [PHAsset fetchAssetsWithLocalIdentifiers:@[localIdentifier] options:screenshotViewAssetFetchOptions];
        }
        if (assets.count > 0) {
            _phAsset = assets.lastObject;
        }
    }

    self.imageView.backgroundColor = [UIColor clearColor];

    if (!screenshotViewImageRequestOptions) {
        screenshotViewImageRequestOptions = [[PHImageRequestOptions alloc] init];
        screenshotViewImageRequestOptions.synchronous = NO;
        screenshotViewImageRequestOptions.networkAccessAllowed = YES;
        screenshotViewImageRequestOptions.version = PHImageRequestOptionsVersionCurrent;
    }
    CGSize desiredSize = CGSizeMake(256, 256);
    if (self.loadFullScreenImage) {
        CGSize fullscreensize = [UIScreen mainScreen].bounds.size;
        CGFloat maxDimension = MAX(fullscreensize.width, fullscreensize.height);
        desiredSize = CGSizeMake(maxDimension, maxDimension);
    }
    self.previousImageRequestId = [[PHImageManager defaultManager] requestImageForAsset:_phAsset targetSize:desiredSize contentMode:PHImageContentModeAspectFit options:screenshotViewImageRequestOptions resultHandler:^(UIImage *result, NSDictionary *info) {
        _weakSelf.imageView.image = result;
    }];
}

- (void) setScreenshotFile:(ScreenshotFileInfo *)screenshotFile loadImmediately:(BOOL)loadImmediately
{
    if ([_screenshotFile.fileUrl isEqual:screenshotFile.fileUrl] && self.imageView.image != nil) {
        return;
    }
    _screenshotFile = screenshotFile;
    _screenshot = nil;
    _phAsset = nil;

    [self.cacheLookupOperation cancel];


    CGSize currentSize = self.bounds.size;
    NSURL *cacheFileURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@&creationDate=%f&width=%.0f",
                                                _screenshotFile.fileUrl.absoluteString,
                                                _screenshotFile.creationDate.timeIntervalSince1970,
                                                currentSize.width]];
    if ([self.previousScreenshotFileCacheURL isEqual:cacheFileURL]) {
        return;
    }

    __weak CLScreenshotView *_weakSelf = self;
    /*
    ScreenshotDocument *imageDoc = [[ScreenshotDocument alloc] initWithFileURL:_screenshotFile.fileUrl];

    [imageDoc openWithCompletionHandler:^(BOOL success) {
        if (![imageDoc.fileURL isEqual:_weakSelf.screenshotFile.fileUrl]) {
            return;
        }

        _weakSelf.imageView.image = imageDoc.image;
    }];
    */

    // See if we have this exact image in cache already.
    _weakSelf.cacheLookupOperation = [[SDImageCache sharedImageCache] queryDiskCacheForKey:cacheFileURL.absoluteString done:^(UIImage *image, SDImageCacheType cacheType) {
        NSOperation *cacheLookupOperation = _weakSelf.cacheLookupOperation;
        _weakSelf.cacheLookupOperation = nil;
        if (cacheLookupOperation.cancelled) {
            return;
        }
        if (image) {
            _weakSelf.imageView.image = image;
        } else {
            // TODO(Riz): If same image is being retrieved, save the completion block, and
            // don't schedule another retrieve, and call the completion blocks at once
            if (loadImmediately) {
                UIImage *image = [UIImage imageWithContentsOfFile:_screenshotFile.fileUrl.path];
                _weakSelf.imageView.image = image;
                [[SDImageCache sharedImageCache] storeImage:image forKey:cacheFileURL.absoluteString];
                return;
            }

            // Othewise we load asynchronously
            _weakSelf.previousScreenshotFileCacheURL = [cacheFileURL copy];
            [screenshotFileLoadingQueue addOperationWithBlock:^{
                // Do every check possible to avoid unnecessary loading haha
                if (!_weakSelf) {
                    return;
                }
                if (![_weakSelf.previousScreenshotFileCacheURL isEqual:cacheFileURL]) {
                    return;
                }
                if (![_weakSelf.screenshotFile.fileUrl isEqual:screenshotFile.fileUrl]) {
                    return;
                }

                UIImage *image = nil;

                NSMutableDictionary *options = [NSMutableDictionary dictionaryWithCapacity:5];
                options[(NSString *)kCGImageSourceShouldCache] = @(YES);
                options[(NSString *)kCGImageSourceCreateThumbnailFromImageIfAbsent] = @(YES);
                CGFloat scale = [UIScreen mainScreen].scale;
                if (currentSize.width > 0 || currentSize.height > 0) {
                    options[(NSString *)kCGImageSourceThumbnailMaxPixelSize] = @(scale * MAX(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds)));
                }
                CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)_screenshotFile.fileUrl, (CFDictionaryRef)options);

                if (source != NULL) {
                    CGImageRef cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, (CFDictionaryRef)options);
                    if (cgImage) {
                        image = [UIImage imageWithCGImage:cgImage];
                    }
                    CFRelease(cgImage);
                }
                CFRelease(source);

                if (image == nil) {
                    image = [UIImage imageWithContentsOfFile:_weakSelf.screenshotFile.fileUrl.path];
                }
                [[SDImageCache sharedImageCache] storeImage:image forKey:cacheFileURL.absoluteString];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (![_weakSelf.screenshotFile.fileUrl isEqual:screenshotFile.fileUrl]) {
                        return;
                    }
                    _weakSelf.imageView.image = image;
                });

            }];
        }
    }];
}
@end
