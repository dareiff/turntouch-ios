//
//  TTModeWemoSwitchOptions.swift
//  Turn Touch iOS
//
//  Created by Samuel Clay on 6/29/16.
//  Copyright © 2016 Turn Touch. All rights reserved.
//

import UIKit

class TTModeWemoDeviceSwitchOptions: TTOptionsDetailViewController, UITableViewDelegate, UITableViewDataSource, TTModeWemoDelegate, TTTitleMenuDelegate {
    
    var modeWemo: TTModeWemo!
    var menuHeight: Int = 42
    
    @IBOutlet var spinner: [UIActivityIndicatorView]!
    @IBOutlet var settingsButton: [UIButton]!
    @IBOutlet var devicesTable: UITableView!
    @IBOutlet var noticeLabel: UILabel!
    
    @IBOutlet var tableHeightConstraint: NSLayoutConstraint!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.modeWemo = (self.mode as! TTModeWemo)
        self.modeWemo.delegate = self
        
        spinner.forEach({ $0.isHidden = true })
        settingsButton.forEach({ $0.isHidden = false })
        
        self.devicesTable.rowHeight = UITableView.automaticDimension
        self.devicesTable.estimatedRowHeight = 2
        self.devicesTable.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        
        self.selectDevices()
    }
    
    func redrawTable() {
        self.devicesTable.reloadData()
        self.devicesTable.layoutIfNeeded()
        tableHeightConstraint.constant = self.devicesTable.contentSize.height
    }
    
    // MARK: Wemo Delegate
    
    func changeState(_ state: TTWemoState, mode: TTModeWemo) {
        if state == .connected {
            spinner.forEach({ $0.isHidden = true })
            settingsButton.forEach({ $0.isHidden = false })
        }
        self.selectDevices()
    }
    
    func selectDevices() {
        self.modeWemo.ensureDevicesSelected()
        
        if TTModeWemo.foundDevices.count == 0 {
            if TTModeWemo.wemoState == .connecting {
                self.noticeLabel.text = "Searching for Wemo devices..."
                self.noticeLabel.textColor = UIColor.darkGray
                spinner.forEach({ $0.isHidden = false })
                settingsButton.forEach({ $0.isHidden = true })
                spinner.forEach { (s) in
                    s.startAnimating()
                }
            } else {
                self.noticeLabel.text = "No Wemo devices found"
                self.noticeLabel.textColor = UIColor.lightGray
                spinner.forEach({ $0.isHidden = true })
                settingsButton.forEach({ $0.isHidden = false })
            }
            self.noticeLabel.isHidden = false
        } else {
            self.noticeLabel.isHidden = true
        }
        
        self.redrawTable()
    }
    
    // MARK: Actions
    
    @IBAction func settings(_ sender: UIButton) {
        appDelegate().mainViewController.toggleModeOptionsMenu(sender, delegate: self)
    }
    
    // MARK: Menu Delegate
    
    func menuOptions() -> [[String : String]] {
        return [
            ["title": "Search for new devices...",
             "image": "search"],
            ["title": "Remove all and search...",
             "image": "remove"],
        ]
    }
    
    func selectMenuOption(_ row: Int) {
        switch row {
        case 0:
            refreshDevices()
        case 1:
            purgeDevices()
        default:
            break
        }
        appDelegate().mainViewController.closeModeOptionsMenu()
    }
    
    @IBAction func refreshDevices() {
        spinner.forEach({ $0.isHidden = false })
        settingsButton.forEach({ $0.isHidden = true })
        spinner.forEach { (s) in
            s.startAnimating()
        }
        
        self.modeWemo.refreshDevices()
    }
    
    func purgeDevices() {
        self.modeWemo.resetKnownDevices()
//        self.action.removeActionOption(TTModeWemoConstants.kWemoSelectedSerials) // Keep selections in case they're useful
        self.selectDevices()
        self.refreshDevices()
    }
    
    // MARK: TableView delegate
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return TTModeWemo.foundDevices.count
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellDevice = TTModeWemo.foundDevices[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.selectionStyle = .blue
        
        cell.textLabel?.text = cellDevice.deviceName
        cell.detailTextLabel?.text = cellDevice.location()
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let cellDevice = TTModeWemo.foundDevices[indexPath.row]
        let devicesSelected = self.action.optionValue(TTModeWemoConstants.kWemoSelectedSerials) as? [String]

        if let devicesSelected = devicesSelected, devicesSelected.contains(cellDevice.serialNumber) {
            cell.accessoryType = .checkmark
            cell.setSelected(true, animated: false)
            self.devicesTable.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        } else {
            cell.accessoryType = .none
            cell.setSelected(false, animated: false)
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        print("Selected: \(indexPath)")
        var selectedSerials: [String] = []
        if let cell = tableView.cellForRow(at: indexPath) {
            cell.accessoryType = .checkmark
        }
        
        
        if let selectedIdentifier = TTModeWemo.foundDevices[indexPath.row].serialNumber {
            if let devicesSelected = self.action.optionValue(TTModeWemoConstants.kWemoSelectedSerials) as? [String] {
                for device in devicesSelected {
                    if device != selectedIdentifier {
                        selectedSerials.append(device)
                    }
                }
            }
            selectedSerials.append(selectedIdentifier)
        }

        self.action.changeActionOption(TTModeWemoConstants.kWemoSelectedSerials, to: selectedSerials)
    }
    
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        print("Deselected: \(indexPath)")
        var selectedSerials: [String] = []

        if let cell = tableView.cellForRow(at: indexPath) {
            cell.accessoryType = .none
        }
        
        if let selectedIdentifier = TTModeWemo.foundDevices[indexPath.row].serialNumber,
            let devicesSelected = self.action.optionValue(TTModeWemoConstants.kWemoSelectedSerials) as? [String] {
            for device in devicesSelected {
                if device != selectedIdentifier {
                    selectedSerials.append(device)
                }
            }
            
        }

        self.action.changeActionOption(TTModeWemoConstants.kWemoSelectedSerials, to: selectedSerials)
    }
    
}
