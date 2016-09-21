//
//  TTBluetoothMonitor.swift
//  Turn Touch iOS
//
//  Created by Samuel Clay on 6/8/16.
//  Copyright © 2016 Turn Touch. All rights reserved.
//

import Foundation
import CoreBluetooth
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}


enum TTBluetoothState {
    case bt_STATE_IDLE
    case bt_STATE_SCANNING_KNOWN
    case bt_STATE_CONNECTING_KNOWN
    case bt_STATE_SCANNING_UNKNOWN
    case bt_STATE_CONNECTING_UNKNOWN
    case bt_STATE_PAIRING_UNKNOWN
    case bt_STATE_DISCOVER_SERVICES
    case bt_STATE_DISCOVER_CHARACTERISTICS
    case bt_STATE_CHAR_NOTIFICATION
}

protocol TTBluetoothMonitorDelegate {
    func changedDeviceCount()
    func pairingSuccess()
}

let DEBUG_BLUETOOTH = true

class TTBluetoothMonitor: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    // Firmware rev. 20+ = v2
    let DEVICE_V2_SERVICE_BATTERY_UUID                 = "180F"
    let DEVICE_V2_SERVICE_BUTTON_UUID                  = "99c31523-dc4f-41b1-bb04-4e4deb81fadd"
    let DEVICE_V2_CHARACTERISTIC_BATTERY_LEVEL_UUID    = "2a19"
    let DEVICE_V2_CHARACTERISTIC_BUTTON_STATUS_UUID    = "99c31525-dc4f-41b1-bb04-4e4deb81fadd"
    let DEVICE_V2_CHARACTERISTIC_NICKNAME_UUID         = "99c31526-dc4f-41b1-bb04-4e4deb81fadd"
    
    var manager: CBCentralManager!
    let buttonTimer = TTButtonTimer()
    var batteryLevelTimer: Timer!
    var manufacturer: NSString?
    var foundDevices = TTDeviceList()
    var bluetoothState = TTBluetoothState.bt_STATE_IDLE
    var onceUnknownToken: Int = 0
    var onceKnownToken: Int = 0
    var delegate: TTBluetoothMonitorDelegate?
    
    dynamic var nicknamedConnectedCount: NSNumber?
    dynamic var pairedDevicesCount: NSNumber?
    dynamic var unpairedDevicesCount: NSNumber?
    dynamic var unpairedConnectingCount: NSNumber?
    dynamic var knownDevicesCount: NSNumber?
    
    override init() {
        super.init()
        
        manager = CBCentralManager(delegate: self, queue: DispatchQueue(label: "TT.bluetooth.queue", attributes: []),
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "TTcentralManageRestoreIdentifier",
                                    CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                                    CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                                    CBConnectPeripheralOptionNotifyOnNotificationKey: true])
        buttonTimer.resetPairingState()
    }
    
    // MARK: Bluetooth status
    
    func isLECapableHardware() -> Bool {
        var state: String? = nil
        switch manager.state {
        case .unsupported:
            state = "The platform/hardware doesn't support Bluetooth Low Energy."
        case .unauthorized:
            state = "The app is not authorized to use Bluetooth Low Energy."
        case .poweredOff:
            state = "Bluetooth is currently powered off."
        case .poweredOn:
            return true
        case .unknown:
            state = "Bluetooth in unknown state."
        case .resetting:
            state = "Bluetooth in resetting state."
//        default:
//            state = "Bluetooth not in any state!"
        }
        
        if DEBUG_BLUETOOTH {
            print(" ---> Central manager state: \(state) - \(manager)/\(manager.state)", state!, manager, manager.state)
        }
        return false
    }
    
    func knownPeripheralIdentifiers() -> [UUID] {
        var identifiers: [UUID] = []
        let preferences = UserDefaults.standard
        let pairedDevices = preferences.array(forKey: "TT:devices:paired") as! [String]?
        if pairedDevices != nil {
            for identifier: String in pairedDevices! {
                identifiers.append(NSUUID(uuidString: identifier)! as UUID)
            }
        }
        return identifiers
    }
    
    // MARK: Scanning
    
    func scanKnown()  {
        var knownDevicesStillDisconnected = false
        var isActivelyConnecting = false
        
        bluetoothState = .bt_STATE_SCANNING_KNOWN
        if DEBUG_BLUETOOTH {
            print(" ---> (\(bluetoothState)) Scanning known: \(self.knownPeripheralIdentifiers().count) remotes")
        }
        
        let peripherals = manager.retrievePeripherals(withIdentifiers: self.knownPeripheralIdentifiers())
        let connectedPeripherals = manager.retrieveConnectedPeripherals(withServices: [CBUUID(string:"1523")])

        for peripheralGroup: [CBPeripheral] in [connectedPeripherals, peripherals] {
            for peripheral: CBPeripheral in peripheralGroup {
                var foundDevice = foundDevices.deviceForPeripheral(peripheral)
                if foundDevice == nil {
                    foundDevice = foundDevices.addPeripheral(peripheral)
                } else if foundDevice!.state == TTDeviceState.device_STATE_CONNECTING {
                    isActivelyConnecting = true
                }
                
                if peripheral.state != CBPeripheralState.disconnected && foundDevice!.state != TTDeviceState.device_STATE_SEARCHING {
                    if DEBUG_BLUETOOTH {
                        print(" ---> Already connected: \(foundDevice!)")
                    }
                    continue
                } else {
                    knownDevicesStillDisconnected = true
                }
                
                if foundDevice!.state == .device_STATE_DISCONNECTED {
                    bluetoothState = .bt_STATE_CONNECTING_KNOWN
//                    if DEBUG_BLUETOOTH {
                        print(" ---> (\(bluetoothState)) Attempting connect to known: \(foundDevice)")
//                    }
//
//                    manager.cancelPeripheralConnection(peripheral)
                    
                    foundDevice!.state = .device_STATE_SEARCHING
                    manager.connect(peripheral, options: [CBCentralManagerOptionRestoreIdentifierKey: "TTcentralManageRestoreIdentifier",
                        CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                        CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                        CBConnectPeripheralOptionNotifyOnNotificationKey: true])
                }
            }
        }
        
        if !knownDevicesStillDisconnected {
            bluetoothState = .bt_STATE_IDLE
            if DEBUG_BLUETOOTH {
                print(" ---> (\(bluetoothState)) All done, no known devices left to connect.")
            }
        }
        
        if !isActivelyConnecting && self.knownPeripheralIdentifiers().count == 0 {
            self.scanUnknown()
            return
        }
        
        // Search for unpaired devices or paired devices that aren't responding to `connectPeripheral`
        
//        dispatch_once(&onceUnknownToken) {
//            let delayTime = dispatch_time(DISPATCH_TIME_NOW, Int64(5 * Double(NSEC_PER_SEC)))
//            dispatch_after(delayTime, dispatch_get_main_queue(), {
//                self.onceUnknownToken = 0
//                if self.bluetoothState != .BT_STATE_SCANNING_KNOWN && self.bluetoothState != .BT_STATE_CONNECTING_KNOWN {
//                    if DEBUG_BLUETOOTH {
//                        print(" ---> (\(self.bluetoothState)) Not scanning for unpaired, since not scanning known.")
//                    }
//                    return
//                }
//                
//                if DEBUG_BLUETOOTH {
//                    print(" ---> (\(self.bluetoothState)) Starting scan for unpaired...")
//                }
//                self.stopScan()
//                self.scanUnknown()
//            })
//        }
    }
    
    func scanUnknown() {
        if bluetoothState == .bt_STATE_PAIRING_UNKNOWN {
            if DEBUG_BLUETOOTH {
                print(" ---> (\(bluetoothState)) Not scanning unknown since in pairing state.")
            }
            return
        }
        
        if bluetoothState == .bt_STATE_CONNECTING_UNKNOWN {
            for device: TTDevice in foundDevices.devices {
                if device.state == TTDeviceState.device_STATE_CONNECTING {
                    if DEBUG_BLUETOOTH {
                        print(" ---> (\(bluetoothState)) [Scanning unknown] Canceling peripheral connection: \(device)")
                    }
//                    manager.cancelPeripheralConnection(device.peripheral)
                }
            }
            if DEBUG_BLUETOOTH {
                print(" ---> (\(bluetoothState)) [Scanning unknown] Not scanning unknown, already connecting to unknown")
            }
            return
        }
        
//        self.stopScan()
        
        bluetoothState = .bt_STATE_SCANNING_UNKNOWN
        if DEBUG_BLUETOOTH {
            print(" ---> (\(bluetoothState)) Scanning unknown")
        }
        
        manager.scanForPeripherals(withServices: [CBUUID(string: DEVICE_V2_SERVICE_BUTTON_UUID),
                CBUUID(string:"1523")], options: nil)
    }
    
    func stopScan() {
        if DEBUG_BLUETOOTH {
            print(" ---> (\(bluetoothState)) Stopping scan.")
        }
        manager.stopScan()
    }
    
    // MARK: Background
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        manager = central
        let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as! [CBPeripheral]
//        if DEBUG_BLUETOOTH {
            print(" ---> Restoring state: \(peripherals)")
//        }
        for peripheral in peripherals {
            peripheral.delegate = self
            var device = foundDevices.deviceForPeripheral(peripheral)
            if device == nil {
                device = foundDevices.addPeripheral(peripheral)
            }
            device?.state = .device_STATE_SEARCHING
            manager.connect(peripheral, options: [CBCentralManagerOptionRestoreIdentifierKey: "TTcentralManageRestoreIdentifier",
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                CBConnectPeripheralOptionNotifyOnNotificationKey: true])
        }
    }
    
    // MARK: CBCentralManager delegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if DEBUG_BLUETOOTH {
            print(" ---> (\(bluetoothState)) centralManagerDidUpdateState: \(central)/\(manager) - \(central.state) -> \(manager.state)")
        }
        manager = central
        self.updateBluetoothState()
    }
    
    func updateBluetoothState() {
        if self.isLECapableHardware() {
            self.scanKnown()
        } else {
            self.countDevices()
        }
    }
    
    func forgetDevice(_ device: TTDevice) {
        var pairedDevicesArray: [String] = []
        let prefs = UserDefaults.standard
        if let pairedDevices = prefs.array(forKey: "TT:devices:paired") as! [String]? {
            for identifier: String in pairedDevices {
                if identifier != device.uuid {
                    pairedDevicesArray.append(identifier)
                }
            }
        }
        prefs.set(pairedDevicesArray, forKey: "TT:devices:paired")
        prefs.synchronize()

        self.disconnectDevice(device)
    }
    
    func disconnectDevice(_ device: TTDevice) {
        if let peripheral = foundDevices.peripheralForDevice(device) {
            print(" ---> Disconnect \(peripheral)")
            manager.cancelPeripheralConnection(peripheral)
            foundDevices.removeDevice(device)
            self.countDevices()
        }
    }
    
    func terminate() {
        let identifiers = foundDevices.connected().map { (device) -> UUID in
            device.peripheral.identifier
        }
        let peripherals = manager.retrievePeripherals(withIdentifiers: identifiers)
        for peripheral in peripherals {
            if peripheral.state != .connected {
                continue
            }
            print(" ---> Terminating, canceling: \(peripheral)")
            manager.cancelPeripheralConnection(peripheral)
            let device = foundDevices.deviceForPeripheral(peripheral)
            if device != nil {
                foundDevices.removeDevice(device!)
            }
        }
        
        foundDevices = TTDeviceList()
    }
    
    func countDevices() {
        foundDevices.ensureDevicesConnected()
        
        pairedDevicesCount = foundDevices.pairedConnected().count as NSNumber?
        self.didChangeValue(forKey: "pairedDevicesCount")
        nicknamedConnectedCount = foundDevices.nicknamedConnected().count as NSNumber?
        self.didChangeValue(forKey: "nicknamedConnectedCount")
        unpairedDevicesCount = foundDevices.unpairedConnected().count as NSNumber?
        self.didChangeValue(forKey: "unpairedDevicesCount")
        unpairedConnectingCount = foundDevices.unpairedConnecting().count as NSNumber?
        self.didChangeValue(forKey: "unpairedConnectingCount")
        knownDevicesCount = foundDevices.count() as NSNumber?
        self.didChangeValue(forKey: "knownDevicesCount")
        
        if delegate != nil {
            DispatchQueue.main.async(execute: {
                self.delegate?.changedDeviceCount()
            })
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        var device = foundDevices.deviceForPeripheral(peripheral)
        if device == nil {
            device = foundDevices.addPeripheral(peripheral)
        }
        bluetoothState = .bt_STATE_CONNECTING_UNKNOWN
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as! String
        if DEBUG_BLUETOOTH {
            print(" ---> (\(bluetoothState)) Found bluetooth peripheral, connecting: \(localName)/\(device) (\(RSSI))")
        }
        manager.connect(peripheral,
                                  options: [
                                    CBCentralManagerOptionRestoreIdentifierKey: "TTcentralManageRestoreIdentifier",
                                    CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                                    CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                                    CBConnectPeripheralOptionNotifyOnNotificationKey: true])
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let device = foundDevices.deviceForPeripheral(peripheral) as TTDevice?
        
        if device == nil {
//            if DEBUG_BLUETOOTH {
                print(" ---> No device found for peripheral: \(peripheral)")
//            }
            manager.cancelPeripheralConnection(peripheral)
            return
        }
        
        peripheral.delegate = self
        
        if device!.isPaired {
            device!.state = TTDeviceState.device_STATE_CONNECTING
            device!.needsReconnection = false
            
            self.countDevices()
            
            bluetoothState = .bt_STATE_DISCOVER_SERVICES
        } else {
            // Never seen before, start pairing
            bluetoothState = .bt_STATE_PAIRING_UNKNOWN
            
            device!.state = TTDeviceState.device_STATE_CONNECTING
            device!.needsReconnection = false
            
            buttonTimer.resetPairingState()
            self.countDevices()
            
            let noPairedDevices = foundDevices.totalPairedCount() == 0
            if noPairedDevices {
                DispatchQueue.main.async(execute: { 
                    appDelegate().mainViewController.showPairingModal()
                })
            }
        }
        
        
        //        if DEBUG_BLUETOOTH {
        print(" ---> (\(bluetoothState)) Connected: \(device)")
        //        }
        
        peripheral.discoverServices([CBUUID(string: DEVICE_V2_SERVICE_BUTTON_UUID),
            CBUUID(string: DEVICE_V2_SERVICE_BATTERY_UUID),
            CBUUID(string:"1523")])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let device = foundDevices.deviceForPeripheral(peripheral)
        let paired = device?.isPaired
        
//        if DEBUG_BLUETOOTH {
            print(" ---> (\(bluetoothState)) Disconnected device: \(device)")
//        }
        
        foundDevices.removePeripheral(peripheral)
        self.countDevices()
        
        if !paired! {
            // Scan unknown since the device was unpaired, so we should find it again
//            self.stopScan()
            self.scanUnknown()
        } else {
            self.scanKnown()
        
//            dispatch_once(&onceKnownToken) {
//                let delayTime = dispatch_time(DISPATCH_TIME_NOW, Int64(2 * Double(NSEC_PER_SEC)))
//                dispatch_after(delayTime, dispatch_get_main_queue(), {
//                    self.onceKnownToken = 0
//                    self.scanKnown()
//                })
//            }
        }
        
        // TODO: hudController release toast mode + action
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let device = foundDevices.deviceForPeripheral(peripheral)
        if DEBUG_BLUETOOTH {
            print(" ---> (\(bluetoothState)) Failed connect to device: \(device)-\(peripheral): \(error?.localizedDescription)")
        }
        
        foundDevices.removePeripheral(peripheral)
        self.countDevices()
        
        let delayTime = DispatchTime.now() + Double(Int64(2 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
        DispatchQueue.main.asyncAfter(deadline: delayTime, execute: {
//            self.stopScan()
            self.scanKnown()
        })
    }
    
    // MARK: CBPeripheral delegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        bluetoothState = .bt_STATE_DISCOVER_CHARACTERISTICS
        let device = foundDevices.deviceForPeripheral(peripheral)!
        if peripheral.services == nil {
            if DEBUG_BLUETOOTH {
                print("Nil services")
            }
            return
        }
        
        for service: CBService in peripheral.services! {
            if service.uuid.isEqual(CBUUID(string: DEVICE_V2_SERVICE_BUTTON_UUID)) {
                device.firmwareVersion = 2
                peripheral.discoverCharacteristics([CBUUID(string: DEVICE_V2_CHARACTERISTIC_BUTTON_STATUS_UUID),
                    CBUUID(string: DEVICE_V2_CHARACTERISTIC_NICKNAME_UUID)], for: service)
            }
            if service.uuid.isEqual(CBUUID(string: DEVICE_V2_SERVICE_BATTERY_UUID)) {
                device.firmwareVersion = 2
                peripheral.discoverCharacteristics([CBUUID(string: DEVICE_V2_CHARACTERISTIC_BATTERY_LEVEL_UUID)], for: service)
            }
//            // Device Information Service
//            if service.UUID.isEqual(CBUUID(string: "180A")) {
//                device.firmwareVersion = 2
//                peripheral.discoverCharacteristics([CBUUID(string: "2A29")], forService: service)
//            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        bluetoothState = .bt_STATE_CHAR_NOTIFICATION

        if service.characteristics == nil {
            return
        }
        
        if service.uuid.isEqual(CBUUID(string: DEVICE_V2_SERVICE_BUTTON_UUID)) {
            for characteristic: CBCharacteristic in service.characteristics! {
                if characteristic.uuid.isEqual(CBUUID(string: DEVICE_V2_CHARACTERISTIC_BUTTON_STATUS_UUID)) {
                    peripheral.setNotifyValue(true, for: characteristic)
                    let device = foundDevices.deviceForPeripheral(peripheral)
                    device?.buttonStatusChar = characteristic
                } else if characteristic.uuid.isEqual(CBUUID(string: DEVICE_V2_CHARACTERISTIC_NICKNAME_UUID)) {
                    peripheral.readValue(for: characteristic)
                }
            }
        }
        
        if service.uuid.isEqual(CBUUID(string: DEVICE_V2_SERVICE_BATTERY_UUID)) {
            for characteristic: CBCharacteristic in service.characteristics! {
                if characteristic.uuid.isEqual(CBUUID(string: DEVICE_V2_CHARACTERISTIC_BATTERY_LEVEL_UUID)) {
                    peripheral.readValue(for: characteristic)
                    self.delayBatteryLevelReading()
                }
            }
        }
        
//        if service.UUID.isEqual(CBUUID(string: "180A")) {
//            for characteristic: CBCharacteristic in service.characteristics! {
//                if characteristic.UUID.isEqual(CBUUID(string: "2A29")) {
//                    peripheral.readValueForCharacteristic(characteristic)
//                }
//            }
//        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid.isEqual(CBUUID(string: DEVICE_V2_CHARACTERISTIC_BUTTON_STATUS_UUID)) {
            let device = foundDevices.deviceForPeripheral(peripheral)!
            if DEBUG_BLUETOOTH {
                print(" ---> (\(bluetoothState)) Subscribed to \(device)")
            }
            
            device.isNotified = true
            device.state = TTDeviceState.device_STATE_CONNECTED
            self.countDevices()
            
            bluetoothState = .bt_STATE_IDLE
//            self.scanKnown()
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let device = foundDevices.deviceForPeripheral(peripheral)!
        if DEBUG_BLUETOOTH {
//        print(" ---> Value: \(characteristic.value)")
        }
        
        if characteristic.uuid.isEqual(CBUUID(string: DEVICE_V2_CHARACTERISTIC_BUTTON_STATUS_UUID)) {
            if characteristic.value != nil {
                if DEBUG_BLUETOOTH {
                    print(" ---> \(bluetoothState) Button press: \(characteristic.value?.hexadecimalString)")
                }
                if device.isPaired {
                    buttonTimer.readBluetoothData(characteristic.value!)
                } else {
                    buttonTimer.readBluetoothDataDuringPairing(characteristic.value!)
                    if buttonTimer.isDevicePaired() {
                        self.pairDeviceSuccess(peripheral)
                    }
                }
                device.lastActionDate = Date()
            } else {
                print(" ---> \(bluetoothState) Characteristic error: \(error?.localizedDescription)")
            }
        } else if characteristic.uuid.isEqual(CBUUID(string: DEVICE_V2_CHARACTERISTIC_NICKNAME_UUID)) {
            if (characteristic.value == nil) || (characteristic.value!.count == 0) {
                print(" ---> \(bluetoothState) No nickname: \(device)")
            } else {
                device.setNicknameData(characteristic.value!)
            }
            self.countDevices()
            
            print(" ---> \(bluetoothState) Hello: \(device)")
            
            let delayTime = DispatchTime.now() + Double(Int64(2 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
            DispatchQueue.main.asyncAfter(deadline: delayTime, execute: {
                if device.state != .device_STATE_DISCONNECTED {
                    self.ensureNicknameOnDevice(device)
                }
            })
        }

    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if DEBUG_BLUETOOTH {
            print("peripheral did write: \(characteristic.value)")
        }
    }
    
    // MARK: Firmware options and customization
    
    func ensureNicknameOnDevice(_ device: TTDevice) {
        var newNickname: String!
        let emptyNickname = NSMutableData(length: 32)
        let deviceNickname = device.nickname
        let deviceNicknameData = device.nickname?.data(using: String.Encoding.utf8)
        let prefs = UserDefaults.standard
        let nicknameKey = "TT:device:\(device.uuid):nickname"
        let existingNickname = prefs.string(forKey: nicknameKey)
        
        var hasDeviceNickname: Bool = false
        if deviceNickname != nil {
            hasDeviceNickname = (deviceNicknameData! != emptyNickname! as Data) && (deviceNickname!.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).characters.count) > 0
        }
        
        if existingNickname == nil && hasDeviceNickname {
            prefs.set(device.nickname, forKey: nicknameKey)
            prefs.synchronize()
        }
        
        if !hasDeviceNickname {
            if existingNickname != nil && existingNickname?.characters.count > 0 {
                newNickname = existingNickname!
            } else {
                let emoji = [
                    "🐱", "🐼", "🐶", "🐨", "🐙", "🐝", "🐠", "🐳", "⛄️",
                    "⚽️", "🎻", "🎱", "🌀", "📚", "🔮", "📡", "⛵️", "🚲",
                    "☀️", "🌎", "🌵", "🌴", "🎋", "🍉", "🍒", "🌻", "🌸",
                    "🏺", "🚀", "🔭", "🔬", "🗿", "🏮", "💎", "🎵", "🍄"
                ]
                let randomEmoji = emoji[Int(arc4random_uniform(UInt32(emoji.count)))]
                newNickname = "\(randomEmoji) Turn Touch Remote"
            }
            
            print(" ---> Generating emoji nickname: \(newNickname)")
            
            self.writeNicknameToDevice(device, nickname: newNickname)
        }
    }
    
    func writeNicknameToDevice(_ device: TTDevice, nickname: String) {
        var data = NSMutableData(data: nickname.data(using: String.Encoding.utf8)!)
        let prefs = UserDefaults.standard

        if data.length > 32 {
            var dataString = String(data: data as Data, encoding: String.Encoding.utf8)
            dataString = dataString?.substring(to: dataString!.characters.index(dataString!.startIndex, offsetBy: 32))
            var maxLength = min(32, dataString!.characters.count)
            
            while maxLength > 0 {
                let encodedLength = dataString?.lengthOfBytes(using: String.Encoding.utf8)
                if encodedLength > 32 || encodedLength == 0 {
                    maxLength -= 1
                    dataString = dataString?.substring(to: dataString!.characters.index(dataString!.startIndex, offsetBy: maxLength))
                } else {
                    break
                }
            }
            
//            dataString?.substringToIndex(dataString!.startIndex.advancedBy(maxLength))
            data = NSMutableData(data: dataString!.data(using: String.Encoding.utf8)!)
        } else {
            data.increaseLength(by: 32-data.length)
        }
        
        if device.peripheral == nil {
            print(" ---> Error! Peripheral not connected")
            self.countDevices()
            return
        }
        
        let characteristic = self.characteristicInPeripheral(device.peripheral, serviceUUID: DEVICE_V2_SERVICE_BUTTON_UUID,
                                                             characteristicUUID: DEVICE_V2_CHARACTERISTIC_NICKNAME_UUID)
        
        if DEBUG_BLUETOOTH {
            print(" ---> New nickname: \(nickname) (\(data))")
        }
        device.peripheral.writeValue(data as Data, for: characteristic!, type: .withResponse)
        
        device.setNicknameData(data as Data)
        prefs.set(nickname, forKey: "TT:device:\(device.uuid):nickname")
        prefs.synchronize()
        
        self.countDevices()
    }
    
    func clearDataOfNullBytes(_ data: NSMutableData) {
        
    }
    
    // MARK: Battery
    
    func delayBatteryLevelReading() {
        
    }
    
    func updateBatteryLevel(_ timer: Timer) {
        
    }
    
    // MARK: Pairing
    
    func pairDeviceSuccess(_ peripheral: CBPeripheral) {
        let preferences = UserDefaults.standard
        var pairedDevices = preferences.array(forKey: "TT:devices:paired") as! [String]?
        if pairedDevices == nil {
            pairedDevices = []
        }
        pairedDevices?.append(peripheral.identifier.uuidString)
        preferences.set(pairedDevices, forKey: "TT:devices:paired")
        preferences.synchronize()
        
        if let device = foundDevices.deviceForPeripheral(peripheral) {
            device.isPaired = foundDevices.isDevicePaired(device)
        }
        buttonTimer.resetPairingState()

        self.countDevices()
        appDelegate().modeMap.activeModeDirection = .no_DIRECTION
        if delegate != nil {
            DispatchQueue.main.async {
                self.delegate?.pairingSuccess()
            }
        }
    }
    
    func disconnectUnpairedDevices() {
        for device in foundDevices.devices {
            if !device.isPaired {
                manager.cancelPeripheralConnection(device.peripheral)
            }
        }
        
//        self.stopScan()
    }
    
    func characteristicInPeripheral(_ peripheral: CBPeripheral, serviceUUID: String, characteristicUUID: String) -> CBCharacteristic? {
        for service: CBService in peripheral.services! {
            if service.uuid.isEqual(CBUUID(string: serviceUUID)) {
                for characteristic: CBCharacteristic in service.characteristics! {
                    if characteristic.uuid.isEqual(CBUUID(string: characteristicUUID)) {
                        return characteristic
                    }
                }
            }
        }
        
        return nil
    }
}

