//
//  CLScreenshotTagCell.m
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

#import "CLScreenshotTagCell.h"
#import "UIColor+Hex.h"

@implementation CLScreenshotTagCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIdentifier];
    if (self) {
        // Initialization code
        self.folderCellStyle = CLScreenshotFolderCellStyleDefault;
    }
    return self;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}


- (void)prepareForReuse
{
    [super prepareForReuse];
    self.folderCellStyle = CLScreenshotFolderCellStyleDefault;
}


- (void)setFolderCellStyle:(CLScreenshotFolderCellStyle)folderCellStyle
{
    _folderCellStyle = folderCellStyle;

    CGFloat textLabelSize = 30.0;
    CGFloat detailTextLabelSize = 28.0;
    UIColor *detailTextColor = [UIColor colorWithRGBHex:0x007aff];
    if (_folderCellStyle == CLScreenshotFolderCellStyleCompact) {
        textLabelSize = 22.0;
        detailTextLabelSize = 20.0;
        detailTextColor = [UIColor lightGrayColor];
    }

    self.textLabel.font = [UIFont fontWithName:@"HelveticaNeue-Thin" size:textLabelSize];
    self.detailTextLabel.font = [UIFont fontWithName:@"HelveticaNeue-Thin" size:detailTextLabelSize];
    self.detailTextLabel.textColor = detailTextColor;
}


- (void) layoutSubviews
{
    [super layoutSubviews];

    CGRect bounds = self.contentView.bounds;
    CGFloat additionalRightPadding = 0.0;
    // Ugh.. hardcoding
    if (self.accessoryType == UITableViewCellAccessoryNone) {
        // We need to add some additional padding
        additionalRightPadding = 28.0;
    } else if (self.editing) {
        // Editing, with an accessory type that isn't currently visible
        additionalRightPadding = 38.0;
    }
    CGRect textLabelFrame = self.textLabel.frame;
    CGRect detailLabelFrame = self.detailTextLabel.frame;

    // Make sure our
    CGSize measuredDetailText = [self.detailTextLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    detailLabelFrame.size.width = MAX(measuredDetailText.width, CGRectGetWidth(detailLabelFrame));
    // Ensure detailTextLabel is accounted for, and then shrink textlabel if need be.
    // By default iOS seems to favor letting textLabel be as wide as the cell, sacrificing the detail text
    detailLabelFrame.origin.x = CGRectGetWidth(bounds) - CGRectGetWidth(detailLabelFrame) - additionalRightPadding;
    if (CGRectGetMaxX(textLabelFrame) > CGRectGetMinX(detailLabelFrame)) {
        textLabelFrame.size.width = CGRectGetMinX(detailLabelFrame) - CGRectGetMinX(textLabelFrame);
    }

    detailLabelFrame.origin.y -= 3.0;
    self.textLabel.frame = textLabelFrame;
    self.detailTextLabel.frame = detailLabelFrame;
}

@end
