//
//  CLBannerView.m
//  Cluster
//
//  Created by Rizwan Sattar on 3/10/14.
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

#import "CLBannerView.h"

#import <QuartzCore/QuartzCore.h>
#import "UIColor+Hex.h"

@interface CLBannerView ()

@property (strong, nonatomic) CAGradientLayer *gradientLayer;
@property (strong, nonatomic) UILabel *label;

@end

@implementation CLBannerView

- (void)commonInit
{
    _type = CLBannerViewTypeInfo;
    self.gradientLayer = [CAGradientLayer layer];
    [self.layer insertSublayer:self.gradientLayer atIndex:0];
    self.gradientLayer.frame = self.bounds;
    [self updateBannerStyle];

    self.backgroundColor = [UIColor clearColor];

    self.label = [[UILabel alloc] initWithFrame:CGRectZero];
    self.label.textColor = [UIColor whiteColor];
    self.label.backgroundColor = [UIColor clearColor];
    self.label.font = [UIFont systemFontOfSize:15.0];
    self.label.textAlignment = NSTextAlignmentCenter;
    self.label.lineBreakMode = NSLineBreakByTruncatingTail;

    [self addSubview:self.label];
    [self setNeedsLayout];
}

- (id)initWithFrame:(CGRect)frame
{
    frame.size.height = 32;
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)awakeFromNib
{
    [self commonInit];
}


- (void) updateBannerStyle
{
    UIColor *colorTop = [UIColor colorWithRGBHex:0x007aff alpha:1.0];
    UIColor *colorBottom = [UIColor colorWithRGBHex:0x007aff alpha:1.0];
    if (self.type == CLBannerViewTypeError) {
        colorTop = [UIColor colorWithRGBHex:0xCC0000 alpha:0.85];
        colorBottom = [UIColor colorWithRGBHex:0x990000 alpha:0.85];
    }
    self.gradientLayer.colors = @[(id)colorTop.CGColor,
                                  (id)colorBottom.CGColor,
                                  ];
    self.gradientLayer.locations = @[@(0),
                                     @(1)
                                     ];
}


- (void)setType:(CLBannerViewType)type
{
    if (_type == type) {
        return;
    }
    _type = type;
    [self updateBannerStyle];
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    self.gradientLayer.frame = self.bounds;
    CGRect labelFrame = CGRectMake(20, 5, CGRectGetWidth(self.frame)-40, 21);
    self.label.frame = labelFrame;

}

@end
