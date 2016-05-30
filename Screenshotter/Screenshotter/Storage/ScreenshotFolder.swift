//
//  ScreenshotFolder.swift
//  Screenshotter
//
//  Created by Rizwan Sattar on 10/8/14.
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

import UIKit

public class ScreenshotFolder: NSObject {

    public internal(set) var folderUrl : NSURL = NSURL()
    public internal(set) var folderName : NSString = ""
    public var files: [ScreenshotFileInfo] = []
    public var count : Int {
        return self.files.count
    }

    init(folderUrl:NSURL) {
        self.folderUrl = folderUrl
        self.folderName = self.folderUrl.lastPathComponent!
    }

    init(folderUrl:NSURL, files:[ScreenshotFileInfo]) {
        self.folderUrl = folderUrl
        self.folderName = self.folderUrl.lastPathComponent!
        self.files = files
    }

    override public var description: String {
        return "\(self.folderName) (Count: \(self.files.count)) - (\(super.description))"
    }
}
