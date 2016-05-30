# Firebase Setup Instructions
=

The Xcode project needs a file called `GoogleService-Info.plist` to configure Firebase Analytics, and a `.json` file to configure Firebase Crash Reporting

## Firebase Analytics

Replace the empty plist `GoogleService-Info.plist` file in this folder, with a valid one from [Firebase](https://firebase.google.com).

### How do I get that file?

1. Set up [a new project in Firebase](https://firebase.google.com).
2. Add the bundle identifier for Screenshotter
3. The `GoogleService-Info.plist` gets downloaded to your computer.
4. Move that file over to this folder, overwriting the empty one that's there.


## Firebase Crash Reporting

Add the `.json` file with your symbol upload service information to this folder.

### How do I get that file?

1. In the process of [configuring your Firebase account for crash reporting](https://firebase.google.com/docs/crash/ios#set_up_crash_reporting), you'll download a `.json` file (e.g. `Screenshotter-RANDOM_NUMBER.json`).
2. Place that file in this folder. (`Firebase Configuration/`)