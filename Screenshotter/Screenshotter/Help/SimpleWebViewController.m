//
//  SimpleWebViewController.m
//  Cluster
//
//  Created by Taylor Hughes on 1/30/13.
//  Copyright (c) 2013 Cluster Labs, Inc. All rights reserved.
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

#import "SimpleWebViewController.h"


@interface SimpleWebViewController ()

@property (strong, nonatomic) NSURL *URL;

@property (strong, nonatomic) UIWebView *webView;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;

@end


@implementation SimpleWebViewController


- (id) initWithTitle:(NSString*)title andURL:(NSURL*)URL
{
    self = [super init];
    if (self) {
        self.title = title;
        self.URL = URL;
        
        self.webView = [[UIWebView alloc] initWithFrame:CGRectMake(0, 0, 320.0, 480.0)];
        self.webView.delegate = self;

        self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        self.spinner.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        self.view = self.webView;
    }
    return self;
}


- (void) viewWillAppear:(BOOL)animated
{
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:self.URL];
    [self.webView loadRequest:request];
    
    //self.navigationItem.title = self.title;
    if (self.navigationController.viewControllers.count == 1) {
        UIBarButtonItem *button = [[UIBarButtonItem alloc] initWithTitle:@"Close"
                                                                   style:UIBarButtonItemStylePlain
                                                                  target:self
                                                                  action:@selector(dismiss:)];
        self.navigationItem.leftBarButtonItem = button;
    }

    if (!self.spinner.superview) {
        [self.view insertSubview:self.spinner belowSubview:self.webView];
        self.spinner.center = self.view.center;
    }
    [self.spinner startAnimating];
}


- (void) webViewDidStartLoad:(UIWebView *)webView
{
}


- (void) webViewDidFinishLoad:(UIWebView *)webView
{
    [self.spinner stopAnimating];
    [self.spinner removeFromSuperview];
}


- (void) webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    NSString *message = [NSString stringWithFormat:@"Couldn't load this content for some reason. (%@)", [error localizedDescription]];
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Whoops!"
                                                    message:message
                                                   delegate:self
                                          cancelButtonTitle:nil
                                          otherButtonTitles:@"Dismiss", nil];
    [alert show];
}


- (void) dismiss:(id)sender
{
    if (self.delegate) {
        [self.delegate simpleWebViewControllerDidRequestDismiss:self];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}


- (void) alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    [self dismiss:alertView];
}


@end
