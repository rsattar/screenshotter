//
//  CLScreenshotsLoader.h
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

#import <Foundation/Foundation.h>

#import <AssetsLibrary/AssetsLibrary.h>
#import <Photos/Photos.h>

@interface CLScreenshotsLoader : NSObject

+ (ALAssetsLibrary *) assetsLibrary;
+ (void) getScreenshotsInAssetsGroup:(ALAssetsGroup *)assetsGroup
                 startingAtIndexPath:(NSIndexPath *)initialIndexPath
                  excludingAssetURLs:(NSSet *)excludeAssetURLs
                     completionBlock:(void (^)(NSArray *screenshots, NSIndexPath *nextStartingIndexPath, NSError *error))completionBlock;
+ (void) getScreenshotsStartingAtIndexPath:(NSIndexPath *)initialIndexPath
                             sortAscending:(BOOL)sortAscending
                           completionBlock:(void (^)(NSArray *screenshots, NSIndexPath *nextStartingIndexPath, NSError *error))completionBlock;
+ (BOOL) phAssetIsProbablyScreenshot:(PHAsset *)asset;
@end
