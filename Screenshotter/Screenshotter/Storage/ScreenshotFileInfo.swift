//
//  ScreenshotFileInfo.swift
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
import ImageIO

/** Essentially represents an NSMetadataItem of a file */
public class ScreenshotFileInfo: NSObject {
    public internal(set) var fileUrl:NSURL = NSURL()
    public private(set) var creationDate:NSDate = NSDate()

    public var fileName:NSString {
        return self.fileUrl.lastPathComponent!
    }

    public private(set) var storedIniCloud:Bool = true

    // Mainly iCloud related (will not be set for local files)
    public private(set) var hasiCloudConflict:Bool = false
    public private(set) var isDownloading:Bool = false
    public private(set) var isUploaded:Bool = true
    public private(set) var isUploading:Bool = false
    public private(set) var percentDownloaded:Double = 100.0
    public private(set) var percentUploaded:Double = 100.0
    public private(set) var downloadingStatus:NSString = NSMetadataUbiquitousItemDownloadingStatusCurrent
    public private(set) var downloadingError:NSError?
    public private(set) var uploadingError:NSError?

    // Actually related to screenshots (the rest is basically file-info)
    private var calculatedImageDimensions:CGSize?

    init(fromMetadataItem item:NSMetadataItem) {

        self.fileUrl = item.valueForAttribute(NSMetadataItemURLKey) as! NSURL
        self.creationDate = item.valueForAttribute(NSMetadataItemFSCreationDateKey) as! NSDate

        self.storedIniCloud = (item.valueForAttribute(NSMetadataItemIsUbiquitousKey) as! NSNumber).boolValue

        if (self.storedIniCloud) {
            // Get the icloud-y things
            self.hasiCloudConflict = (item.valueForAttribute(NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as! NSNumber).boolValue
            if let downloadingNumber = item.valueForAttribute(NSMetadataUbiquitousItemIsDownloadingKey) as? NSNumber {
                self.isDownloading = downloadingNumber.boolValue
            }
            if let uploadedNum = item.valueForAttribute(NSMetadataUbiquitousItemIsUploadedKey) as? NSNumber {
                self.isUploaded = uploadedNum.boolValue
            }
            if let uploadingNum = item.valueForAttribute(NSMetadataUbiquitousItemIsUploadingKey) as? NSNumber {
                self.isUploading = uploadingNum.boolValue
            }
            if let percentDownloadedNum = item.valueForAttribute(NSMetadataUbiquitousItemPercentDownloadedKey) as? NSNumber {
                self.percentDownloaded = percentDownloadedNum.doubleValue
            }
            if let percentUploadedNum = item.valueForAttribute(NSMetadataUbiquitousItemPercentUploadedKey) as? NSNumber {
                self.percentUploaded = percentUploadedNum.doubleValue
            }
            if let downloadingStatus = item.valueForAttribute(NSMetadataUbiquitousItemDownloadingStatusKey) as? NSString {
                self.downloadingStatus = downloadingStatus
            }
            self.downloadingError = item.valueForAttribute(NSMetadataUbiquitousItemDownloadingErrorKey) as? NSError
            self.uploadingError = item.valueForAttribute(NSMetadataUbiquitousItemUploadingErrorKey) as? NSError
        }
    }

    init(fromFileUrl fileUrl:NSURL) {
        self.fileUrl = fileUrl
        var maybeValue:AnyObject? = nil
        do {
            try self.fileUrl.getResourceValue(&maybeValue, forKey: NSURLCreationDateKey)
            self.creationDate = (maybeValue! as! NSDate)
        } catch {

        }
    }

    public func imageDimensions() -> CGSize {
        if let validDimensions = self.calculatedImageDimensions {
            return validDimensions
        }
        // we have to calculate
        self.calculatedImageDimensions = ScreenshotFileInfo.imageDimensionsFromFileAtUrl(self.fileUrl)

        return self.calculatedImageDimensions!
    }

    public class func imageDimensionsFromFileAtUrl(fileUrl:NSURL) -> CGSize {

        var pixelWidth:Double = 0.0
        var pixelHeight:Double = 0.0

        let pathExtension = fileUrl.pathExtension!.lowercaseString
        var dataUTI:String = "public.png"
        if (pathExtension.hasSuffix("jpg") || pathExtension.hasSuffix("jpeg")) {
            dataUTI = "public.jpeg"
        }
        let options: [NSString : NSString] = [kCGImageSourceTypeIdentifierHint : dataUTI]

        let imageSource = CGImageSourceCreateWithURL(fileUrl, options)
        if let imageSource = imageSource, properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, options) as? NSDictionary {
            // properties is basically the EXIF dict, and has 'PixelWidth', 'PixelHeight' entries
            let widthNumber:NSNumber? = properties["PixelWidth"] as? NSNumber
            let heightNumber:NSNumber? = properties["PixelHeight"] as? NSNumber
            if (widthNumber != nil) {
                pixelWidth = widthNumber!.doubleValue
            }
            if (heightNumber != nil) {
                pixelHeight = heightNumber!.doubleValue
            }
        } else {
            // This file might have been deleted, or is not a valid image
            CLLog("Couldn't extract image dimensions for file at: \(fileUrl)")
        }
        return CGSizeMake(CGFloat(pixelWidth), CGFloat(pixelHeight))
    }

    override public var description: String {
        var desc:String = self.fileUrl.lastPathComponent!
        if (self.isDownloading) {
            desc += " (Downloading \(self.percentDownloaded)%)"
        }
        if (self.isUploading) {
            desc += " (Uploading \(self.percentUploaded)%)"
        }
        desc += " - (\(super.description))"
        return desc
    }
}
