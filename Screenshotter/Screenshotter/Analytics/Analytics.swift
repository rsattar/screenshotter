//
//  Analytics.swift
//  Screenshotter
//
//  Created by Rizwan Sattar on 5/26/16.
//  Copyright © 2016 Cluster Labs, Inc. All rights reserved.
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

let LOG_ANALYTICS_TO_CONSOLE = false

private var FIREBASE_ENABLED = false

/***
 * A place for you to add your own analytics package, if you want
 */
public class Analytics: NSObject {

    public static var sharedInstance: Analytics = {
        let instance = Analytics()
        instance.initialize()
        return instance
    }()

    private func initialize() {
        // Check if GoogleService-Info.plist is in our bundle, and only start
        // Firebase if it is not empty
        if let plistPath = NSBundle.mainBundle().pathForResource("GoogleService-Info", ofType: "plist"),
            let firebasePlist = NSDictionary(contentsOfFile: plistPath) where firebasePlist.count > 0 {
            FIRApp.configure()
            FIREBASE_ENABLED = true
        } else {

            print("Firebase is not configured, because GoogleService-Info.plist in the app bundle is empty by default.")
            print("See Instructions.md in the project directory if you want to set it up.");
        }
    }

    @objc(track:)
    public func track(event event: String) {
        self.track(event: event, properties: nil)
    }

    @objc(track:properties:)
    public func track(event event: String, properties: NSDictionary?) {
        if LOG_ANALYTICS_TO_CONSOLE {
            if let properties = properties where properties.count > 0 {
                print("Tracked '\(event)' with \(properties.count) properties")
            } else {
                print("Tracked '\(event)'")
            }
        }
        if FIREBASE_ENABLED {
            FIRAnalytics.logEventWithName(event, parameters: properties as? [String : NSObject])
        }
    }

    @objc(set:)
    public func set(properties properties: NSDictionary) {
        if LOG_ANALYTICS_TO_CONSOLE {
            print("Set properties: '\(properties)'")
        }
        if FIREBASE_ENABLED {
            for element in properties {
                if let key = element.key as? String {
                    let value = "\(element.value)"
                    FIRAnalytics.setUserPropertyString(value, forName: key)
                }
            }
        }
    }

    @objc(registerScreen:)
    public func registerScreen(screenName: String) {
        if LOG_ANALYTICS_TO_CONSOLE {
            print("Screen: '\(screenName)'")
        }
        if FIREBASE_ENABLED {
            // Firebase can't handle spaces, and strings longer than 24 characters, so transform
            let truncated = screenName.stringByReplacingOccurrencesOfString(" ", withString: "_").lowercaseString
            var eventName = "scr_\(truncated)"
            if eventName.characters.count > 24 {
                eventName = eventName[eventName.startIndex..<(eventName.startIndex.advancedBy(24))]
            }
            FIRAnalytics.logEventWithName(eventName, parameters: nil)
        }
    }
}