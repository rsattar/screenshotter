# Screenshotter

This is the source code for the iOS app [Screenshotter](http://screenshotter.net/), available [on the App Store](https://itunes.apple.com/us/app/screenshotter-organize-manage/id826596892?mt=8).

<p align="center"><img style="height:600px;width:auto" src="http://screenshotter.net/lib/images/iphone.png"/></p>

## General Project Info

Screenshotter is an Objective C and Swift app that mainly consists of 3 pieces working together:

* Logic to scan a user's photo library (`CLScreenshotsLoader`), looking for PNG images that match iOS screenshot dimensions
* A local Core Data store (`ScreenshotCatalog`), keeping the library information up-to-date
* An iCloud Drive integration, which allows Screenshotter to copy screenshots from the user's photo library to screenshot files on a user-visible file system (`ScreenshotStorage`).

## Building Screenshotter

### iCloud Drive Entitlement
Screenshotter relies on iCloud drive integration, so you will need to have that entitlement in your app Id. You may have to rename the container identifier for iCloud, since `iCloud.com.getcluster.Screenshotter` is already in use in production.

### (Optional) Firebase Integration
Screenshotter uses Firebase Analytics and Crash Reporting. The project has the necessary files either empty (`GoogleService-Info.plist`) or missing (a `.json` file for crash reporting) in the `Firebase Configuration/` folder. 

See [instructions](https://github.com/LaunchKit/screenshotter/blob/master/Screenshotter/Screenshotter/Analytics/Firebase%20Configuration/Instructions.md) to integrating with your Firebase account.

### CocoaPods
Screenshotter uses:

* **[Firebase](https://cocoapods.org/pods/Firebase)**: For analytics and event tracking
* **[Firebase Crash Reporter](https://cocoapods.org/pods/FirebaseCrash)**: For reporting crashes
* **[MBProgressHUD](https://cocoapods.org/pods/MBProgressHUD)**: For showing progress while copying screenshots to iCloud
* **[SDWebImage](https://cocoapods.org/pods/SDWebImage)**: Just for caching images to disk

## License
Screenshotter uses an Apache 2.0 license, under a Cluster Labs, Inc. copyright.

[Read License File](https://github.com/LaunchKit/screenshotter/blob/master/LICENSE)
