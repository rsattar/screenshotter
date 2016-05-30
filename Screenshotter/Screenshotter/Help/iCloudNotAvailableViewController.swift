//
//  iCloudNotAvailableViewController.swift
//  Screenshotter
//
//  Created by Rizwan Sattar on 10/27/14.
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

@objc protocol iCloudNotAvailableViewControllerDelegate {
    func iCloudNotAvailableViewControllerDidChangeStorageToUseLocalContainer(controller:iCloudNotAvailableViewController)
}

class iCloudNotAvailableViewController: UIViewController {

    var delegate:iCloudNotAvailableViewControllerDelegate?

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: NSBundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

    @IBAction func onUseLocalContainerButtonTapped(sender: UIButton) {
        self.confirmSwitchingToLocalContainer()
    }


    func confirmSwitchingToLocalContainer() {
        let title = "Stop syncing with iCloud?"
        let message = "Screenshotter will start a new catalog, which will only store your screenshots on this device. If you uninstall Screenshotter, your filed screenshots and folders will be deleted.\n\nYou should consider this option if you are sure you do not want to use iCloud."

        let confirmSwitch = UIAlertController(title: title, message: message, preferredStyle: .Alert)
        confirmSwitch.addAction(UIAlertAction(title: "Cancel", style: .Cancel, handler: { (action) -> Void in

        }));
        confirmSwitch.addAction(UIAlertAction(title: "Continue", style: .Destructive, handler: { (action) -> Void in
            self.reallySwitchToLocalContainer()
        }));

        self.presentViewController(confirmSwitch, animated: true, completion: nil)

    }

    func reallySwitchToLocalContainer() {
        ScreenshotStorage.iCloudUsagePermissionState = .ShouldNotUse

        let destinationName = "Local Documents"
        let progressHUD = MBProgressHUD.showHUDAddedTo(self.view, animated:true)
        progressHUD.labelText = "Migrating to \(destinationName)"
        //progressHUD.mode = 0;//MBProgressHUDModeIndeterminate;
        ScreenshotStorage.sharedInstance.moveScreenshotsIntoContainer(.Local) { (success, error) -> Void in
            ScreenshotStorage.sharedInstance.updateToCurrentStorageOption()
            progressHUD.labelText = "Finishing Up"
            progressHUD.hide(true, afterDelay:0.0)
            self.delegate?.iCloudNotAvailableViewControllerDidChangeStorageToUseLocalContainer(self)
        }
    }
}
