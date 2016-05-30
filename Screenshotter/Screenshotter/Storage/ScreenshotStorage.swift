//
//  ScreenshotStorage.swift
//  Screenshotter
//
//  Created by Rizwan Sattar on 9/16/14.
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
import Photos

private let USER_DESIRE_TO_USE_ICLOUD_KEY = "userDesireToUseiCloud"
private let LAST_USED_ICLOUD_TOKEN_KEY = "lastUsediCloudToken"

private let LOG_SCREENSHOTS_WHEN_UPDATING = false
private let LOG_ELAPSED_TIME = false
private let LOG_UBIQUITY_URL_REQUESTED_FROM_MAIN_THREAD = false

public class ScreenshotStorage: NSObject {

    // TODO: Needs to be made into class const
    public let DOCUMENTS_WERE_UPDATED_NOTIFICATION = "documentsWereUpdated"

    var lastiCloudToken : AnyObject?
    var currentiCloudToken : AnyObject?

    var listeningForiCloudChanges : Bool = false
    // Very helpful: https://developer.apple.com/library/ios/documentation/DataManagement/Conceptual/DocumentBasedAppPGiOS/ManageDocumentLifeCycle/ManageDocumentLifeCycle.html#//apple_ref/doc/uid/TP40011149-CH4-SW6
    let filesQuery : NSMetadataQuery

    // [iCloudContainer]/Documents/
    var _ubiquityDocumentsUrl:NSURL?
    var ubiquityDocumentsUrl: NSURL? {
        if _ubiquityDocumentsUrl == nil {
            if LOG_UBIQUITY_URL_REQUESTED_FROM_MAIN_THREAD {
                let isMainThread = NSThread.isMainThread()
                if (isMainThread) {
                    CLLog("Warning: URLForUbiquityContainerIdentifier being called from main thread")
                }
            }
            // Note: URLForUbiquityContainerIdentifier: also *activates* iCloud Drive folder if running for the first time
            // See: http://stackoverflow.com/questions/25203697/exposing-an-apps-ubiquitous-container-to-icloud-drive-in-ios-8

            // Specifying nil for the identifier returns the first container listed in
            // the com.apple.developer.ubiquity-container-identifiers entitlement array.
            _ubiquityDocumentsUrl = NSFileManager.defaultManager().URLForUbiquityContainerIdentifier(nil)?.URLByAppendingPathComponent("Documents");
        }
        return _ubiquityDocumentsUrl
    }

    // [AppSandbox]/Documents/Screenshots/
    let localScreenshotsUrl : NSURL?

    let dateFormatter: NSDateFormatter

    var iCloudAvailable = true
    var iCloudEnabled:Bool {
        return self.iCloudAvailable && (ScreenshotStorage.iCloudUsagePermissionState == .ShouldUse)
    }
    var _iCloudDrivePossiblyNotAvailable = false
    var iCloudDrivePossiblyNotAvailable: Bool {
        return _iCloudDrivePossiblyNotAvailable
    }

    @objc
    class var iCloudUsagePermissionState : UsagePermissionState {
        get {
            if let stringValue = NSUserDefaults.standardUserDefaults().stringForKey(USER_DESIRE_TO_USE_ICLOUD_KEY) {
                if stringValue == "ShouldUse" {
                    return .ShouldUse
                } else if (stringValue == "ShouldNotUse") {
                    return .ShouldNotUse
                }
            }
            return .NotDetermined
        }
        set {
            var stringToWrite:String = "NotDetermined"
            if (newValue == .ShouldUse) {
                stringToWrite = "ShouldUse"
            } else if (newValue == .ShouldNotUse) {
                stringToWrite = "ShouldNotUse"
            }
            NSUserDefaults.standardUserDefaults().setObject(stringToWrite, forKey: USER_DESIRE_TO_USE_ICLOUD_KEY)
            NSUserDefaults.standardUserDefaults().synchronize()
        }
    }

    // WTF: http://konstantinkoval.github.io/posts/swift-public-property-with-private-setter/
    public private(set) var screenshotFolders = [ScreenshotFolder]()
    public private(set) var screenshotFoldersByFolderName = [NSString : ScreenshotFolder]()
    public private(set) var screenshotFilesByFolderName = [NSString : [ScreenshotFileInfo]]()

    class var sharedInstance : ScreenshotStorage {
    struct Static {
        static let instance: ScreenshotStorage = ScreenshotStorage()
        }
        return Static.instance
    }

    override init() {
        self.dateFormatter = NSDateFormatter()
        // E.g. Screen Shot 2014-09-26 at 3.00.05 PM.PNG
        self.dateFormatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"

        self.filesQuery = NSMetadataQuery()
        self.filesQuery.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]

        if let documentsUrl = try? NSFileManager.defaultManager().URLForDirectory(.DocumentDirectory,
                                                                                  inDomain: .UserDomainMask,
                                                                                  appropriateForURL: nil,
                                                                                  create: false) {
            // Put local screenshots inside /Documents/Screenshots/ if not under iCloud
            self.localScreenshotsUrl = documentsUrl.URLByAppendingPathComponent("Screenshots")
        } else {
            self.localScreenshotsUrl = nil
        }

        super.init()

        // Always listen for changes to iCloud availability
        self.updateCurrentiCloudToken()
    }

    deinit {
        self.stopListeningForiCloudFileChanges()

        if (self.listeningForiCloudChanges) {
            NSNotificationCenter.defaultCenter().removeObserver(self,
                                                                name: NSUbiquityIdentityDidChangeNotification,
                                                                object: nil)
            self.listeningForiCloudChanges = false
        }
    }

    func updateToCurrentStorageOption() {
        self.createScreenshotDocumentsFolderIfNeededWithCompletion { (error) -> Void in
            if error == nil {
                if self.iCloudEnabled {
                    self.startListeningForiCloudFileChanges()
                } else {
                    self.updateScreenshotFoldersAndFilesIfNeeded()
                }
            }
        }
    }

    func updateCurrentiCloudToken() {
        NSLog("Updating to current iCloud token")
        let defaults = NSUserDefaults.standardUserDefaults()
        if let lastTokenData = defaults.objectForKey(LAST_USED_ICLOUD_TOKEN_KEY) as? NSData {
            self.lastiCloudToken = NSKeyedUnarchiver.unarchiveObjectWithData(lastTokenData)
        } else {
            self.lastiCloudToken = nil
        }

        self.currentiCloudToken = NSFileManager.defaultManager().ubiquityIdentityToken
        if let currentToken: AnyObject = self.currentiCloudToken {
            CLLog("iCloud token found")
            self.iCloudAvailable = true
            // (yey) we can continue using iCloud!
            if let lastToken: AnyObject = self.lastiCloudToken {
                if (!lastToken.isEqual(currentToken)) {
                    NSLog("iCloud token is different from before: (Old: \(lastToken), New: \(currentToken))")
                    // Needs a refresh/restart? of files query?
                }
            }
            let currentTokenData = NSKeyedArchiver.archivedDataWithRootObject(currentToken)
            defaults.setObject(currentTokenData, forKey: LAST_USED_ICLOUD_TOKEN_KEY)
        } else {
            NSLog("iCloud Token not found, user must be signed out of iCloud. WTF MAN NOT COOL.")
            // Note: we keep LAST_USED_ICLOUD_TOKEN_KEY in our defaults, so we can check later if we 
            // once used to have iCloud available
            self.iCloudAvailable = false
        }

        if (!self.listeningForiCloudChanges) {
            // Add listener for if iCloud becomes available/not available
            NSNotificationCenter.defaultCenter().addObserver(self,
                                                             selector: #selector(ScreenshotStorage.oniCloudAccountAvailabilityChanged(_:)),
                                                             name: NSUbiquityIdentityDidChangeNotification,
                                                             object: nil)
            self.listeningForiCloudChanges = true
        }
    }

    func oniCloudAccountAvailabilityChanged(notification: NSNotification) {
        NSLog("iCloud account availability changed")
        _ubiquityDocumentsUrl = nil; // Calling .ubiquityDocumentsUrl next time will retrieve it
        self.ubiquityDocumentsUrl
        self.updateCurrentiCloudToken()
    }

    func startListeningForiCloudFileChanges() {
        if !self.iCloudEnabled {
            return;
        }
        if (!self.filesQuery.started) {
            NSNotificationCenter.defaultCenter().addObserver(self,
                selector: #selector(ScreenshotStorage.onFilesQueryDidUpdate(_:)),
                name: NSMetadataQueryDidFinishGatheringNotification,
                object: nil)
            NSNotificationCenter.defaultCenter().addObserver(self,
                selector: #selector(ScreenshotStorage.onFilesQueryDidUpdate(_:)),
                name: NSMetadataQueryDidUpdateNotification,
                object: nil)

            self.filesQuery.enableUpdates()
            self.filesQuery.startQuery()
        }
    }

    func stopListeningForiCloudFileChanges() {
        if (self.filesQuery.started) {
            if (self.filesQuery.gathering) {
                self.filesQuery.disableUpdates()
            }
            if (self.filesQuery.started && !self.filesQuery.stopped) {
                self.filesQuery.stopQuery()
            }
        }
    }

    func onFilesQueryDidUpdate(notification:NSNotification) {
        self.filesQuery.disableUpdates();
        self.updateFileMapFromQuery(self.filesQuery)
        self.filesQuery.enableUpdates();
    }

    func updateFileMapFromQuery(query : NSMetadataQuery) {
        if LOG_SCREENSHOTS_WHEN_UPDATING {
            CLLog("Found \(query.resultCount) results")
        }

        let ubiquityDocumentsUrl = self.ubiquityDocumentsUrl
        if (ubiquityDocumentsUrl == nil) {
            CLLog("Ubiquity documents url was nil during file query update, skipping")
            return;
        }

        self.screenshotFolders.removeAll(keepCapacity: true)
        self.screenshotFoldersByFolderName.removeAll(keepCapacity: true)
        self.screenshotFilesByFolderName.removeAll(keepCapacity: true)

        let fileManager = NSFileManager.defaultManager()
        for result in query.results {
            if !(result is NSMetadataItem) {
                continue
            }
            let item = result as! NSMetadataItem
            if let fileUrl = result.valueForAttribute(NSMetadataItemURLKey) as? NSURL {
                var directoryCheck:ObjCBool = true
                let urlExistsLocally = fileManager.fileExistsAtPath(fileUrl.path!, isDirectory:&directoryCheck)
                var isDirectory = directoryCheck.boolValue

                // If the file is not downloaded by us, ask the system to begin downloading it
                if (!urlExistsLocally) {
                    // If url doesn't exist locally we also can't know for sure if it's a directory, so check using the
                    // url "string"
                    isDirectory = fileUrl.absoluteString.hasSuffix("/")

                    var isDownloading = false
                    if let downloadingNumber = item.valueForAttribute(NSMetadataUbiquitousItemIsDownloadingKey) as? NSNumber {
                        isDownloading = downloadingNumber.boolValue
                    }

                    // isUbiquitousItemAtURL() is seemingly expensive, so limit its use if possible
                    if (!isDownloading && fileManager.isUbiquitousItemAtURL(fileUrl)) {
                        CLLog("iCloud item at url \(fileUrl) doesn't exist locally (and isn't downloading yet), requesting download")
                        do {
                            try NSFileManager.defaultManager().startDownloadingUbiquitousItemAtURL(fileUrl)
                        } catch {

                        }

                    }

                    // Don't parse it, since we don't really have the data
                    continue;
                }


                if (isDirectory) {
                    // It is a directory!
                    // Ensure the directory is RIGHT below our container url
                    if let parentFolderUrl = fileUrl.URLByDeletingLastPathComponent {
                        if !parentFolderUrl.isEqual(ubiquityDocumentsUrl!) {
                            // Skips files like "/Foo/Bar.app", where Bar.app is a folder/package
                            CLLog("Skipping nested folder/package: \(fileUrl.lastPathComponent)")
                            continue;
                        }
                    }
                    if LOG_SCREENSHOTS_WHEN_UPDATING {
                        CLLog("Directory: \(fileUrl)")
                    }
                    let folderName = fileUrl.lastPathComponent!
                    let folder = ScreenshotFolder(folderUrl : fileUrl)
                    self.screenshotFolders.append(folder)
                    self.screenshotFoldersByFolderName[folderName] = folder
                } else {
                    // It is a file
                    //CLLog("File: \(fileUrl)")

                    // Figure out the folder name of this file url
                    let pathComponents = fileUrl.pathComponents!
                    let folderName = pathComponents[pathComponents.count-2]

                    // Ensure it is a filename with an extension of .png, .jpg, or some shit

                    if let filename = item.valueForAttribute(NSMetadataItemFSNameKey) as? NSString {
                        let lowercaseFilename = filename.lowercaseString
                        if (lowercaseFilename.hasSuffix(".png") || lowercaseFilename.hasSuffix(".jpg") || lowercaseFilename.hasSuffix(".jpeg")) {


                            let screenshotFileInfo = ScreenshotFileInfo(fromMetadataItem:item)


                            // Associate this file with the folder it belongs in
                            var files:[ScreenshotFileInfo]? = self.screenshotFilesByFolderName[folderName]
                            if (files == nil) {
                                files = [ScreenshotFileInfo]()
                            }
                            files!.append(screenshotFileInfo)
                            
                            self.screenshotFilesByFolderName[folderName] = files!
                        } else {
                            CLLog("Skipping non-screenshot file: \(filename)")
                        }
                    }

                }
            }
        }

        // Run through the foldernames found within the filepaths and see if any folders are
        // there that ARE NOT in screenshotFoldersByFolderName (i.e. they did not appear
        // as a directory NSMetadataItem in the results)
        // NOTE: This usually means that the iCloud Drive is not turned on, and is the
        // older "Documents & Data" mode before iOS 8 and Yosemite
        self._iCloudDrivePossiblyNotAvailable = false
        let folderNamesWithFilesInThem = self.screenshotFilesByFolderName.keys
        for folderName in folderNamesWithFilesInThem {
            let folder = self.screenshotFoldersByFolderName[folderName]
            if folder == nil {
                self._iCloudDrivePossiblyNotAvailable = true
                // ScreenshotFolder does *NOT* exist, so create it
                let folderUrl = ubiquityDocumentsUrl!.URLByAppendingPathComponent(folderName as String)
                let folder = ScreenshotFolder(folderUrl : folderUrl)
                self.screenshotFolders.append(folder)
                self.screenshotFoldersByFolderName[folderName] = folder
            }
        }

        // Now assign urls to each folder
        for folder in self.screenshotFolders {
            var files = self.screenshotFilesByFolderName[folder.folderName]
            if (files == nil) {
                files = [ScreenshotFileInfo]()
            }
            folder.files = files!
        }

        // Sort folders alphabetically
        self.screenshotFolders.sortInPlace { (folder1, folder2) -> Bool in
            folder1.folderName.lowercaseString.compare(folder2.folderName.lowercaseString) == NSComparisonResult.OrderedAscending
        }

        self.notifyDocumentsWereUpdated()

    }

    func createScreenshotDocumentsFolderIfNeededWithCompletion(completion:((error:NSError?) -> Void)?) {
        let finish = {(success:Bool, error:NSError?) in
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                let _ = completion?(error:error)
            })
        }
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), { () -> Void in

            var maybeFolderUrl:NSURL? = nil
            if self.iCloudEnabled {
                // Initialize the iCloud Documents folder

                // [iCloudContainer]/Documents/
                maybeFolderUrl = self.ubiquityDocumentsUrl
            } else {

                // Initialize local documents folder
                // [AppSandbox]/Documents/Screenshots/
                maybeFolderUrl = self.localScreenshotsUrl
            }

            // For some reason I can't seem to use optional binding here, so explicitly check for nil
            if maybeFolderUrl != nil {
                let screenshotFoldersUrl = maybeFolderUrl!
                var isDirectory: ObjCBool = true
                let exists = NSFileManager.defaultManager().fileExistsAtPath(screenshotFoldersUrl.path!, isDirectory: &isDirectory)
                if(!exists) {
                    let folderType:String = (self.iCloudEnabled ? "iCloud" : "local")
                    CLLog("Creating \(folderType) screenshots folder at \(screenshotFoldersUrl)")
                    do {
                        try NSFileManager.defaultManager().createDirectoryAtPath(screenshotFoldersUrl.path!, withIntermediateDirectories: false, attributes: nil)
                        finish(true, nil)
                    } catch let error as NSError {
                        CLLog("Error creating \(folderType) screenshots folder: \(error)")
                        finish(false, error)
                    }
                } else {
                    // Already exists
                    finish(true, nil)
                }
            } else {
                var message = "Local Documents folder was null, something's really messed up"
                if self.iCloudEnabled {
                    message = "iCloud ubiquity container url was null, iCloud possibly not available?"
                }
                CLLog(message)
                finish(false, NSError(domain: "Screenshotter", code: 500, userInfo: ["message" : message]))
            }
        })
    }


    func updateLocalDocumentsFilesAndFolders() {
        if (self.localScreenshotsUrl == nil) {
            return;
        }

        self.screenshotFolders.removeAll(keepCapacity: true)
        self.screenshotFoldersByFolderName.removeAll(keepCapacity: true)
        self.screenshotFilesByFolderName.removeAll(keepCapacity: true)

        let fileManager = NSFileManager.defaultManager()

        let keys = [NSURLIsDirectoryKey, NSURLIsRegularFileKey, NSURLNameKey]
        // Get top-level folder contents
        guard let folderContents =  try? fileManager.contentsOfDirectoryAtURL(self.localScreenshotsUrl!,
                                                                              includingPropertiesForKeys: keys,
                                                                              options: .SkipsHiddenFiles) else {
            CLLog("Couldn't view contents of local screenshots directory: \(self.localScreenshotsUrl)")
            return;
        }

        // We have the top-level files, enumerate the screenshot folders
        for folderUrl in folderContents {
            if self.isDirectory(folderUrl) {
                // At the top-level we only care about screenshot directories

                let folderName = folderUrl.lastPathComponent!

                var screenshotFiles = [ScreenshotFileInfo]()
                // Get the contents of THAT folder
                guard let fileContents = try? fileManager.contentsOfDirectoryAtURL(folderUrl,
                                                                                   includingPropertiesForKeys: keys,
                                                                                   options: .SkipsHiddenFiles) else {
                    CLLog("Couldn't view contents of screenshots folder: \(folderUrl), skipping")
                    continue;
                }

                for screenshotFileUrl in fileContents {
                    // Since we are the only ones that write into this folder, we pretty much know
                    // that these can only be screenshot files
                    let screenshotFile = ScreenshotFileInfo(fromFileUrl: screenshotFileUrl)
                    screenshotFiles.append(screenshotFile)
                }

                screenshotFiles.sortInPlace { (screenshot1, screenshot2) -> Bool in
                    let date1 = screenshot1.creationDate
                    let date2 = screenshot2.creationDate
                    return date2.compare(date1) == .OrderedAscending
                }

                let screenshotFolder = ScreenshotFolder(folderUrl: folderUrl, files: screenshotFiles)

                self.screenshotFolders.append(screenshotFolder)
                self.screenshotFoldersByFolderName[folderName] = screenshotFolder
                self.screenshotFilesByFolderName[folderName] = screenshotFiles
            }
        }

        // Sort folders alphabetically
        self.screenshotFolders.sortInPlace { (folder1, folder2) -> Bool in
            folder1.folderName.lowercaseString.compare(folder2.folderName.lowercaseString) == NSComparisonResult.OrderedAscending
        }

        self.notifyDocumentsWereUpdated()
    }


    func isDirectory(url:NSURL) -> Bool {
        // TODO(Riz): Ensure this function worked correctly converting from 1.2 to 2.2
        var maybeValue:AnyObject? = nil
        var didDetermineDirectory = false
        do {
            try url.getResourceValue(&maybeValue, forKey: NSURLIsDirectoryKey)
            didDetermineDirectory = true
        } catch {
            didDetermineDirectory = false
        }
        var isDir = false
        if didDetermineDirectory {
            isDir = (maybeValue as! NSNumber).boolValue
        }
        return isDir
    }


    func updateScreenshotFoldersAndFilesIfNeeded() {
        // For local folder, we have to manually update
        if !self.iCloudEnabled {
            self.updateLocalDocumentsFilesAndFolders();
        }
        // For iCloud, we just... wait.
    }


    func createFolderWithName(name:String, completion:((folder:ScreenshotFolder?, error:NSError?) -> Void)?) {
        let parentFolderUrl = (self.iCloudEnabled ? self.ubiquityDocumentsUrl : self.localScreenshotsUrl)
        self.createFolderWithName(name, inFolderUrl: parentFolderUrl, completion: completion)
    }


    func createFolderWithName(name:String, inFolderUrl parentFolderUrl:NSURL?, completion:((folder:ScreenshotFolder?, error:NSError?) -> Void)?) {
        // Sanitize the name to make sure it doesn't include path items
        var sanitizedName = (name as NSString).stringByReplacingOccurrencesOfString("/", withString: ":")
        sanitizedName = sanitizedName.stringByReplacingOccurrencesOfString(".", withString: "_")
        sanitizedName = sanitizedName.stringByReplacingOccurrencesOfString("~", withString: "")

        let startTime = NSDate()

        let finish = { [unowned self] (folder:ScreenshotFolder?, error:NSError?) in
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                if LOG_ELAPSED_TIME {
                    let elapsedTime = NSDate().timeIntervalSinceDate(startTime)
                    CLLog("Took \(elapsedTime)s to create folder: \(name)")
                }
                if folder != nil {
                    self.updateScreenshotFoldersAndFilesIfNeeded()
                }
                // If we don't block the completion return, it thinks the return
                // is for the closure, so hold it in a temp value (smh)
                let _ = completion?(folder: folder, error:error)
            })
        }

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), { () -> Void in

            if let screenshotFoldersUrl = parentFolderUrl {
                let folderNameUrl = screenshotFoldersUrl.URLByAppendingPathComponent(sanitizedName)

                var isDirectory: ObjCBool = true
                let folderNameExists = NSFileManager.defaultManager().fileExistsAtPath(folderNameUrl.path!, isDirectory: &isDirectory)
                if(!folderNameExists) {
                    let path = folderNameUrl.path!
                    do {
                        try NSFileManager.defaultManager().createDirectoryAtPath(path, withIntermediateDirectories: false, attributes: nil)
                        CLLog("Created Folder '\(sanitizedName)' at: \(folderNameUrl.path)")
                        self.updateScreenshotFoldersAndFilesIfNeeded();
                        let folder = ScreenshotFolder(folderUrl: folderNameUrl)
                        // TODO: Create empty screenshot folder and add to our local list (in order)
                        finish(folder, nil)
                    } catch let error as NSError {
                        CLLog("Error creating Folder '\(sanitizedName)': \(error)")
                        finish(nil, error)
                    }
                } else {
                    CLLog("Folder '\(sanitizedName)' already exists! isDirectory: \(isDirectory.boolValue)")
                    if !isDirectory.boolValue {
                        CLLog("WTF, the folder name exists, but it's a file on the system");
                        finish(nil, NSError(domain:"Screenshotter",
                                            code: 409,
                                            userInfo: ["message" : "The folder name already exists, but as a file instead of a directory"]))
                    } else {
                        let folder = ScreenshotFolder(folderUrl: folderNameUrl)
                        finish(folder, nil)
                    }
                }
            } else {
                CLLog("Screenshots folder url was null")
                finish(nil, NSError(domain: "Screenshotter",
                                    code: 500,
                                    userInfo: ["message" : "Screenshots folder not available"]))
            }
        })
    }

    func saveAssets(assets:[PHAsset], toFolderWithName folderName:String, progressHandler:((progress:CGFloat) -> Void)?, completion:((error:NSError?) -> Void)?) {

        CLLog("Saving \(assets.count) assets to folder: \(folderName)")
        let startTime = NSDate()
        let finish = { [unowned self] (error:NSError?) in
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                if LOG_ELAPSED_TIME {
                    let elapsedTime = NSDate().timeIntervalSinceDate(startTime)
                    CLLog("Took \(elapsedTime)s to save \(assets.count) assets to folder: \(folderName)")
                }
                if error == nil {
                    self.updateScreenshotFoldersAndFilesIfNeeded()
                }
                completion?(error:error)
            })
        }

        var progress:CGFloat = 0.0;

        self.createFolderWithName(folderName, completion: { (folder, error) -> Void in
            if let validFolder = folder {

                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), { () -> Void in

                    let numAssets:CGFloat = CGFloat(assets.count);
                    var numAssetImagesLeft:CGFloat = CGFloat(numAssets);

                    let options = PHImageRequestOptions()
                    options.version = PHImageRequestOptionsVersion.Unadjusted // original means it'll download from iCloud if iCloud Photo Library enabled
                    options.deliveryMode = .HighQualityFormat
                    options.networkAccessAllowed = true
                    options.synchronous = true

                    for asset in assets {
                        let imageStartTime = NSDate()
                        PHImageManager.defaultManager().requestImageDataForAsset(asset, options: options, resultHandler: { (imageData, dataUTI, orientation, info) -> Void in
                            if LOG_ELAPSED_TIME {
                                let elapsedImageTime = NSDate().timeIntervalSinceDate(imageStartTime)
                                CLLog(" -> Took \(elapsedImageTime) to fetch asset")
                            }
                            guard let imageData = imageData where imageData.length > 0 else {
                                // Invalid image data
                                CLLog("Skipping asset to save: \(asset). Image data not available, existing info: \(info)")
                                numAssetImagesLeft--;
                                progress = CGFloat(1.0) - (numAssetImagesLeft/numAssets)
                                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                                    let _ = progressHandler?(progress:progress)
                                })
                                if (numAssetImagesLeft == 0) {
                                    // We're done
                                    //FIXME: ScreenshotFolder not returned when having saved assets to Documents folder
                                    finish(nil)
                                }
                                return;
                            }
                            if dataUTI == nil {
                                CLLog("Data UTI was nil, info contains: \(info)")
                            }
                            let filename = self.documentFilenameForPHAsset(asset, dataUTI:dataUTI)
                            let fileUrl = validFolder.folderUrl.URLByAppendingPathComponent(filename)

                            // Create image documents and save them
                            //Read: http://www.raywenderlich.com/12779/icloud-and-uidocument-beyond-the-basics-part-1
                            let imageDoc = ScreenshotDocument(fileURL: fileUrl)
                            imageDoc.data = imageData
                            imageDoc.creationDate = asset.creationDate
                            imageDoc.saveToURL(fileUrl, forSaveOperation:UIDocumentSaveOperation.ForCreating, completionHandler: { (succeeded:Bool) -> Void in
                                if !succeeded {
                                    CLLog("Error saving image to file url: \(fileUrl)")
                                }
                                numAssetImagesLeft--
                                progress = CGFloat(1.0) - (numAssetImagesLeft/numAssets)
                                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                                    let _ = progressHandler?(progress:progress)
                                })
                                if (numAssetImagesLeft == 0) {
                                    // We're done
                                    //FIXME: ScreenshotFolder not returned when having saved assets to Documents folder
                                    finish(nil)
                                }
                            })
                        })
                    }
                })
            } else {
                // Folder couldn't be created while saving assets.
                CLLog("Had error creating folder while saving assets: \(error)")
                finish(error)
            }
        })
    }

    func deleteScreenshotFolder(folder:ScreenshotFolder?, completion:((success:Bool, error:NSError?) -> Void)?) {
        let finish = { [unowned self] (success:Bool, error:NSError?) in
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                if success {
                    self.updateScreenshotFoldersAndFilesIfNeeded()
                }
                let _ = completion?(success:success, error:error)
            })
        }

        guard let folder = folder else {
            // Nothing to delete
            finish(false, nil)
            return;
        }

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), { () -> Void in
            let fileManager = NSFileManager.defaultManager();

            let folderUrl = folder.folderUrl
            do {
                try fileManager.removeItemAtURL(folderUrl)
                if let deleteIndex = self.screenshotFolders.indexOf(folder) {
                    self.screenshotFolders.removeAtIndex(deleteIndex);
                }
                // We're done
                finish(true, nil)
            } catch let error as NSError {
                CLLog("Couldn't delete folder \(folderUrl.lastPathComponent), error: \(error)")
                finish(false, error)
            }
        })
    }

    func renameScreenshotFolder(folder:ScreenshotFolder?, toName newName:String, completion:((success:Bool, error:NSError?) -> Void)?) {
        let finish = { [unowned self] (success:Bool, error:NSError?) in
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                if success {
                    self.updateScreenshotFoldersAndFilesIfNeeded()
                }
                let _ = completion?(success:success, error:error)
            })
        }
        guard let folder = folder else {
            finish(false, nil)
            return;
        }
        if (folder.folderName == newName) {
            finish(true, nil)
            return;
        }
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), { () -> Void in
            let fileManager = NSFileManager.defaultManager();

            let olderFolderUrl:NSURL = folder.folderUrl
            let newFolderUrl = olderFolderUrl.URLByDeletingLastPathComponent!.URLByAppendingPathComponent(newName)

            do {
                try fileManager.moveItemAtURL(olderFolderUrl, toURL: newFolderUrl)
                folder.folderUrl = newFolderUrl
                folder.folderName = newName
                // NOTE: These "updated" fileInfos are not really full representations, they have just had their
                // fileUrls updated, but the other properties are still from before.
                for fileInfo in folder.files {
                    let filename = fileInfo.fileName
                    // Heh, delete two levels up and rebuild with new folder name :troll:
                    let newFileUrl = fileInfo.fileUrl.URLByDeletingLastPathComponent!.URLByDeletingLastPathComponent!.URLByAppendingPathComponent(newName).URLByAppendingPathComponent(filename as String)
                    fileInfo.fileUrl = newFileUrl
                }
                // We're done
                finish(true, nil)
            } catch let error as NSError {
                CLLog("Couldn't rename folder \(olderFolderUrl.lastPathComponent), error: \(error)")
                finish(false, error)
                return;
            }
        })
    }

    func moveScreenshotFiles(files:[ScreenshotFileInfo]?, toFolder destinationFolder:ScreenshotFolder?, progressHandler:((progress:CGFloat) -> Void)?, completion:((success:Bool, error:NSError?) -> Void)?) {
        let finish = { [unowned self] (success:Bool, error:NSError?) in
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                if success {
                    self.updateScreenshotFoldersAndFilesIfNeeded()
                }
                let _ = completion?(success:success, error:error)
            })
        }
        guard let files = files, destinationFolder = destinationFolder else {
            // Files or the folder is nil, back out
            finish(false, nil)
            return;
        }

        // Exclude any files that might already be in this folder
        var sourceFiles = [ScreenshotFileInfo]()
        for file in files {
            let sourceFolderUrl = file.fileUrl.URLByDeletingLastPathComponent!
            if (sourceFolderUrl != destinationFolder.folderUrl) {
                // This file can be moved
                sourceFiles.append(file)
            }
        }
        if (sourceFiles.count == 0) {
            // No files to move
            finish(true, nil)
            return;
        }

        // TODO: Do progress updates for progress handler

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), { () -> Void in
            let fileManager = NSFileManager.defaultManager();

            for sourceFile in sourceFiles {
                let sourceFileUrl = sourceFile.fileUrl
                // New file url using existing file name, but under new dir
                let filename = sourceFile.fileName
                let destinationFileUrl = destinationFolder.folderUrl.URLByAppendingPathComponent(filename as String)

                // Actually do the move
                do {
                    try fileManager.moveItemAtURL(sourceFileUrl, toURL: destinationFileUrl)
                    // Make a "cheap" change, just the fileUrl (potentially stale icloud/file info remains from before)
                    sourceFile.fileUrl = destinationFileUrl;
                    destinationFolder.files.append(sourceFile)
                    finish(true, nil)
                } catch let error as NSError {
                    CLLog("Couldn't move file from:\n \(sourceFileUrl) to:\n \(destinationFileUrl)\n error: \(error)")
                    finish(false, error)
                    return;
                }
            }
        })
    }

    func mergeScreenshotFolder(sourceFolder:ScreenshotFolder?, intoFolder destinationFolder:ScreenshotFolder?, completion:((success:Bool, error:NSError?) -> Void)?) {
        let finish = { [unowned self] (success:Bool, error:NSError?) in
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                if success {
                    self.updateScreenshotFoldersAndFilesIfNeeded()
                }
                let _ = completion?(success:success, error:error)
            })
        }
        if (sourceFolder == nil || destinationFolder == nil) {
            // One of the folders doesn't exist, back out
            finish(false, nil)
            return;
        }
        if (sourceFolder!.folderUrl.isEqual(destinationFolder!.folderUrl)) {
            // Same folder
            finish(true, nil)
            return;
        }
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), { () -> Void in
            let fileManager = NSFileManager.defaultManager();

            // Instead of using moveScreenshotFiles, use raw fileUrls, since we are technically "killing" a folder,
            // and a user may have put non-screenshot files into the folder which would then be erased (and that is bad)
            let fileUrls: [NSURL]
            do {
                fileUrls = try fileManager.contentsOfDirectoryAtURL(sourceFolder!.folderUrl, includingPropertiesForKeys: nil, options:.SkipsHiddenFiles)
            } catch let error as NSError {
                CLLog("Couldn't retrieve fileUrls from folder at url \(sourceFolder!.folderUrl), error: \(error)")
                finish(false, error)
                return;
            }

            for sourceFileUrl in fileUrls {
                // New file url using existing file name, but under new dir
                let filename = sourceFileUrl.lastPathComponent!
                let destinationFileUrl = destinationFolder!.folderUrl.URLByAppendingPathComponent(filename)

                // Actually do the move
                do {
                    try fileManager.moveItemAtURL(sourceFileUrl, toURL: destinationFileUrl)
                } catch let error as NSError {
                    CLLog("Couldn't move file from \(sourceFileUrl) to \(destinationFileUrl), error: \(error)")
                    finish(false, error)
                    return;
                }
            }

            self.deleteScreenshotFolder(sourceFolder, completion: { (success, error) -> Void in
                // We're done
                finish(success, nil)
            })
        })
    }

    func deleteScreenshotFiles(files:[ScreenshotFileInfo]?, completion:((success:Bool, error:NSError?) -> Void)?) {

        let finish = { [unowned self] (success:Bool, error:NSError?) in
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                if success {
                    self.updateScreenshotFoldersAndFilesIfNeeded()
                }
                self.notifyDocumentsWereUpdated()
                let _ = completion?(success:success, error:error)
            })
        }

        if (files == nil) {
            finish(true, nil)
            return;
        }

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), { () -> Void in
            let fileManager = NSFileManager.defaultManager();

            for fileInfo in files! {
                let fileUrl = fileInfo.fileUrl
                do {
                    try fileManager.removeItemAtURL(fileUrl)
                } catch let error as NSError {
                    CLLog("Couldn't delete file \(fileUrl.lastPathComponent), error: \(error)")
                    finish(false, error)
                    return;
                }
                // Remove the screenshot file from our local model
                self.removeScreenshotFileFromLocalModel(fileInfo)
            }

            // We're done
            finish(true, nil)
        })
    }

    func documentFilenameForPHAsset(phAsset:PHAsset, dataUTI:String?) -> String {
        var date: NSDate
        if let creationDate = phAsset.creationDate {
            date = creationDate
        } else {
            // Weird, the asset doesn't have a creation date? ok let's just pick "now"
            date = NSDate()
        }
        let filename = "Screen Shot " + self.dateFormatter.stringFromDate(date)
        var fileExtension = "png"
        if (dataUTI != nil && dataUTI == "public.jpeg") {
            fileExtension = "jpg"
        }


        return filename + "." + fileExtension
    }

    func moveScreenshotsIntoContainer(container:ScreenshotContainerType, completion:((success:Bool, error:NSError?) -> Void)? ) {
        let finish = {(success:Bool, error:NSError?) in
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                let _ = completion?(success: success, error: error)
            })
        }

        if (self.localScreenshotsUrl == nil || self.ubiquityDocumentsUrl == nil) {
            let message = "Local screenshots folder and/or ubiquity documents is unavailable\nLocal: \(self.localScreenshotsUrl)\niCloud: \(self.ubiquityDocumentsUrl)"
            CLLog(message)
            finish(false, NSError(domain: "Screenshotter", code: 500, userInfo: ["message" : message]))
            return
        }

        let destinationContainerUrl = (container == .Local ? self.localScreenshotsUrl! : self.ubiquityDocumentsUrl!)
        let shouldBeUbiquitous = (container == .Cloud)
        let destinationNameForLogging = (container == .Local ? "Local Documents" : "iCloud")

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), { () -> Void in

            // According to NSHipster (http://nshipster.com/nsfilemanager/), we have to create our own instance
            let fileManager = NSFileManager()

            self.createScreenshotDocumentsFolderIfNeededWithCompletion({ (error) -> Void in

                if error != nil {
                    CLLog("Error creating screenshots container folder: \(error)")
                    finish(false, error)
                    return;
                }

                // Create one random suffix for this transfer "attempt", so that all
                // folders during existing-folder errors can be grouped together in Finder
                let randomFilenameSuffix = NSString.randomStringWithLength(4)

                let screenshotFolders = self.screenshotFolders
                var numFoldersLeft = screenshotFolders.count

                for screenshotFolder in screenshotFolders {
                    // Ensure that this same folder exists on the other side
                    var destinationFolderUrl = destinationContainerUrl.URLByAppendingPathComponent(screenshotFolder.folderName as String)
                    do {
                        try fileManager.setUbiquitous(shouldBeUbiquitous, itemAtURL: screenshotFolder.folderUrl, destinationURL: destinationFolderUrl)
                    } catch let actualError as NSError {
                        // Maybe file already exists with that name?
                        if (actualError.code == 516) {
                            CLLog("A folder with the same name (\(screenshotFolder.folderName)) exists at the destination")
                            // Append random file suffix to folder name
                            let newFolderName = (screenshotFolder.folderName as String) + " - " + randomFilenameSuffix
                            destinationFolderUrl = destinationContainerUrl.URLByAppendingPathComponent(newFolderName)
                            // Now try again
                            do {
                                try fileManager.setUbiquitous(shouldBeUbiquitous, itemAtURL: screenshotFolder.folderUrl, destinationURL: destinationFolderUrl)
                            } catch let anotherError as NSError {
                                // TODO(Riz): make this better.
                                CLLog("Skipping. Couldn't move folder '\(screenshotFolder.folderName)' 'into container even after adding random suffix: \(anotherError)")
                            }
                        } else {
                            CLLog("Encountered error while moving screenshot folder '\(screenshotFolder.folderName)' 'to \(destinationNameForLogging): \(actualError)")
                            finish(false, actualError)
                            return
                        }
                    }

                    CLLog("\(screenshotFolder.files.count) screenshots in \(screenshotFolder.folderName) moved to \(destinationNameForLogging)")

                    numFoldersLeft -= 1
                }

                if numFoldersLeft == 0 {
                    // Now all folders and files have been moved, presumably
                    CLLog("All screenshots finished moving, finishing up...")
                    finish(true, nil)
                }
            })
        })
    }

    func removeScreenshotFileFromLocalModel(fileInfo:ScreenshotFileInfo) -> Bool {

        let fileUrl = fileInfo.fileUrl
        if let folderUrl = fileUrl.URLByDeletingLastPathComponent {
            let folderName = folderUrl.lastPathComponent!
            if let folder = self.screenshotFoldersByFolderName[folderName] {
                if let index = folder.files.indexOf(fileInfo) {
                    folder.files.removeAtIndex(index)
                    return true;
                }
            }
        }
        return false;
    }

    func notifyDocumentsWereUpdated() {
        dispatch_async(dispatch_get_main_queue(), { [unowned self] () -> Void in
            NSNotificationCenter.defaultCenter().postNotificationName(self.DOCUMENTS_WERE_UPDATED_NOTIFICATION, object: self)
        })

        if LOG_SCREENSHOTS_WHEN_UPDATING {
            for folder in self.screenshotFolders {
                CLLog("\n")
                CLLog("\(folder)")
                for file in folder.files {
                    CLLog("  \(file.fileUrl.lastPathComponent): \(file.percentUploaded)%")
                }
            }
        }
    }
}
