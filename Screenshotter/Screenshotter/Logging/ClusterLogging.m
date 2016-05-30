//
//  ClusterLogging.m
//  Screenshotter
//
//  Created by Rizwan Sattar on 11/18/14.
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

#import "ClusterLogging.h"

@implementation ClusterLogging


+ (void) log:(NSString *)msg fromFile:(NSString *)file method:(NSString *)method line:(NSInteger)line column:(NSInteger)column
{
#ifdef DEBUG
    NSLog(@"%@", msg);
    //CLSNSLog(@"%@->%@ line %ld col %ld $ %@", file, method, (long)line, (long)column, msg);
#else
    NSLog(@"%@->%@ line %ld col %ld $ %@", file, method, (long)line, (long)column, msg);
#endif
}

@end