//
//  TTModeNestConnecting.swift
//  Turn Touch iOS
//
//  Created by Samuel Clay on 1/3/17.
//  Copyright © 2017 Turn Touch. All rights reserved.
//

import UIKit
import NestSDK

class TTModeNestConnecting: TTOptionsDetailViewController {

    @IBOutlet var progressMessage: UILabel!
    @IBOutlet var cancelButton: UIButton!
    
    var modeNest: TTModeNest!

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.clipsToBounds = true
    }
    
    func setConnectingWithMessage(_ message: String?) {
        var m = message
        if message == nil {
            m = "Connecting to Nest..."
        }
        
        self.progressMessage.text = m
    }
    
    @IBAction func cancelConnect(_ sender: UIButton) {
        self.modeNest.cancelConnectingToNest()
    }

}
