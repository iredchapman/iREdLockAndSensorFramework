import Foundation
import CoreBluetooth
import Combine
import iREdSecureLinkFramework

@MainActor
fileprivate final class BluetoothRouter: @unchecked Sendable {

    static let shared = BluetoothRouter()

    private init() {}

    private var macToPeripheral: [String: CBPeripheral] = [:]
    private var macToWriteChar: [String: CBCharacteristic] = [:]

    private var uuidToMAC: [UUID: String] = [:]

    func registerDevice(peripheral: CBPeripheral, macAddress: String) {
        macToPeripheral[macAddress] = peripheral
        uuidToMAC[peripheral.identifier] = macAddress
    }

    func registerWriteChannel(characteristic: CBCharacteristic, for macAddress: String) {
        macToWriteChar[macAddress] = characteristic
    }

    func getDeviceAndChannel(for uuid: UUID) -> (mac: String, writeChar: CBCharacteristic?)? {

        guard let macAddress = uuidToMAC[uuid] else {
            return nil
        }

        let characteristic = macToWriteChar[macAddress]

        return (mac: macAddress, writeChar: characteristic)
    }

    func getPeripheralAndChannel(for macAddress: String) -> (peripheral: CBPeripheral, writeChar: CBCharacteristic?)? {

        guard let peripheral = macToPeripheral[macAddress] else {
            return nil
        }

        let characteristic = macToWriteChar[macAddress]

        return (peripheral: peripheral, writeChar: characteristic)
    }
}

@MainActor
final class BluetoothData: ObservableObject, @unchecked Sendable {
    static let shared = BluetoothData()

    @Published var locks: [iREdLockModel] = []
    @Published var sensors: [iREdSensorModel] = []
    @Published var otpLocks: [iREdOtpLockModel] = []

    private var cancellables = Set<AnyCancellable>()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var storageDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("BluetoothData", isDirectory: true)
    }

    private var locksFileURL: URL { storageDirectoryURL.appendingPathComponent("locks.json") }
    private var sensorsFileURL: URL { storageDirectoryURL.appendingPathComponent("sensors.json") }

    private init() {
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        try? FileManager.default.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true)

        restoreAllData()
        setupAutoSave()
    }

    @discardableResult
    func addLock(_ lock: iREdLockModel) -> Bool {

        if locks.contains(where: { $0.qrCodeString == lock.qrCodeString }) {
            return false
        }
        if let mac = lock.deviceAddress, locks.contains(where: { $0.deviceAddress == mac }) {
            return false
        }
        locks.append(lock)
        return true
    }

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
    func addSensor(_ sensor: iREdSensorModel) -> Bool {
        let qr = sensor.qrCodeString
        if sensors.contains(where: { $0.qrCodeString == qr }) {
            return false
        }
        if sensors.contains(where: { $0.deviceAddress == sensor.deviceAddress }) {
            return false
        }
        sensors.append(sensor)
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
    func updateLock(qrCodeString: String, action: (inout iREdLockModel) -> Void) -> Bool {
        guard let index = locks.firstIndex(where: { $0.qrCodeString == qrCodeString }) else {
            return false
        }
        action(&locks[index])
        locks[index].updatedAt = Date()

        return true
    }

    @discardableResult
    func updateOTPInfo(qrCodeString: String, otpString: String, action: (inout OTPBaseInfo) -> Void) -> Bool {
        guard let lockIndex = locks.firstIndex(where: { $0.qrCodeString == qrCodeString }) else {
            return false
        }
        guard let otpIndex = locks[lockIndex].otpList.firstIndex(where: { $0.otp == otpString }) else {
            return false
        }
        action(&locks[lockIndex].otpList[otpIndex])
        locks[lockIndex].updatedAt = Date()

        return true
    }

    @discardableResult
    func addOTPToLock(deviceAddress: String, newOTP: OTPBaseInfo) -> Bool {
        guard let index = locks.firstIndex(where: { $0.deviceAddress == deviceAddress }) else {
            return false
        }
        if locks[index].otpList.contains(where: { $0.otp == newOTP.otp }) {
            return false
        }

        locks[index].otpList.append(newOTP)
        locks[index].updatedAt = Date()

        return true
    }

    @discardableResult
    func addOTPToLock(qrCodeString: String, newOTP: OTPBaseInfo) -> Bool {
        guard let index = locks.firstIndex(where: { $0.qrCodeString == qrCodeString }) else {
            return false
        }

        if locks[index].otpList.contains(where: { $0.otp == newOTP.otp }) {
            return false
        }

        locks[index].otpList.append(newOTP)
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

    private func setupAutoSave() {
        $locks.dropFirst().debounce(for: .milliseconds(500), scheduler: DispatchQueue.main).sink { [weak self] in self?.saveLocks($0) }.store(in: &cancellables)
        $sensors.dropFirst().debounce(for: .milliseconds(500), scheduler: DispatchQueue.main).sink { [weak self] in self?.saveSensors($0) }.store(in: &cancellables)
    }

    private func saveToFile<T: Codable>(_ array: [T], to fileURL: URL, label: String) {
        do {
            let data = try encoder.encode(array)
            try data.write(to: fileURL, options: .atomic)
        } catch {
        }
    }

    private func saveLocks(_ locks: [iREdLockModel]) {
        var sanitized = locks
        for i in 0..<sanitized.count {
            sanitized[i].connectStatus = .disconnected
            sanitized[i].tempToken = nil
        }
        saveToFile(sanitized, to: locksFileURL, label: "普通锁")
    }

    private func saveSensors(_ sensors: [iREdSensorModel]) {
        saveToFile(sensors, to: sensorsFileURL, label: "传感器")
    }

    private func loadFromFile<T: Codable>(_ fileURL: URL, label: String) -> [T] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let array = try decoder.decode([T].self, from: data)
            return array
        } catch {
            return []
        }
    }

    private func restoreAllData() {
        var restoredLocks: [iREdLockModel] = loadFromFile(locksFileURL, label: "普通锁")
        for i in 0..<restoredLocks.count {
            restoredLocks[i].connectStatus = .disconnected
            restoredLocks[i].pairStatus = .notPair
            restoredLocks[i].tempToken = nil
            restoredLocks[i].lockStatus = .unknown
        }
        self.locks = restoredLocks

        var restoredSensors: [iREdSensorModel] = loadFromFile(sensorsFileURL, label: "传感器")
        for i in 0..<restoredSensors.count {
            restoredSensors[i].contactStatus = .unknown
            restoredSensors[i].tamperStatus = .unknown
        }
        self.sensors = restoredSensors

    }

    func clearAllData() {
        locks.removeAll()
        sensors.removeAll()
        otpLocks.removeAll()

        for fileURL in [locksFileURL, sensorsFileURL] {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func saveAllDataNow() {
        saveLocks(locks)
        saveSensors(sensors)
    }

    func reloadAllData() {
        restoreAllData()
    }

    func purgeExpiredOtpLocks() {
        let before = otpLocks.count
        otpLocks.removeAll { lock in
            lock.isExpired || (lock.isInvalidateOTP == true)
        }
        let _ = before - otpLocks.count
    }
}

@MainActor
public final class BLEManager: NSObject, ObservableObject, @unchecked Sendable {

    public static let shared = BLEManager()
    @Published public private(set) var bleState: CBManagerState = .unknown

    private let br = BluetoothRouter.shared
    private let bd = BluetoothData.shared
    private let lockAndSensor: LockAndSensor

    private var activePeripheral: CBPeripheral? = nil

    public struct ToastMessage: Identifiable, Equatable {
        public let id = UUID()
        public let message: String
    }
    @Published public var globalToastMessage: ToastMessage? = nil
    public func showToast(_ msg: String) {
        self.globalToastMessage = ToastMessage(message: msg)
    }

    private var targetPairingMAC: String? = nil

    public private(set) var otpKey: String = ""
    public func setOtpKey(otpKey: String) {
        self.otpKey = otpKey
        UserDefaults.standard.set(otpKey, forKey: "BLEManager_otpKey")
    }

    private var central: CBCentralManager!
    private var cancellables = Set<AnyCancellable>()
    override init() {
        self.otpKey = UserDefaults.standard.string(forKey: "BLEManager_otpKey") ?? ""
        self.lockAndSensor = LockAndSensor()
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        LockAndSensor.delegate = self

        bd.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    public func startListeningToSensor(qrCodeString: String) {
        guard central.state == .poweredOn else { return }
        if isValidMACAddress(qrCodeString) {
            self.targetPairingMAC = qrCodeString
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }

    @Published private var isOTPLock: Bool = false

    public func connect(identifier: String) {
        guard central.state == .poweredOn else { return }
        guard let deviceAddress = resolveMACAddress(from: identifier) else { return }
        self.targetPairingMAC = deviceAddress
        if identifier.count == 16 && !identifier.contains(":") {
            bd.updateOtpLock(deviceAddress: deviceAddress) { ol in
                ol.pairStatus = .pairing
            }
            isOTPLock = true
        } else {
            bd.updateLock(deviceAddress: deviceAddress) { l in
                l.pairStatus = .pairing
            }
            isOTPLock = false
        }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    public func disconnect(identifier: String) {
        guard let deviceAddress = resolveMACAddress(from: identifier) else { return }
        if let (peripheral, _) = br.getPeripheralAndChannel(for: deviceAddress) {
            central.cancelPeripheralConnection(peripheral)
        }
    }

    public func unlock(identifier: String) {
        guard let deviceAddress = resolveMACAddress(from: identifier) else { return }
        guard let (peripheral, writeCh) = br.getPeripheralAndChannel(for: deviceAddress), let writeCh else { return }
        if isOTPLock {
            guard let cmd = bd.getOtpLock(for: deviceAddress)?.unlockCommand else { return }
            peripheral.writeValue(cmd, for: writeCh, type: .withResponse)
        } else {
            guard let targetLock = bd.locks.first(where: { $0.deviceAddress == deviceAddress }),
                  let tempToken = targetLock.tempToken else { return }
            guard let cmd = try? self.lockAndSensor.BLE_UnlockCommand(deviceAddress: deviceAddress, tempToken: tempToken) else { return }
            peripheral.writeValue(cmd, for: writeCh, type: .withResponse)
        }

    }

    public func queryStatus(identifier: String) {
        guard let deviceAddress = resolveMACAddress(from: identifier) else { return }
        guard let (peripheral, writeCh) = br.getPeripheralAndChannel(for: deviceAddress), let writeCh else { return }
        guard let targetLock = bd.locks.first(where: { $0.deviceAddress == deviceAddress }),
              let tempToken = targetLock.tempToken else { return }
        guard let cmd = try? self.lockAndSensor.BLE_LockStatusCommand(deviceAddress: deviceAddress, tempToken: tempToken) else { return }
        peripheral.writeValue(cmd, for: writeCh, type: .withResponse)
    }

    public func addCard(identifier: String) {
        guard let deviceAddress = resolveMACAddress(from: identifier) else { return }
        guard let (peripheral, writeCh) = br.getPeripheralAndChannel(for: deviceAddress), let writeCh else { return }
        guard let targetLock = bd.locks.first(where: { $0.deviceAddress == deviceAddress }),
              let tempToken = targetLock.tempToken else { return }
        guard let cmd = try? self.lockAndSensor.BLE_AddCardCommand(deviceAddress: deviceAddress, tempToken: tempToken) else { return }
        peripheral.writeValue(cmd, for: writeCh, type: .withResponse)
        showToast("请将卡片靠近锁具识别区")
    }

    public func queryCardCount(identifier: String) {
        guard let deviceAddress = resolveMACAddress(from: identifier) else { return }
        guard let (peripheral, writeCh) = br.getPeripheralAndChannel(for: deviceAddress), let writeCh else { return }
        guard let targetLock = bd.locks.first(where: { $0.deviceAddress == deviceAddress }),
              let tempToken = targetLock.tempToken else { return }
        guard let cmd = try? self.lockAndSensor.BLE_QueryCardCountCommand(deviceAddress: deviceAddress, tempToken: tempToken) else { return }
        peripheral.writeValue(cmd, for: writeCh, type: .withResponse)
    }

    public func deleteAllCard(identifier: String) {
        guard let deviceAddress = resolveMACAddress(from: identifier) else { return }
        guard let (peripheral, writeCh) = br.getPeripheralAndChannel(for: deviceAddress), let writeCh else { return }
        guard let targetLock = bd.locks.first(where: { $0.deviceAddress == deviceAddress }),
              let tempToken = targetLock.tempToken else { return }
        guard let cmd = try? self.lockAndSensor.BLE_DeleteAllCardsCommand(deviceAddress: deviceAddress, tempToken: tempToken) else { return }
        peripheral.writeValue(cmd, for: writeCh, type: .withResponse)
    }

    public func generateOTP(qrCodeString: String, expiredTime: Int) async -> Bool {
        let (otp, exp) = await LockAndSensor.CreateHttpPostBody_GenerateOTP(
            credentials: qrCodeString,
            expiredTime: expiredTime,
            otpKey: self.otpKey
        )
        if let otp, let exp {
            bd.addOTPToLock(qrCodeString: qrCodeString, newOTP: OTPBaseInfo(otp: otp, exp: exp))
            return true
        }
        return false
    }

    public func invalidateOTP(otp: String) {
        Task {
            await LockAndSensor.CreateHttpPostBody_InvalidateOTPCommand(oneTimePassword: otp, otpKey: self.otpKey)
        }
    }

    @discardableResult
    public func register(for identifier: String) async -> Bool {
        switch getDeviceType(identifier: identifier) {
        case .lock:
            let (qrCodeString, deviceAddress, isSuccess) = self.lockAndSensor.setLockCredentials(fromQRCode: identifier)
            if isSuccess {
                bd.addLock(iREdLockModel(qrCodeString: qrCodeString, deviceAddress: deviceAddress))
            }
            return isSuccess

        case .otp:
            let (deviceAddress, requestTokenCommand) = await LockAndSensor.fetch_requestTokenCommand(otp: identifier, otpKey: self.otpKey)
            let isSuccess = (deviceAddress != nil && requestTokenCommand != nil)
            if isSuccess, let deviceAddress, let requestTokenCommand {
                let newLock = iREdOtpLockModel(otp: identifier, deviceAddress: deviceAddress, requestTokenCommand: requestTokenCommand)
                bd.addOtpLock(newLock)
            }
            return isSuccess
        case .sensor:
            let (qrString, mac, isSuccess) = lockAndSensor.setSensorCredentials(fromQRCode: identifier)
            if let mac, isSuccess {
                bd.addSensor(iREdSensorModel(qrCodeString: qrString, deviceAddress: mac))
            }
            return isSuccess
        case .unknown:
            return false
        }

    }

    private func getDeviceType(identifier: String) -> iREdDeviceType {
        if identifier.count == 40 {
            return .lock
        } else if identifier.count == 16 {
            return .otp
        } else if identifier.count == 17 {
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
        if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {

            if let broadcastLockMAC = LockAndSensor.getLockMAC(manufacturerData: mfg), let targetMAC = targetPairingMAC, targetMAC == broadcastLockMAC {

                self.targetPairingMAC = nil

                br.registerDevice(peripheral: peripheral, macAddress: broadcastLockMAC)

                central.stopScan()

                self.activePeripheral = peripheral
                if let p = self.activePeripheral {
                    central.connect(p, options: nil)
                }
                if self.isOTPLock {
                    bd.updateOtpLock(deviceAddress: broadcastLockMAC) { ol in
                        ol.pairStatus = .paired
                        ol.connectStatus = .connecting
                    }
                } else {
                    bd.updateLock(deviceAddress: broadcastLockMAC) { l in
                        l.pairStatus = .paired
                        l.connectStatus = .connecting
                    }
                }
                return
            }

            if let (_, _) = br.getDeviceAndChannel(for: peripheral.identifier) {
                LockAndSensor.handleSensorBroadcast(peripheral: peripheral, manufacturerData: mfg)
                return
            }
            let broadcastSensorMAC = LockAndSensor.getSensorMAC(manufacturerData: mfg)
            if let sensorMAC = broadcastSensorMAC, bd.sensors.contains(where: { $0.deviceAddress == sensorMAC }) {
                LockAndSensor.handleSensorBroadcast(peripheral: peripheral, manufacturerData: mfg)
                br.registerDevice(peripheral: peripheral, macAddress: sensorMAC)
            }
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        if let (macAddress, _) = br.getDeviceAndChannel(for: peripheral.identifier) {
            if self.isOTPLock {
                bd.updateOtpLock(deviceAddress: macAddress) { ol in
                    ol.connectStatus = .connected
                }
            } else {
                bd.updateLock(deviceAddress: macAddress) { l in
                    l.connectStatus = .connected
                }
            }
        }
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let (macAddress, _) = br.getDeviceAndChannel(for: peripheral.identifier) {
            if self.isOTPLock {
                bd.updateOtpLock(deviceAddress: macAddress) { ol in
                    ol.connectStatus = .connectionFailed
                }
            } else {
                bd.updateLock(deviceAddress: macAddress) { l in
                    l.connectStatus = .connectionFailed
                }
            }
        }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let (macAddress, _) = br.getDeviceAndChannel(for: peripheral.identifier) {
            if self.isOTPLock {
                bd.updateOtpLock(deviceAddress: macAddress) { ol in
                    ol.tempToken = nil
                    ol.batteryPercentage = 0
                    ol.lockStatus = .unknown
                    ol.connectStatus = .disconnected
                }
            } else {
                bd.updateLock(deviceAddress: macAddress) { l in
                    l.tempToken = nil
                    l.batteryPercentage = 0
                    l.lockStatus = .unknown
                    l.connectStatus = .disconnected
                }
            }
        }
        self.isOTPLock = false
    }
}

extension BLEManager: @preconcurrency CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return }
        peripheral.services?.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard error == nil else { return }
        service.characteristics?.forEach { ch in
            if ch.properties.contains(.notify) {

                peripheral.setNotifyValue(true, for: ch)
            }
            if ch.properties.contains(.write) {

                if let (macAddress, _) = br.getDeviceAndChannel(for: peripheral.identifier) {
                    br.registerWriteChannel(characteristic: ch, for: macAddress)
                    if isOTPLock {
                        if let otpLock = bd.getOtpLock(for: macAddress), let cmd = otpLock.requestTokenCommand {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {

                                peripheral.writeValue(cmd, for: ch, type: .withResponse)
                            }
                        }
                    } else {
                        guard let cmd = try? self.lockAndSensor.BLE_RequestTokenCommand(deviceAddress: macAddress) else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {

                            peripheral.writeValue(cmd, for: ch, type: .withResponse)
                        }
                    }
                }
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        if let (macAddress, _) = br.getDeviceAndChannel(for: peripheral.identifier) {

            if isOTPLock {
                if let otpLock = bd.getOtpLock(for: macAddress) {
                    Task {
                        await LockAndSensor.CreateHttpPostBody_HandleBleResponseCommand(oneTimePassword: otpLock.otp, bleResponse: data, otpKey: otpKey)
                    }
                    return
                }
            }

            self.lockAndSensor.decodBleLockData(deviceAddress: macAddress, encrypted: data)
        }
    }
}

extension BLEManager: @preconcurrency LockAndSensor.LockAndSensorFrameworkDelegate {

    public func doorSensorCallback(deviceAddress: String?, didDecodeSensor response: LockAndSensor.SensorResponse) {
        switch response {

        case .batteryLevelEvent(let deviceAddress, let batteryPercentage):
            if let index = bd.sensors.firstIndex(where: { $0.deviceAddress == deviceAddress }) {
                let pct = Int(max(0, min(100, batteryPercentage)))
                bd.sensors[index].batteryPercentage = pct
            }

        case .doorStatusEvent(let deviceAddress, let isDoorOpen, let isDisassembled):
            if let index = bd.sensors.firstIndex(where: { $0.deviceAddress == deviceAddress }) {
                bd.sensors[index].contactStatus = isDoorOpen ? .opened : .closed
                bd.sensors[index].tamperStatus = isDisassembled ? .tampered : .normal
            }
        @unknown default:
            fatalError()
        }
    }

    public func lockCallback(didDecode response: LockAndSensor.LockResponse) {
        switch response {

        case .tokenRecievedEvent(let deviceAddress, let token, let batteryPercentage):

            bd.updateLock(deviceAddress: deviceAddress) { l in
                l.batteryPercentage = batteryPercentage
                l.tempToken = token
            }

            guard let (peripheral, writeCh) = br.getPeripheralAndChannel(for: deviceAddress), let writeCh else { return }
            guard let lockStatusCommand = try? self.lockAndSensor.BLE_LockStatusCommand(deviceAddress: deviceAddress, tempToken: token) else { return }
            peripheral.writeValue(lockStatusCommand, for: writeCh, type: .withResponse)
            guard let queryCardCountCommand = try? self.lockAndSensor.BLE_QueryCardCountCommand(deviceAddress: deviceAddress, tempToken: token) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                peripheral.writeValue(queryCardCountCommand, for: writeCh, type: .withResponse)
            }

        case .unlockResponseEvent(let deviceAddress, let isLocked):
            bd.updateLock(deviceAddress: deviceAddress) { l in
                l.lockStatus = isLocked ? .normalClose : .normallyOpen
            }
        case .queryLockStatus(let deviceAddress, let isLocked):
            bd.updateLock(deviceAddress: deviceAddress) { l in
                l.lockStatus = isLocked ? .normalClose : .normallyOpen
            }

        case .addCardEvent(_, let isSuccess, let cardType):
            let message = isSuccess
            ? "Card added successfully ✅ (\(cardType == .ic ? "IC Card" : "ID Card"))"
            : "Failed to add card ❌"
            showToast(message)

        case .deleteAllCardEvent(let deviceAddress, let isSuccess):
            let message = isSuccess
            ? "All cards deleted ✅"
            : "Failed to delete cards ❌"
            showToast(message)
            if isSuccess {
                bd.updateLock(deviceAddress: deviceAddress) { l in
                    l.icCardCount = 0
                    l.idCardCount = 0
                    l.updatedAt = Date()
                }
            }

        case .queryCardCountEvent(let deviceAddress, let ic, let id):
            bd.updateLock(deviceAddress: deviceAddress) { l in
                l.icCardCount = ic
                l.idCardCount = id
                l.updatedAt = Date()
            }

            showToast("Card count: IC=\(ic) | ID=\(id)")

        case .otpInvalidateOTPEvent(let otp, let isSuccess):
            bd.updateOtpLock(otp: otp) { ol in
                ol.isInvalidateOTP = isSuccess
            }

        case .otpLockStatusEvent(let otp, let isLocked):
            bd.updateOtpLock(otp: otp) { ol in
                ol.lockStatus = isLocked ? .normalClose : .normallyOpen
            }

        case .lockDataAndUnlockCommand(let otp, let unlockCommand, let batteryPercent):
            bd.updateOtpLock(otp: otp) { ol in
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

        let macPattern = "^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$"
        return string.range(of: macPattern, options: .regularExpression) != nil
    }

    private func resolveMACAddress(from identifier: String) -> String? {

        if isValidMACAddress(identifier) {
            return identifier
        }

        if let foundMAC = bd.locks.first(where: { $0.qrCodeString == identifier })?.deviceAddress {
            return foundMAC
        }

        if let foundMAC = bd.otpLocks.first(where: { $0.otp == identifier })?.deviceAddress {
            return foundMAC
        }
        return nil
    }
}

extension BLEManager {

    public func getLock(identifier: String) -> iREdLockModel? {
        guard let deviceAddress = resolveMACAddress(from: identifier) else { return nil }
        return bd.locks.first(where: { $0.deviceAddress == deviceAddress })
    }

    public func getLocks() -> [iREdLockModel] {
        return Array(bd.locks)
    }

    public func updateLock(deviceAddress: String, action: (inout iREdLockModel) -> Void) -> Bool {
        return bd.updateLock(deviceAddress: deviceAddress, action: action)
    }

    @discardableResult
    public func setOTPInfo(qrCodeString: String, otpString: String, name: String? = nil, label: String? = nil, description: String? = nil) -> Bool {
        return bd.updateOTPInfo(qrCodeString: qrCodeString, otpString: otpString) { otp in
            otp.name = name
            otp.label = label
            otp.description = description
        }
    }

    public func getOtpLock(otp: String) -> iREdOtpLockModel? {
        return bd.otpLocks.first(where: { $0.otp == otp })
    }

    public func getOtpLocks() -> [iREdOtpLockModel] {
        return Array(bd.otpLocks)
    }

    @discardableResult
    private func updateOtpLock(otp: String, action: (inout iREdOtpLockModel) -> Void) -> Bool {
        return bd.updateOtpLock(otp: otp, action: action)
    }

    public func getSensor(identifier: String) -> iREdSensorModel? {
        return bd.sensors.first(where: { $0.qrCodeString == identifier })
    }

    public func getSensors() -> [iREdSensorModel] {
        return Array(bd.sensors)
    }
}
