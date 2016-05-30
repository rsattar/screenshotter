//
//  SimpleWebViewController.h
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


@class SimpleWebViewController;
@protocol SimpleWebViewControllerDelegate <NSObject>

- (void) simpleWebViewControllerDidRequestDismiss:(SimpleWebViewController *)controller;

@end



@interface SimpleWebViewController : UIViewController <UIWebViewDelegate, UIAlertViewDelegate>

@property (weak, nonatomic) NSObject <SimpleWebViewControllerDelegate> *delegate;

- (id) initWithTitle:(NSString*)title andURL:(NSURL*)URL;

@end
