//
//  ChooseStorageOptionViewController.swift
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

class ChooseStorageOptionViewController: UIViewController {

    @IBOutlet weak var iconView: UIImageView!
    @IBOutlet weak var infoPanelView: UIView!
    @IBOutlet weak var infoPanelViewTopConstraint: NSLayoutConstraint!
    @IBOutlet weak var infoPanelTopPadding: NSLayoutConstraint!
    @IBOutlet weak var useiCloudDriveButtonTopConstraint: NSLayoutConstraint!

    var choiceHandler:((choseiCloud:Bool) -> ())?

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override init(nibName: String!, bundle nibBundle: NSBundle!) {
        super.init(nibName:nibName, bundle:nibBundle)
    }

    override func prefersStatusBarHidden() -> Bool {
        return true;
    }

    override func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        if self.traitCollection.userInterfaceIdiom == .Pad {
            return [UIInterfaceOrientationMask.All]
        } else {
            return [UIInterfaceOrientationMask.Portrait]
        }
    }

    override func preferredInterfaceOrientationForPresentation() -> UIInterfaceOrientation {
        return UIInterfaceOrientation.Portrait
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        var percentageOfHeight:CGFloat = 0.285
        let viewHeight = CGRectGetHeight(UIScreen.mainScreen().bounds)
        var infoPanelPadding = self.infoPanelTopPadding.constant
        var useiCloudButtonTopMargin = self.useiCloudDriveButtonTopConstraint.constant;

        if (!CLScreenshotterApplication.isTallPhoneScreen()) {
            // Hardcoded hack for short iPhones
            // Needed to fit all the bullet points in
            percentageOfHeight = 0.20
            useiCloudButtonTopMargin = 30
        } else if (viewHeight > 568.0) {
            // iPhones 6
            infoPanelPadding = 50.0
        }
        self.infoPanelTopPadding.constant = infoPanelPadding
        self.useiCloudDriveButtonTopConstraint.constant = useiCloudButtonTopMargin

        let idealTopSpace = viewHeight * percentageOfHeight
        self.infoPanelViewTopConstraint.constant = idealTopSpace
    }

    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        Analytics.sharedInstance.registerScreen("Choose Storage Option Screen")
    }

    @IBAction func oniCloudDriveButtonTapped(sender: UIButton) {
        choiceHandler?(choseiCloud:true)
    }
    @IBAction func onUseLocalDocumentsButtonTapped(sender: UIButton) {
        let deviceType = (self.traitCollection.userInterfaceIdiom == .Pad ? "iPad" : "iPhone")
        let msg = "Your filed screenshots and folders will only be on this \(deviceType), and will be deleted if you delete Screenshotter."
        let alert = UIAlertController(title: "Are You Sure?", message: msg, preferredStyle: .Alert)

        let cancelAction = UIAlertAction(title: "Cancel", style: UIAlertActionStyle.Cancel, handler: nil)
        let localAction = UIAlertAction(title: "Continue", style: UIAlertActionStyle.Default) { [unowned self] (action) -> Void in
            let _ = self.choiceHandler?(choseiCloud:false)
        }
        alert.addAction(cancelAction)
        alert.addAction(localAction)
        self.presentViewController(alert, animated: true, completion: nil)
    }

}
