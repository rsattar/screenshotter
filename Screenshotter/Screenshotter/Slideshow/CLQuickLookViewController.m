//
//  CLQuickLookViewController.m
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

#import "CLQuickLookViewController.h"


@interface CLQuickLookViewController () <UIScrollViewDelegate>

// Just a (UIScrollView *)reference to self.view
@property (weak, nonatomic) UIScrollView *scrollView;

@property (strong, nonatomic) Screenshot *screenshot;
@property (strong, nonatomic) PHAsset *phAsset;

@property (strong, nonatomic) CLScreenshotView *screenshotView;

@property (strong, nonatomic) UITapGestureRecognizer *tapGestureRecognizer;
@property (strong, nonatomic) UITapGestureRecognizer *doubleTapGestureRecognizer;

@end

@implementation CLQuickLookViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
        self.screenshotView = [[CLScreenshotView alloc] initWithFrame:CGRectZero];
        self.screenshotView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.screenshotView.loadFullScreenImage = YES;
        self.tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTapGestureRecognizerFired:)];
        [self.screenshotView addGestureRecognizer:self.tapGestureRecognizer];

        _dismissOnSingleTap = YES;
        self.automaticallyAdjustsScrollViewInsets = NO;
    }
    return self;
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (void)loadView
{
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scrollView.minimumZoomScale = 1.0;
    scrollView.maximumZoomScale = 6.0;
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.delegate = self;

    self.view = scrollView;
    self.scrollView = scrollView;

    self.doubleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onDoubleTapGestureRecognizerFired:)];
    self.doubleTapGestureRecognizer.numberOfTapsRequired = 2;
    self.doubleTapGestureRecognizer.enabled = !_dismissOnSingleTap;
    [self.view addGestureRecognizer:self.doubleTapGestureRecognizer];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	self.view.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.screenshotView];
}


- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (!self.animatingTransition) {
        [self adjustScreenshotViewToFit];
    }
}


- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self adjustScreenshotViewToFit];
    [[Analytics sharedInstance] registerScreen:@"Single Shot"];
}

- (void)adjustScreenshotViewToFit
{
    CGSize originalImageSize = self.screenshotView.imageView.image.size;
    if (!CGSizeEqualToSize(originalImageSize, CGSizeZero)) {
        CGRect screenshotViewFrame = self.screenshotView.frame;
        CGRect bounds = self.scrollView.bounds;

        CGFloat viewAspectRatio = CGRectGetWidth(bounds)/CGRectGetHeight(bounds);
        CGFloat imageAspectRatio = originalImageSize.width/originalImageSize.height;

        if (imageAspectRatio < viewAspectRatio) {
            // Constraint to height
            screenshotViewFrame.size.height = CGRectGetHeight(bounds);
            screenshotViewFrame.size.width = CGRectGetHeight(screenshotViewFrame) * imageAspectRatio;
        } else {
            screenshotViewFrame.size.width = CGRectGetWidth(bounds);
            screenshotViewFrame.size.height = CGRectGetWidth(screenshotViewFrame) / imageAspectRatio;
        }

        self.scrollView.zoomScale = 1.0;
        self.scrollView.contentSize = [self imageSizeWithZoomScale:self.scrollView.zoomScale];

        CGSize scrollFrameSize = bounds.size;
        CGFloat verticalExtra = (scrollFrameSize.height - screenshotViewFrame.size.height) / 2.0;
        CGFloat horizontalExtra = (scrollFrameSize.width - screenshotViewFrame.size.width) / 2.0;
        self.scrollView.contentInset = UIEdgeInsetsMake(verticalExtra, horizontalExtra, verticalExtra, horizontalExtra);
        //NSLog(@"Content inset X: %.1f, Y: %.1f, offset = %@", horizontalExtra, verticalExtra, NSStringFromCGPoint(self.scrollView.contentOffset));

        self.screenshotView.frame = screenshotViewFrame;
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];
    [self adjustScreenshotViewToFit];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    self.scrollView.zoomScale = 1.0;
    [self updateContentSizeWithZoomScale:1.0];
}

- (void)setDismissOnSingleTap:(BOOL)dismissOnSingleTap
{
    _dismissOnSingleTap = dismissOnSingleTap;
    self.tapGestureRecognizer.enabled = _dismissOnSingleTap;
    self.doubleTapGestureRecognizer.enabled = !_dismissOnSingleTap;
}

- (void)onTapGestureRecognizerFired:(id)sender
{
    CLLog(@"User dismissed quicklook");
    [self.delegate quickLookViewControllerDidRequestDismiss:self];
}

- (void)onDoubleTapGestureRecognizerFired:(id)sender
{
    CLLog(@"User double-tapped screenshot");
    if (self.scrollView.zoomScale > self.scrollView.minimumZoomScale) {
        [self.scrollView setZoomScale:self.scrollView.minimumZoomScale animated:YES];
    } else {
        // Default zoom scale == 3
        CGRect zoomRect = [self zoomRectForScale:3.0 withCenter:[self.doubleTapGestureRecognizer locationInView:self.view]];
        [self.scrollView zoomToRect:zoomRect animated:YES];
    }
}

// See: http://stackoverflow.com/a/11003277/9849
- (CGRect)zoomRectForScale:(float)scale withCenter:(CGPoint)center {

    CGRect zoomRect;

    CGSize screenshotViewSize = self.screenshotView.imageView.frame.size;
    zoomRect.size.height = screenshotViewSize.height / scale;
    zoomRect.size.width  = screenshotViewSize.width  / scale;

    center = [self.screenshotView.imageView convertPoint:center fromView:self.view];

    zoomRect.origin.x    = center.x - ((zoomRect.size.width / 2.0));
    zoomRect.origin.y    = center.y - ((zoomRect.size.height / 2.0));

    return zoomRect;
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

#pragma mark - UIScrollViewDelegate


- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    return self.screenshotView;
}

- (void) scrollViewDidZoom:(UIScrollView *)scrollView
{
    UIView *zoomedView = [self viewForZoomingInScrollView:scrollView];
    CGSize zoomedViewSize = zoomedView.bounds.size;
    zoomedViewSize = CGSizeMake(zoomedViewSize.width * scrollView.zoomScale, zoomedViewSize.height * scrollView.zoomScale);
    //CGSize zoomedViewSize = [self imageSizeWithZoomScale:scrollView.zoomScale];
    CGSize containerSize = scrollView.bounds.size;

    CGFloat horizontalInset = MAX(0, containerSize.width - zoomedViewSize.width) / 2.0;
    CGFloat verticalInset = MAX(0, containerSize.height - zoomedViewSize.height) / 2.0;
    scrollView.contentInset = UIEdgeInsetsMake(verticalInset, horizontalInset, verticalInset, horizontalInset);
    //NSLog(@"Content inset X: %.1f, Y: %.1f, offset = %@", horizontalInset, verticalInset, NSStringFromCGPoint(scrollView.contentOffset));
    
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(UIView *)view atScale:(CGFloat)scale
{
    [self updateContentSizeWithZoomScale:scale];
}

- (CGSize)imageSizeWithZoomScale:(CGFloat)scale
{
    // update the content size to be what the scaled image is
    CGSize originalImageSize = self.screenshotView.imageView.image.size;
    CGSize scrollViewSize = self.scrollView.frame.size;

    CGSize scaleDimensions = CGSizeMake(scrollViewSize.width/originalImageSize.width, scrollViewSize.height/originalImageSize.height);
    CGFloat singleDimensionScale = -1.0;
    switch (self.screenshotView.imageView.contentMode) {
        case UIViewContentModeScaleAspectFit:
            singleDimensionScale = MIN(scaleDimensions.width, scaleDimensions.height);
            break;
        case UIViewContentModeScaleAspectFill:
            singleDimensionScale = MAX(scaleDimensions.width, scaleDimensions.height);
        default:
            break;
    }
    if (singleDimensionScale >= 0.0) {
        scaleDimensions = CGSizeMake(singleDimensionScale, singleDimensionScale);
    }
    CGSize scaledImageSize = CGSizeMake(originalImageSize.width*scaleDimensions.width, originalImageSize.height*scaleDimensions.height);

    CGSize zoomedImageSize = CGSizeMake(scaledImageSize.width*scale, scaledImageSize.height*scale);
    return zoomedImageSize;
}

- (void)updateContentSizeWithZoomScale:(CGFloat)scale
{
    // Ensure our content size isn't smaller than our viewport, otherwise the scroll offset would jump
    CGSize zoomedImageSize = [self imageSizeWithZoomScale:scale];
    CGSize contentSize = zoomedImageSize;//CGSizeMake(MAX(scrollViewSize.width, zoomedImageSize.width), MAX(scrollViewSize.height, zoomedImageSize.height));

    self.scrollView.contentSize = contentSize;
}


@end
