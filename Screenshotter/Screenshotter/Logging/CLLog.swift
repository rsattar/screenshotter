//
//  CLLog.swift
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

import Foundation

// Used by Swift because CLLog() (in ClusterLogging.h) is not available from Objective-C
func CLLog(msg:String, file:String=#file, method:String=#function, line:Int=#line, column:Int=#column) {
    ClusterLogging.log(msg, fromFile: file, method: method, line: line, column:column)
}