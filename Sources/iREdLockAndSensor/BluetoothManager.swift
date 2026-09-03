import Foundation
import SwiftUI
import CoreBluetooth
import Combine
#if canImport(LockAndSensorFramework)
import LockAndSensorFramework
#endif

@MainActor
public final class BLEManager: NSObject, ObservableObject, @unchecked Sendable {
    
    public static let shared = BLEManager()
    @Published public private(set) var bleState: CBManagerState = .unknown
    
    private let lockAndSensor: LockAndSensor
    private let pirSensor: PIRSensor
    
    @Published public var locks: [iREdLockModel] = []
    @Published public var sensors: [iREdSensorModel] = []
    @Published public var otpLocks: [iREdOtpLockModel] = []
    @Published public var pirSensors: [PIRSensorDeviceModel] = []
    
    private let kDevicesIdentifiablesKey = "devicesIdentifiables"
    private var devicesIdentifiables: [DeviceItem] {
        didSet {
            if let data = try? JSONEncoder().encode(devicesIdentifiables) {
                UserDefaults.standard.set(data, forKey: kDevicesIdentifiablesKey)
            }
        }
    }
    
    private var activePeripheral: CBPeripheral? = nil
    
    public private(set) var otpKey: String = ""
    public func setOtpKey(otpKey: String) {
        self.otpKey = otpKey
    }
    
    private var central: CBCentralManager!
    override init() {
        self.lockAndSensor = LockAndSensor()
        self.pirSensor = PIRSensor()
        if let data = UserDefaults.standard.data(forKey: kDevicesIdentifiablesKey),
           let items = try? JSONDecoder().decode([DeviceItem].self, from: data) {
            self.devicesIdentifiables = items
        } else {
            self.devicesIdentifiables = []
        }
        print("devicesIdentifiables: \(devicesIdentifiables)")
        super.init()
        
        central = CBCentralManager(delegate: self, queue: .main)
        LockAndSensor.delegate = self
        self.pirSensor.delegate = self
        
        for devicesIdentifiable in devicesIdentifiables {
            Task {
                await register(for: devicesIdentifiable.identifier)
            }
        }
    }
    
    public func startListeningToSensor(qrCodeString: String) {
        guard central.state == .poweredOn else { return }
        if let idx = sensors.firstIndex(where: { $0.qrCodeString == qrCodeString }) {
            sensors[idx].isListening = true
        } else if let idx = pirSensors.firstIndex(where: { $0.qrCodeString == qrCodeString }) {
            pirSensors[idx].isListening = true
        }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    
    public func stopListeningToSensor(qrCodeString: String) {
        guard central.state == .poweredOn else { return }
        if let idx = sensors.firstIndex(where: { $0.qrCodeString == qrCodeString }) {
            sensors[idx].isListening = false
        } else if let idx = pirSensors.firstIndex(where: { $0.qrCodeString == qrCodeString }) {
            pirSensors[idx].isListening = false
        }
    }
    
    public func connect(identifier: String) {
        guard central.state == .poweredOn, let deviceAddress = resolveMACAddress(from: identifier) else {
            return
        }
        
        if identifier.count == 16 && !identifier.contains(":") {
            updateOtpLock(deviceAddress: deviceAddress) { ol in
                ol.pairStatus = .pairing
                ol.isConnection = true
            }
        } else {
            updateLock(deviceAddress: deviceAddress) { l in
                l.pairStatus = .pairing
                l.isConnection = true
            }
        }
        
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    
    public func disconnect(identifier: String) {
        guard let deviceAddress = resolveMACAddress(from: identifier) else { return }
        guard let peripheral = locks.first(where: { $0.deviceAddress == deviceAddress })?.blePeripheralInfo?.peripheral else { return }
        central.cancelPeripheralConnection(peripheral)
    }
    
    public func unlock(identifier: String) {
        guard let deviceAddress = resolveMACAddress(from: identifier) else { return }
        if let lock = locks.first(where: { $0.qrCodeString == identifier }) { // Local Lock 只会传递 qrcode
            // Lock
            guard let peripheral = lock.blePeripheralInfo?.peripheral,
                  let writeCh = lock.blePeripheralInfo?.writeCharacteristic else { return }
            do {
                let cmd = try lockAndSensor.BLE_UnlockCommand(deviceAddress: deviceAddress)
                peripheral.writeValue(cmd, for: writeCh, type: .withResponse)
            } catch { }
        } else if let otplock = otpLocks.first(where: { $0.deviceAddress == deviceAddress }) {
            // OTP
            guard let peripheral = otplock.blePeripheralInfo?.peripheral,
                  let writeCh = otplock.blePeripheralInfo?.writeCharacteristic,
                  let cmd = otplock.unlockCommand else { return }
            peripheral.writeValue(cmd, for: writeCh, type: .withResponse)
        }
    }
    
    public func queryStatus(identifier: String) {
        guard let deviceAddress = resolveMACAddress(from: identifier) else { return }
        guard let peripheral = locks.first(where: { $0.deviceAddress == deviceAddress })?.blePeripheralInfo?.peripheral else { return }
        guard let writeCh = locks.first(where: { $0.deviceAddress == deviceAddress })?.blePeripheralInfo?.writeCharacteristic else { return }
        guard let cmd = try? self.lockAndSensor.BLE_LockStatusCommand(deviceAddress: deviceAddress) else { return }
        peripheral.writeValue(cmd, for: writeCh, type: .withResponse)
    }
    
    public func addCard(identifier: String) {
        guard let deviceAddress = resolveMACAddress(from: identifier) else { return }
        guard let peripheral = locks.first(where: { $0.deviceAddress == deviceAddress })?.blePeripheralInfo?.peripheral else { return }
        guard let writeCh = locks.first(where: { $0.deviceAddress == deviceAddress })?.blePeripheralInfo?.writeCharacteristic else { return }
        guard let cmd = try? self.lockAndSensor.BLE_AddCardCommand(deviceAddress: deviceAddress) else { return }
        peripheral.writeValue(cmd, for: writeCh, type: .withResponse)
    }
    
    public func queryCardCount(identifier: String) {
        guard let deviceAddress = resolveMACAddress(from: identifier) else { return }
        guard let peripheral = locks.first(where: { $0.deviceAddress == deviceAddress })?.blePeripheralInfo?.peripheral else { return }
        guard let writeCh = locks.first(where: { $0.deviceAddress == deviceAddress })?.blePeripheralInfo?.writeCharacteristic else { return }
        guard let cmd = try? self.lockAndSensor.BLE_QueryCardCountCommand(deviceAddress: deviceAddress) else { return }
        peripheral.writeValue(cmd, for: writeCh, type: .withResponse)
    }
    
    public func deleteAllCard(identifier: String) {
        guard let deviceAddress = resolveMACAddress(from: identifier) else { return }
        guard let peripheral = locks.first(where: { $0.deviceAddress == deviceAddress })?.blePeripheralInfo?.peripheral else { return }
        guard let writeCh = locks.first(where: { $0.deviceAddress == deviceAddress })?.blePeripheralInfo?.writeCharacteristic else { return }
        guard let cmd = try? self.lockAndSensor.BLE_DeleteAllCardsCommand(deviceAddress: deviceAddress) else { return }
        peripheral.writeValue(cmd, for: writeCh, type: .withResponse)
    }
    
    public func generateOTP(qrCodeString: String, expiredTime: Int) async -> Bool {
        let (otp, exp) = await LockAndSensor.CreateHttpPostBody_GenerateOTP(
            credentials: qrCodeString,
            expiredTime: expiredTime,
            otpKey: self.otpKey
        )
        if let otp, let exp {
            guard let index = locks.firstIndex(where: { $0.qrCodeString == qrCodeString }) else {
                return false
            }
            
            if locks[index].otpList.contains(where: { $0.otp == otp }) {
                return false
            }
            
            locks[index].otpList.append(OTPBaseInfo(otp: otp, exp: exp))
            locks[index].updatedAt = Date()
            
            return true
        }
        return false
    }
    
    public func invalidateOTP(otp: String) {
        Task {
            await LockAndSensor.CreateHttpPostBody_InvalidateOTPCommand(oneTimePassword: otp, otpKey: self.otpKey)
        }
    }
    
    public func setLockCredentials(fromQRCode: String) {
        let (qrCodeString, deviceAddress, isSuccess) = self.lockAndSensor.setLockCredentials(fromQRCode: fromQRCode)
        if isSuccess, let index = locks.firstIndex(where: { $0.qrCodeString == qrCodeString }) {
            locks[index].deviceAddress = deviceAddress
        }
    }
    
    public func setSensorCredentials(fromQRCode: String) {
        let (qr1, addr1, ok1) = lockAndSensor.setSensorCredentials(fromQRCode: fromQRCode)
        if let addr1, ok1, let idx = sensors.firstIndex(where: { $0.qrCodeString == qr1 }) {
            sensors[idx].deviceAddress = addr1
            //            return true
        }
    }
    
    @discardableResult
    public func register(for identifier: String) async -> Bool {
        switch getDeviceType(identifier: identifier) {
        case .lock:
            let (qrCodeString, deviceAddress, isSuccess) = self.lockAndSensor.setLockCredentials(fromQRCode: identifier)
            if isSuccess, let deviceAddress {
                if !locks.contains(where: { $0.qrCodeString == qrCodeString }) {
                    var lock = iREdLockModel(qrCodeString: qrCodeString, deviceAddress: deviceAddress)
                    if let customName = devicesIdentifiables.first(where: { $0.identifier == identifier })?.customName {
                        lock.customName = customName
                    } else {
                        devicesIdentifiables.append(DeviceItem(identifier: identifier, customName: lock.customName))
                    }
                    locks.append(lock)
                }
            }
            
            return isSuccess
            
        case .otp:
            let (deviceAddress, requestTokenCommand) = await LockAndSensor.CreateHttpPostBody_GetMACAddressAndTokenCommand(oneTimePassword: identifier, otpKey: self.otpKey)
            let isSuccess = (deviceAddress != nil && requestTokenCommand != nil)
            if isSuccess, let deviceAddress, let requestTokenCommand {
                let newLock = iREdOtpLockModel(otp: identifier, deviceAddress: deviceAddress, requestTokenCommand: requestTokenCommand)
                addOtpLock(newLock)
            }
            return isSuccess
        case .sensor:
            // 1. 尝试门磁 (Door Sensor)
            let (qr1, addr1, ok1) = lockAndSensor.setSensorCredentials(fromQRCode: identifier)
            if ok1, let addr1 {
                if !sensors.contains(where: { $0.qrCodeString == qr1 }) {
                    var sensor = iREdSensorModel(qrCodeString: qr1, deviceAddress: addr1)
                    if let customName = devicesIdentifiables.first(where: { $0.identifier == identifier })?.customName {
                        sensor.customName = customName
                    } else {
                        devicesIdentifiables.append(DeviceItem(identifier: identifier, customName: sensor.customName))
                    }
                    sensors.append(sensor)
                }
                return true
            }
            
            // 2. 尝试 PIR (PIR Sensor)
            let (qr2, addr2, ok2) = pirSensor.setSensorCredentials(fromQRCode: identifier)
            if ok2, let addr2 {
                if !pirSensors.contains(where: { $0.qrCodeString == qr2 }) {
                    var pirSensor = PIRSensorDeviceModel(qrCodeString: qr2, deviceAddress: addr2)
                    if let customName = devicesIdentifiables.first(where: { $0.identifier == identifier })?.customName {
                        pirSensor.customName = customName
                    } else {
                        devicesIdentifiables.append(DeviceItem(identifier: identifier, customName: pirSensor.customName))
                    }
                    pirSensors.append(pirSensor)
                }
                return true
            }
            
            return false
        case .unknown:
            return false
        }
    }
    
    public func setName(for identifier: String, name: String) {
        if let idx = devicesIdentifiables.firstIndex(where: { $0.identifier == identifier }) {
            devicesIdentifiables[idx].customName = name
        }
        switch getDeviceType(identifier: identifier) {
        case .lock:
            if let idx = locks.firstIndex(where: { $0.qrCodeString == identifier }) {
                locks[idx].customName = name
            }
        case .sensor:
            if let idx = sensors.firstIndex(where: { $0.qrCodeString == identifier }) {
                sensors[idx].customName = name
            }
            if let idx = pirSensors.firstIndex(where: { $0.qrCodeString == identifier }) {
                pirSensors[idx].customName = name
            }
        default:
            break
        }
    }
    
    private func getDeviceType(identifier: String) -> iREdDeviceType {
        if identifier.count == 40 {
            return .lock
        } else if identifier.count == 16 {
            return .otp
        } else if identifier.count == 17 { // MAC地址的冒号格式字符串长度=17
            return .sensor
        } else {
            return .unknown
        }
    }
    
    public enum iREdDeviceType {
        case lock, otp, sensor
        case unknown
    }
}

extension BLEManager: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bleState = central.state
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        var isScanning: Bool {
            locks.contains { $0.isConnection } ||
            otpLocks.contains { $0.isConnection } ||
            sensors.contains { $0.isListening } ||
            pirSensors.contains { $0.isListening }
        }
        
        if !isScanning {
            print("No device needs to be monitored")
            return
        }
        
        // Lock
        if let mac = LockAndSensor.isLock(peripheral: peripheral, advertisementData: advertisementData) {
            if let l = locks.filter({ $0.deviceAddress == mac }).first {
                if l.isConnection {
                    self.activePeripheral = peripheral
                    if let p = self.activePeripheral {
                        central.connect(p, options: nil)
                    }
                    updateLock(deviceAddress: mac) { l in
                        l.blePeripheralInfo = BLEPeripheralInfo(peripheral: peripheral)
                    }
                }
            }
        }
        
        // OTP
        if let mac = LockAndSensor.getLockMAC(peripheral: peripheral, advertisementData: advertisementData) {
            if let ol = otpLocks.filter({ $0.deviceAddress == mac }).first {
                if ol.isConnection {
                    self.activePeripheral = peripheral
                    if let p = self.activePeripheral {
                        central.connect(p, options: nil)
                    }
                    updateOtpLock(deviceAddress: mac) { ol in
                        ol.blePeripheralInfo = BLEPeripheralInfo(peripheral: peripheral)
                    }
                }
            }
        }
        
        // Door Sensor
        if LockAndSensor.isSensor(peripheral: peripheral, advertisementData: advertisementData) {
            LockAndSensor.handleSensorBroadcast(peripheral: peripheral, advertisementData: advertisementData)
        }
        
        // PIR Sensor
        let listeningMacs = self.pirSensors.filter { $0.isListening && $0.deviceAddress != nil }.compactMap { $0.deviceAddress }
        pirSensor.process(peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI.intValue, macAddressList: listeningMacs)
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        if let idx = otpLocks.firstIndex(where: { $0.blePeripheralInfo?.peripheral.identifier.uuidString == peripheral.identifier.uuidString && $0.isConnection }) {
            otpLocks[idx].connectStatus = .connected
        }
        if let mac = LockAndSensor.isLock(peripheral: peripheral, advertisementData: nil)  {
            updateLock(deviceAddress: mac) { l in
                l.connectStatus = .connected
            }
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let mac = LockAndSensor.isLock(peripheral: peripheral, advertisementData: nil) {
            updateLock(deviceAddress: mac) { l in
                l.connectStatus = .connectionFailed
            }
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let mac = LockAndSensor.isLock(peripheral: peripheral, advertisementData: nil) {
            updateLock(deviceAddress: mac) { l in
                l.isConnection = false
                l.connectStatus = .disconnected
                l.batteryPercentage = 0
                l.lockStatus = .unknown
            }
        } else {
            if let idx = otpLocks.firstIndex(where: { $0.blePeripheralInfo?.peripheral.identifier.uuidString == peripheral.identifier.uuidString }) {
                otpLocks[idx].pairStatus = .paired
                otpLocks[idx].connectStatus = .disconnected
                otpLocks[idx].isConnection = false
            }
        }
    }
}

extension BLEManager: @preconcurrency CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return }
        peripheral.services?.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { return }
        service.characteristics?.forEach { ch in
            if ch.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: ch)
            }
            if ch.properties.contains(.write) || ch.properties.contains(.writeWithoutResponse) {
                if let idx = otpLocks.firstIndex(where: { $0.blePeripheralInfo?.peripheral.identifier.uuidString == peripheral.identifier.uuidString && $0.isConnection }) {
                    if let cmd = otpLocks[idx].requestTokenCommand {
                        otpLocks[idx].blePeripheralInfo?.writeCharacteristic = ch
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            // print("连接成功，申请临时令牌")
                            peripheral.writeValue(cmd, for: ch, type: .withResponse)
                        }
                    }
                } else if let mac = LockAndSensor.isLock(peripheral: peripheral, advertisementData: nil) {
                    updateLock(deviceAddress: mac) { l in
                        if l.blePeripheralInfo != nil {
                            l.blePeripheralInfo?.writeCharacteristic = ch
                        } else {
                            var info = BLEPeripheralInfo(peripheral: peripheral)
                            info.writeCharacteristic = ch
                            l.blePeripheralInfo = info
                        }
                    }
                    guard let cmd = try? self.lockAndSensor.BLE_RequestTokenCommand(deviceAddress: mac) else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        // print("连接成功，申请临时令牌")
                        peripheral.writeValue(cmd, for: ch, type: .withResponse)
                    }
                }
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        if let mac = LockAndSensor.isLock(peripheral: peripheral, advertisementData: nil) {
            self.lockAndSensor.decodBleLockData(peripheral: peripheral, encrypted: data)
        }
        // OTP
        if let idx = otpLocks.firstIndex(where: { $0.blePeripheralInfo?.peripheral.identifier.uuidString == peripheral.identifier.uuidString }) {
            if let deviceAddress = otpLocks[idx].deviceAddress {
                Task {
                    await LockAndSensor.CreateHttpPostBody_HandleBleResponseCommand(oneTimePassword: otpLocks[idx].otp, bleResponse: data, otpKey: otpKey)
                }
            }
        }
        
    }
}

extension BLEManager: @preconcurrency LockAndSensorFrameworkDelegate {
    
    public func doorSensorCallback(deviceAddress: String?, didDecodeSensor response: SensorResponse) {
        switch response {
            
        case .batteryLevelEvent(let deviceAddress, let batteryPercentage):
            if let index = sensors.firstIndex(where: { $0.deviceAddress == deviceAddress }) {
                let pct = Int(max(0, min(100, batteryPercentage)))
                sensors[index].batteryPercentage = pct
            }
            
        case .doorStatusEvent(let deviceAddress, let isDoorOpen, let isDisassembled):
            if let index = sensors.firstIndex(where: { $0.deviceAddress == deviceAddress }) {
                sensors[index].contactStatus = isDoorOpen ? .opened : .closed
                sensors[index].tamperStatus = isDisassembled ? .tampered : .normal
            }
        @unknown default:
            fatalError()
        }
    }
    
    public func lockCallback(didDecode response: LockResponse) {
        switch response {
            
        case .tokenRecievedEvent(let deviceAddress, let batteryPercentage):
            
            updateLock(deviceAddress: deviceAddress) { l in
                l.batteryPercentage = batteryPercentage
            }
            
            guard let peripheral = locks.first(where: { $0.deviceAddress == deviceAddress })?.blePeripheralInfo?.peripheral else { return }
            guard let writeCh = locks.first(where: { $0.deviceAddress == deviceAddress })?.blePeripheralInfo?.writeCharacteristic else { return }
            guard let lockStatusCommand = try? self.lockAndSensor.BLE_LockStatusCommand(deviceAddress: deviceAddress) else { return }
            peripheral.writeValue(lockStatusCommand, for: writeCh, type: .withResponse)
            guard let queryCardCountCommand = try? self.lockAndSensor.BLE_QueryCardCountCommand(deviceAddress: deviceAddress) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                peripheral.writeValue(queryCardCountCommand, for: writeCh, type: .withResponse)
            }
            
        case .unlockResponseEvent(let deviceAddress, let isLocked):
            updateLock(deviceAddress: deviceAddress) { l in
                l.lockStatus = isLocked ? .normalClose : .normallyOpen
            }
        case .queryLockStatus(let deviceAddress, let isLocked):
            updateLock(deviceAddress: deviceAddress) { l in
                l.lockStatus = isLocked ? .normalClose : .normallyOpen
            }
            
        case .addCardEvent(let deviceAddress, let isSuccess, let cardType):
            let message = isSuccess
            ? "Card added successfully ✅ (\(cardType == .ic ? "IC Card" : "ID Card"))"
            : "Failed to add card ❌"
            updateLock(deviceAddress: deviceAddress) { l in
                l.cardMessage = message
            }
            
        case .deleteAllCardEvent(let deviceAddress, let isSuccess):
            let message = isSuccess
            ? "All cards deleted ✅"
            : "Failed to delete cards ❌"
            if isSuccess {
                updateLock(deviceAddress: deviceAddress) { l in
                    l.icCardCount = 0
                    l.idCardCount = 0
                    l.updatedAt = Date()
                }
            }
            updateLock(deviceAddress: deviceAddress) { l in
                l.cardMessage = message
            }
            
            
        case .queryCardCountEvent(let deviceAddress, let ic, let id):
            updateLock(deviceAddress: deviceAddress) { l in
                l.icCardCount = ic
                l.idCardCount = id
                l.updatedAt = Date()
                l.cardMessage = "IC Card Count: \(ic), ID Card Count: \(id)"
            }
            
        case .otpInvalidateOTPEvent(let otp, let isSuccess):
            updateOtpLock(otp: otp) { ol in
                ol.isInvalidateOTP = isSuccess
            }
            
        case .otpLockStatusEvent(let otp, let isLocked):
            updateOtpLock(otp: otp) { ol in
                ol.lockStatus = isLocked ? .normalClose : .normallyOpen
            }
            
        case .lockDataAndUnlockCommand(let otp, let unlockCommand, let batteryPercent):
            updateOtpLock(otp: otp) { ol in
                ol.unlockCommand = unlockCommand
                ol.batteryPercentage = batteryPercent ?? 0
            }
            
        case .unknown:
            break
        @unknown default:
            fatalError()
        }
    }
}

extension BLEManager {
    
    private func isValidMACAddress(_ string: String) -> Bool {
        guard string.count == 17 else {
            return false
        }
        
        guard string.contains(":") else {
            return false
        }
        
        return string.allSatisfy {
            $0.isNumber || $0.isLetter || $0 == ":"
        }
    }
    
    private func resolveMACAddress(from identifier: String) -> String? {
        if isValidMACAddress(identifier) {
            return identifier
        }
        
        if let lock = locks.first(where: { $0.qrCodeString == identifier }) {
            if let foundMAC = lock.deviceAddress {
                return foundMAC
            }
        }
        
        if let foundMAC = otpLocks.first(where: { $0.otp == identifier })?.deviceAddress {
            return foundMAC
        }
        
        if let foundMAC = pirSensors.first(where: { $0.deviceAddress == identifier })?.deviceAddress {
            return foundMAC
        }
        return nil
    }
}

// MARK: PIR Sensor
extension BLEManager: @MainActor PIRSensorDelegate {
    public func pirSensor(_ sensor: PIRSensor, didUpdateDevice macAddress: String, result: PIRSensorParseResult) {
        DispatchQueue.main.async {
            if let index = self.pirSensors.firstIndex(where: { $0.deviceAddress?.uppercased() == macAddress.uppercased() || $0.qrCodeString.uppercased() == macAddress.uppercased() }) {
                var device = self.pirSensors[index]
                if !device.isListening { return }
                if let battery = result.battery { device.battery = battery }
                if let temp = result.temperature { device.temperature = temp }
                if let humidity = result.humidity { device.humidity = humidity }
                if let x = result.xValue { device.xValue = x }
                if let y = result.yValue { device.yValue = y }
                if let z = result.zValue { device.zValue = z }
                if let pir = result.pirState { device.pirState = pir }
                if let name = result.name { device.name = name }
                if let lumens = result.lumens { device.lumens = lumens }
                if let rssi = result.rssi { device.rssi = rssi }
                device.lastUpdated = Date()
                self.pirSensors[index] = device
            }
        }
    }
}

extension BLEManager {
    public func addPIRSensor(qrCodeString: String) {
        guard qrCodeString.isValidMACAddress else { return }
        if !pirSensors.contains(where: { $0.qrCodeString == qrCodeString }) {
            let item = PIRSensorDeviceModel(qrCodeString: qrCodeString)
            self.pirSensors.append(item)
            guard central.state == .poweredOn else { return }
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }
}

// MARK: LOCK
extension BLEManager {
    
    @discardableResult
    func addOtpLock(_ lock: iREdOtpLockModel) -> Bool {
        if otpLocks.contains(where: { $0.otp == lock.otp }) {
            return false
        }
        if let mac = lock.deviceAddress, otpLocks.contains(where: { $0.deviceAddress == mac }) {
            return false
        }
        otpLocks.append(lock)
        return true
    }
    
    @discardableResult
    func updateLock(deviceAddress: String, action: (inout iREdLockModel) -> Void) -> Bool {
        guard let index = locks.firstIndex(where: { $0.deviceAddress == deviceAddress }) else {
            return false
        }
        action(&locks[index])
        locks[index].updatedAt = Date()
        return true
    }
    
    @discardableResult
    func updateOtpLock(otp: String, action: (inout iREdOtpLockModel) -> Void) -> Bool {
        guard let index = otpLocks.firstIndex(where: { $0.otp == otp }) else {
            return false
        }
        action(&otpLocks[index])
        otpLocks[index].updatedAt = Date()
        return true
    }
    
    func updateOtpLock(deviceAddress: String, action: (inout iREdOtpLockModel) -> Void) {
        guard let index = otpLocks.firstIndex(where: { $0.deviceAddress == deviceAddress }) else {
            return
        }
        action(&otpLocks[index])
        otpLocks[index].updatedAt = Date()
    }
    
    func getOtpLock(for identifier: String) -> iREdOtpLockModel? {
        if identifier.contains(":") {
            return otpLocks.filter { $0.deviceAddress == identifier }.first
        }
        return otpLocks.filter { $0.otp == identifier }.first
    }
}

// Remove
public extension BLEManager {
    func remove(for identifier: String) {
        locks.removeAll { $0.qrCodeString == identifier }
        sensors.removeAll { $0.qrCodeString == identifier }
        pirSensors.removeAll { $0.qrCodeString == identifier }
        devicesIdentifiables.removeAll { $0.identifier == identifier }
    }
}


struct DeviceItem: Identifiable, Codable {
    var id: String { identifier }
    let identifier: String
    var customName: String
}
