//
//  ScreenshotDocument.swift
//  Screenshotter
//
//  Created by Rizwan Sattar on 10/7/14.
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

enum ScreenshotDocumentError: ErrorType {
    case InvalidContents(receivedContents: AnyObject)
}

public class ScreenshotDocument: UIDocument {

    public var image:UIImage?
    public var data:NSData

    public var creationDate:NSDate?

    override init(fileURL url: NSURL) {
        // Must declare our own properties before calling super.init
        // See: http://stackoverflow.com/a/24021346/9849
        self.data = NSData()
        super.init(fileURL:url)
    }

    override public func loadFromContents(contents: AnyObject, ofType typeName: String?) throws {
        if (contents is NSData) {
            self.data = contents as! NSData
            self.image = UIImage(data: self.data)
        }
        throw ScreenshotDocumentError.InvalidContents(receivedContents: contents)
    }

    override public func contentsForType(typeName: String) throws -> AnyObject {
        if (self.data.length == 0) {
            if let validImage = self.image, dataFromImage = UIImagePNGRepresentation(validImage) {
                // Recreate it from our image
                self.data = dataFromImage
            }
        }
        return self.data
    }

    override public func fileAttributesToWriteToURL(url: NSURL, forSaveOperation saveOperation: UIDocumentSaveOperation) throws -> [NSObject : AnyObject] {
        // Include a thumbnail of the screenshot
        if (self.data.length > 0) {
            if (self.image == nil) {
                self.image = UIImage(data: self.data)
            }
            var fileAttributes:[NSObject : AnyObject] = [NSURLThumbnailDictionaryKey : [NSThumbnail1024x1024SizeKey : self.image!]]
            if (self.creationDate != nil) {
                fileAttributes[NSURLCreationDateKey] = self.creationDate!
            }
            return fileAttributes
        }
        return [:]
    }

    override public func hasUnsavedChanges() -> Bool {
        let hasChanges = super.hasUnsavedChanges();
        return hasChanges;
    }
}