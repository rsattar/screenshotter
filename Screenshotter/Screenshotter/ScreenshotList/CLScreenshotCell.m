//
//  CLScreenshotCell.m
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

#import "CLScreenshotCell.h"

#import "CLScreenshotView.h"
#import "UIColor+Hex.h"

@interface CLScreenshotCell ()

@property (strong, nonatomic) Screenshot *screenshot;
@property (strong, nonatomic) PHAsset *phAsset;

@property (strong, nonatomic) CLScreenshotView *screenshotView;
@property (strong, nonatomic) UIImageView *selectedImageView;

@end

@implementation CLScreenshotCell

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
        self.screenshotView = [[CLScreenshotView alloc] initWithFrame:self.contentView.bounds];
        [self.contentView addSubview:self.screenshotView];
        self.screenshotView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        self.selectedImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"SelectedIcon"]];
        self.selectedImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView insertSubview:self.selectedImageView aboveSubview:self.screenshotView];
        NSLayoutConstraint *bottomConstraint =
        [NSLayoutConstraint constraintWithItem:self.selectedImageView
                                     attribute:NSLayoutAttributeBottom
                                     relatedBy:NSLayoutRelationEqual
                                        toItem:self.contentView
                                     attribute:NSLayoutAttributeBottom
                                    multiplier:1.0
                                      constant:0.0];
        NSLayoutConstraint *rightConstraint =
        [NSLayoutConstraint constraintWithItem:self.selectedImageView
                                     attribute:NSLayoutAttributeTrailing
                                     relatedBy:NSLayoutRelationEqual
                                        toItem:self.contentView
                                     attribute:NSLayoutAttributeTrailing
                                    multiplier:1.0
                                      constant:0.0];
        [self.contentView addConstraints:@[bottomConstraint, rightConstraint]];
        self.selectedImageView.hidden = YES;
    }
    return self;
}


- (void)prepareForReuse
{
    [super prepareForReuse];
    [self.screenshotView prepareForReuse];
}


- (void)setScreenshot:(Screenshot *)screenshot andAsset:(PHAsset *)phAsset
{
    _screenshot = screenshot;
    _phAsset = phAsset;
    [self.screenshotView setScreenshot:_screenshot andAsset:_phAsset];
}


- (void)setScreenshotFile:(ScreenshotFileInfo *)screenshotFile loadImmediately:(BOOL)loadImmediately
{
    _screenshotFile = screenshotFile;
    [self.screenshotView setScreenshotFile:screenshotFile loadImmediately:loadImmediately];
}


- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];

    self.screenshotView.imageView.alpha = selected ? 0.7 : 1.0;
    self.screenshotView.backgroundColor = selected ? [UIColor colorWithRGBHex:0x007aff] : [UIColor clearColor];
    if (selected) {
        self.selectedImageView.hidden = NO;
    } else if (!selected) {
        self.selectedImageView.hidden = YES;
    }
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect
{
    // Drawing code
}
*/

@end
