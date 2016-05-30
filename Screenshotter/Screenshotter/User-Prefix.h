//
//  User-Prefix.h
//  Screenshotter
//
//  Created by Rizwan Sattar on 11/11/14.
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

//
// Prefix header for setting up user-specific constants, etc.
//

#import "ClusterLogging.h"

// These following #defines let us define many consts quickly, one for "phone" and one for "pad" idioms
// They result in a const named as the non-idiom-specific part of term, and having the right value

#define DeclareConstByIdiom(type, prefix, phoneValue, padValue) \
static type prefix;\
static type const prefix##_PHONE = phoneValue;\
static type const prefix##_PAD = padValue;

#define ImplementConstByIdiom(prefix)\
prefix = [ClusterApplication isPad] ? prefix##_PAD : prefix##_PHONE;