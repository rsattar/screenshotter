//
//  TopInnerShadowView.swift
//  Screenshotter
//
//  Created by Rizwan Sattar on 11/13/14.
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

class TopInnerShadowView: UIView {

    var gradient:CAGradientLayer!

    func commonInit() {
        self.gradient = CAGradientLayer();
        self.gradient.colors = [ UIColor(RGBHex:0x999999).CGColor,
                            UIColor(RGBHex:0xD0D0D0).CGColor,
                            UIColor(RGBHex:0xFFFFFF).CGColor];
        self.gradient.locations = [0.0, 0.4, 0.8]
        self.layer.addSublayer(self.gradient);
        self.gradient.frame = self.bounds;
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.commonInit();
    }

    override init(frame: CGRect) {
        super.init(frame:frame);
        self.commonInit();
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.gradient.frame = self.bounds;
    }

}
