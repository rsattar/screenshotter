//
//  TintColorButton.swift
//  Screenshotter
//
//  Created by Rizwan Sattar on 10/28/14.
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

class TintColorButton: UIButton {

    var _lastSetEnabledTintColor:UIColor?

    override var tintColor: UIColor? {
        get {
            return super.tintColor
        }
        set {
            if self.enabled {
                _lastSetEnabledTintColor = newValue
            }
            super.tintColor = newValue
        }
    }

    override var enabled: Bool {
        get {
            return super.enabled
        }
        set {
            super.enabled = newValue
            self.tintColor = newValue ? _lastSetEnabledTintColor : UIColor.darkGrayColor()
            self.imageView?.tintColor = self.tintColor
        }
    }
}
