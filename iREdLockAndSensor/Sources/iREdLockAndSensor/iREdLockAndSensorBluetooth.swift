import Foundation
import CoreBluetooth
import iREdLockAndSensorFramework

@MainActor
public final class iREdLockAndSensorBluetooth: NSObject, ObservableObject {
    @MainActor public static let shared = iREdLockAndSensorBluetooth()
    @Published public private(set) var state: Status = Status()
    
    @Published public private(set) var sensorData: [Sensor] = []
    @Published public private(set) var lockData: [Lock] = []
    @Published public private(set) var otpLockData: [Lock] = []
    
    private var currentScanning_Lock_QRCodeString: String? = nil
    private var currentScanning_OTPLock_otpString: String? = nil
    private var pendingConnect: DeviceType? = nil
    private(set) var otpKey: String = ""
    
    private var central: CBCentralManager!
    
    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        LockAndSensor.delegate = self
    }
    
    public func setOtpKey(otpKey: String) {
        self.otpKey = otpKey
    }
    
    public func startScan(device: DeviceType) {
        guard central.state == .poweredOn else { return }
        
        switch device {
        case .localLock(let qr):
            currentScanning_OTPLock_otpString = nil
            currentScanning_Lock_QRCodeString = qr
            // 标记这把锁进入“配对扫描中”
            updateLock(qrCode: qr) { $0.isPairing = true }
            
        case .otpLock(let otp):
            currentScanning_Lock_QRCodeString = nil
            currentScanning_OTPLock_otpString = otp
            // 标记这把 OTP 锁进入“配对扫描中”
            updateOtpLock(otp: otp) { $0.isPairing = true }
            
        case .sensor(let addr):
            currentScanning_Lock_QRCodeString = nil
            currentScanning_OTPLock_otpString = nil
            updateSensor(deviceAddress: addr) { $0.isScanning = true }
        }
        
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        state.ble_isScanning = true
    }
    
    public func stopScan(for device: DeviceType) {
        switch device {
        case .localLock(let qr):
            // 清锁的配对标记 & 目标意图
            updateLock(qrCode: qr) { $0.isPairing = false }
            if currentScanning_Lock_QRCodeString == qr {
                currentScanning_Lock_QRCodeString = nil
            }
            
        case .otpLock(let otp):
            updateOtpLock(otp: otp) { $0.isPairing = false }
            if currentScanning_OTPLock_otpString == otp {
                currentScanning_OTPLock_otpString = nil
            }
            
        case .sensor(let addr):
            updateSensor(deviceAddress: addr) {
                $0.isScanning = false
                $0.isOpened = nil
                $0.isDisassembled = nil
                $0.batteryPercentage = nil
            }
        }
        
        _stopScanIfNoTargets()
    }
    
    public func connect(to device: DeviceType) {
        guard central.state == .poweredOn else { return }
        pendingConnect = device           // 记录连接意图
        startScan(device: device)         // 统一走扫描
    }
    
    public func disconnect(_ device: DeviceType) {
        switch device {
        case .localLock(let qr):
            if let l = getLock(forQRCode: qr), let p = l.peripheral {
                central.cancelPeripheralConnection(p)
                // 可选：乐观更新，避免 UI 等待回调才变灰
                updateLock(qrCode: qr) { $0.connectStatus = .disconnected }
            }
            _clearPendingIfMatch(.localLock(qrCodeString: qr))
            
        case .otpLock(let otp):
            if let l = getOtpLock(forOTP: otp), let p = l.peripheral {
                central.cancelPeripheralConnection(p)
                updateOtpLock(otp: otp) { $0.connectStatus = .disconnected }
            }
            _clearPendingIfMatch(.otpLock(otp: otp))
            
        case .sensor(let addr):
            if let s = getSensor(forQRCode: addr), let p = s.peripheral {
                central.cancelPeripheralConnection(p)
            }
            _clearPendingIfMatch(.sensor(qrCodeString: addr))
        }
    }
    
    // MARK: LOCK
    public func registerLock(qrCodeString: String) {
        LockAndSensor.setLockCredentials(fromQRCode: qrCodeString)
    }
    
    public func fetchTempToken(qrCodeString: String) {
        guard let l = getLock(forQRCode: qrCodeString), let deviceAddress = l.deviceAddress else { return }
        do {
            let cmd = try LockAndSensor.BLE_RequestTokenCommand(deviceAddress: deviceAddress)
            // print("已经请求TOKEN")
            self.write(to: .localLock(qrCodeString: qrCodeString), data: cmd)
            // "已请求Token"
        } catch {
            // "请求Token失败：\(error)"
        }
    }
    
    public func unlock(qrCodeString: String) {
        guard let l = getLock(forQRCode: qrCodeString), let t = l.tempToken, let deviceAddress = l.deviceAddress else { return }
        do {
            let cmd = try LockAndSensor.BLE_UnlockCommand(deviceAddress: deviceAddress, tempToken: t)
            self.write(to: .localLock(qrCodeString: qrCodeString), data: cmd)
            // "已发送开锁"
        } catch {
            // "开锁失败：\(error)"
        }
        
    }
    
    public func queryStatus(qrCodeString: String) {
        guard let l = getLock(forQRCode: qrCodeString), let t = l.tempToken, let deviceAddress = l.deviceAddress else { return }
        do {
            let cmd = try LockAndSensor.BLE_LockStatusCommand(deviceAddress: deviceAddress, tempToken: t)
            self.write(to: .localLock(qrCodeString: qrCodeString), data: cmd)
            // "查询状态…"
            state.lock_isQueryingStatus = true
        } catch {
            // "查询失败：\(error)"
        }
    }
    
    // MARK: - LOCK Card
    public func addCard(qrCodeString: String) {
        guard let l = getLock(forQRCode: qrCodeString), let t = l.tempToken, let deviceAddress = l.deviceAddress else { return }
        do {
            let cmd = try LockAndSensor.BLE_AddCardCommand(deviceAddress: deviceAddress, tempToken: t)
            self.write(to: .localLock(qrCodeString: qrCodeString), data: cmd)
            // print("添加卡")
        } catch {
            // print("添加卡失败")
        }
    }
    
    public func queryCardCount(qrCodeString: String) {
        guard let l = getLock(forQRCode: qrCodeString), let t = l.tempToken, let deviceAddress = l.deviceAddress else { return }
        do {
            let cmd = try LockAndSensor.BLE_QueryCardCountCommand(deviceAddress: deviceAddress, tempToken: t)
            self.write(to: .localLock(qrCodeString: qrCodeString), data: cmd)
            // print("查询卡数量")
        } catch {
            // print("查询卡数量失败")
        }
    }
    
    public func deleteAllCard(qrCodeString: String) {
        guard let l = getLock(forQRCode: qrCodeString), let t = l.tempToken, let deviceAddress = l.deviceAddress else { return }
        do {
            let cmd = try LockAndSensor.BLE_DeleteAllCardsCommand(deviceAddress: deviceAddress, tempToken: t)
            self.write(to: .localLock(qrCodeString: qrCodeString), data: cmd)
            // print("删除卡")
        } catch {
            // print("删除卡失败")
        }
    }
    
    
    // MARK: - LOCK OTP
    public func generateOTP(qrCodeString: String, expiredTime: Int) {
        state.otp_generating = true
        Task {
            await LockAndSensor.CreteHttpPostBody_GenerateOTP(
                credentials: qrCodeString,
                expiredTime: expiredTime,
                otpKey: self.otpKey
            )
        }
    }
    
    public func getMACAddressAndTokenCommand(otp: String) {
        updateOtpLock(otp: otp) { ol in
            ol.requestingTempToken = true
        }
        if !otp.isEmpty {
            Task {
                await LockAndSensor.CreteHttpPostBody_GetMACAddressAndTokenCommand(oneTimePassword: otp, otpKey: self.otpKey)
            }
        }
    }
    
    public func requestTokenOTP(otp: String) {
        guard let l = getOtpLock(forOTP: otp), let requestTokenCommand = l.requestTokenCommand else { return }
        write(to: .otpLock(otp: otp), data: requestTokenCommand)
    }
    
    public func unlockOTP(otp: String) {
        guard let l = getOtpLock(forOTP: otp), let unlockCommand = l.unlockCommand else { return }
        write(to: .otpLock(otp: otp), data: unlockCommand)
    }
    
    public func invalidateOTP(otp: String) {
        updateOtpLock(otp: otp) { ol in
            ol.invalidating = true
        }
        Task {
            await LockAndSensor.CreteHttpPostBody_InvalidateOTPCommand(oneTimePassword: otp, otpKey: self.otpKey)
        }
    }
    
    // MARK: Sensor
    public func registerSensor(qrString: String) {
        LockAndSensor.setSensorCredentials(fromQRCode: qrString)
    }
    
    // MARK: - 私有工具
    private func write(to device: DeviceType, data: Data) {
        let lock: Lock?
        
        switch device {
        case .localLock(let qrCodeString):
            lock = self.getLock(forQRCode: qrCodeString)
        case .otpLock(let otp):
            lock = self.getOtpLock(forOTP: otp)
        case .sensor:
            return
        }
        
        guard let l = lock, let p = l.peripheral, let ch = l.writeCh else { return }
        p.writeValue(data, for: ch, type: .withResponse)
    }
}

// MARK: - CBCentralManagerDelegate
extension iREdLockAndSensorBluetooth: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            let isOn = (central.state == .poweredOn)
            // isOn ? "蓝牙已开启" : "蓝牙不可用"
            state.ble_isOpenedBluetooth = isOn
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            Task { @MainActor in
                if LockAndSensor.isLock(peripheral: peripheral, manufacturerData: mfg), let deviceAddress = LockAndSensor.getLockMAC(manufacturerData: mfg) {
                    if let qr = currentScanning_Lock_QRCodeString, let lock = getLock(forQRCode: qr), deviceAddress == lock.deviceAddress {
                        _markLocalLockPaired(qr: qr, peripheral: peripheral)
                    }
                    else if let otp = currentScanning_OTPLock_otpString, let lock = getOtpLock(forOTP: otp), deviceAddress == lock.deviceAddress {
                        _markOTPLockPaired(otp: otp, peripheral: peripheral)
                    }
                    
                    if let pending = pendingConnect {
                        _stopScanIfNoTargets()
                        switch pending {
                        case .localLock(let qr):
                            if let lock = getLock(forQRCode: qr), lock.deviceAddress == deviceAddress {
                                self.pendingConnect = nil
                                self.central.connect(peripheral)
                            }
                        case .otpLock(let otp):
                            if let lock = getOtpLock(forOTP: otp), lock.deviceAddress == deviceAddress {
                                self.pendingConnect = nil
                                self.central.connect(peripheral)
                            }
                        case .sensor:
                            break
                        }
                    }
                }
                
                if LockAndSensor.isSensor(peripheral: peripheral, manufacturerData: mfg) {
                    // get mac，不是所有广播数据都有mac地址
                    if let sensor_deviceAddress = LockAndSensor.getSensorMAC(manufacturerData: mfg) {
                        if let sensor = getSensor(forQRCode: sensor_deviceAddress) {
                            if sensor.peripheral == nil { // 避免重复刷新
                                updateSensor(deviceAddress: sensor_deviceAddress) { s in
                                    s.peripheral = peripheral
                                }
                            }
                        }
                    }
                    if let s = sensorData.filter({ $0.peripheral?.identifier == peripheral.identifier }).first {
                        if s.isScanning {
                            LockAndSensor.handleSensorBroadcast(peripheral: peripheral, manufacturerData: mfg)
                        }
                    }
                }
            }
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            peripheral.delegate = self
            peripheral.discoverServices(nil)
            // print("已连接：\(peripheral.name ?? "-")")
            if let l = getLock(forPeripheralUUID: peripheral.identifier), let p = l.peripheral {
                updateLock(peripheralUUID: p.identifier) { l in
                    l.connectStatus = .connected
                }
            } else {
                updateOtpLock(peripheralUUID: peripheral.identifier) { ol in
                    ol.connectStatus = .connected
                }
            }
        }
    }
    
    public func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            // print("连接失败：\(error?.localizedDescription ?? "-")")
        }
    }
    
    public func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            // print("已断开：\(peripheral.name ?? "-")")
            if let _ = getLock(forPeripheralUUID: peripheral.identifier) {
                updateLock(peripheralUUID: peripheral.identifier) { l in
                    l.tempToken = nil
                    l.lockStatus = nil
                    l.batteryPercentage = nil
                    l.writeCh = nil
                    l.notifyCh = nil
                    l.connectStatus = .disconnected
                }
            } else {
                updateOtpLock(peripheralUUID: peripheral.identifier) { ol in
                    ol.tempToken = nil
                    ol.lockStatus = nil
                    ol.batteryPercentage = nil
                    ol.writeCh = nil
                    ol.notifyCh = nil
                    ol.connectStatus = .disconnected
                }
            }
        }
    }
}

// MARK: - CBPeripheralDelegate
extension iREdLockAndSensorBluetooth: @preconcurrency CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard error == nil else { return }
        }
        peripheral.services?.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }
    
    public func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        guard error == nil else { return }
        service.characteristics?.forEach { ch in
            if ch.properties.contains(.notify) {
                Task { @MainActor in
                    
                    if let _ = getLock(forPeripheralUUID: peripheral.identifier) {
                        updateLock(peripheralUUID: peripheral.identifier) { l in
                            l.notifyCh = ch
                        }
                    } else {
                        updateOtpLock(peripheralUUID: peripheral.identifier) { ol in
                            ol.notifyCh = ch
                        }
                    }
                }
                peripheral.setNotifyValue(true, for: ch)
            }
            if ch.properties.contains(.write) {
                Task { @MainActor in
                    
                    if let _ = getLock(forPeripheralUUID: peripheral.identifier) {
                        updateLock(peripheralUUID: peripheral.identifier) { l in
                            l.writeCh = ch
                        }
                    } else {
                        updateOtpLock(peripheralUUID: peripheral.identifier) { ol in
                            ol.writeCh = ch
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
        Task { @MainActor in
            if let l = self.getLock(forPeripheralUUID: peripheral.identifier), let deviceAddress = l.deviceAddress {
                LockAndSensor.decodBleLockData(deviceAddress: deviceAddress, encrypted: data)
            } else if let l = self.getOtpLock(forPeripheralUUID: peripheral.identifier) {
                Task {
                    await LockAndSensor.CreteHttpPostBody_HandleBleResponseCommand(oneTimePassword: l.otpString, bleResponse: data, otpKey: otpKey)
                }
            }
        }
    }
}

extension iREdLockAndSensorBluetooth {
    // MARK: - 工具
    private func normalize(_ deviceAddress: String?) -> String? {
        guard let s = deviceAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s.uppercased().replacingOccurrences(of: ":", with: "")
    }
    private func markLockUpdated(_ idx: Int) { lockData[idx].updatedAt = Date() }
    private func markSensorUpdated(_ idx: Int) { sensorData[idx].updatedAt = Date() }
    private func markOtpLockUpdated(_ idx: Int) { otpLockData[idx].updatedAt = Date() }
    // MARK: - Sensor 增/查/改/删
    /// 查
    public func getSensor(forQRCode deviceAddress: String) -> Sensor? {
        guard let n = normalize(deviceAddress) else { return nil }
        return sensorData.first { normalize($0.deviceAddress) == n }
    }
    /// 改（闭包就地更新任意字段）
    private func updateSensor(deviceAddress: String, update: (inout Sensor) -> Void) {
        guard let n = normalize(deviceAddress),
              let idx = sensorData.firstIndex(where: { normalize($0.deviceAddress) == n }) else { return }
        update(&sensorData[idx])
        markSensorUpdated(idx)
        sensorData = sensorData
    }
    private func updateSensor(qrCode: String, update: (inout Sensor) -> Void) {
        guard let idx = sensorData.firstIndex(where: { $0.qrCodeString == qrCode }) else { return }
        update(&sensorData[idx])
        markSensorUpdated(idx)
        sensorData = sensorData
    }
    /// 增（存在则整体替换，不存在则追加）
    private func upsertSensor(_ sensor: Sensor) {
        let key = normalize(sensor.deviceAddress)
        if let idx = sensorData.firstIndex(where: { normalize($0.deviceAddress) == key }) {
            sensorData[idx] = sensor
            markSensorUpdated(idx)
        } else {
            var new = sensor
            new.updatedAt = Date()
            sensorData.append(new)
        }
        sensorData = sensorData
    }
    /// 删
    private func removeSensor(deviceAddress: String) {
        guard let n = normalize(deviceAddress) else { return }
        sensorData.removeAll { normalize($0.deviceAddress) == n }
    }
    // MARK: - Lock 增/查/改/删
    /// 按 MAC 查
    private func getLock(for deviceAddress: String) -> Lock? {
        guard let n = normalize(deviceAddress) else { return nil }
        return lockData.first { normalize($0.deviceAddress) == n }
    }
    /// 按 peripheralUUID 查
    private func getLock(forPeripheralUUID uuid: UUID) -> Lock? {
        lockData.first { $0.peripheral?.identifier == uuid }
    }
    
    /// 按 QR 查
    public func getLock(forQRCode qrCode: String) -> Lock? {
        lockData.first { $0.qrCodeString == qrCode }
    }
    /// 改（闭包就地更新任意字段）
    private func updateLock(deviceAddress: String, update: (inout Lock) -> Void) {
        guard let n = normalize(deviceAddress),
              let idx = lockData.firstIndex(where: { normalize($0.deviceAddress) == n }) else { return }
        update(&lockData[idx])
        markLockUpdated(idx)
        lockData = lockData
    }
    private func updateLock(qrCode: String, update: (inout Lock) -> Void) {
        guard let idx = lockData.firstIndex(where: { $0.qrCodeString == qrCode }) else { return }
        update(&lockData[idx])
        markLockUpdated(idx)
        lockData = lockData
    }
    /// 改（按 peripheralUUID，就地更新任意字段）
    private func updateLock(peripheralUUID uuid: UUID, update: (inout Lock) -> Void) {
        guard let idx = lockData.firstIndex(where: { $0.peripheral?.identifier == uuid }) else { return }
        update(&lockData[idx])
        markLockUpdated(idx)
        lockData = lockData
    }
    /// 增（存在则整体替换，不存在则追加）
    private func upsertLock(_ lock: Lock) {
        let key = normalize(lock.deviceAddress)
        if let idx = lockData.firstIndex(where: { normalize($0.deviceAddress) == key }) {
            lockData[idx] = lock
            markLockUpdated(idx)
        } else {
            var new = lock
            new.updatedAt = Date()
            lockData.append(new)
        }
        lockData = lockData
    }
    /// 删
    private func removeLock(deviceAddress: String) {
        guard let n = normalize(deviceAddress) else { return }
        lockData.removeAll { normalize($0.deviceAddress) == n }
    }
    
    // MARK: - OTP Lock
    /// 查（按 OTP）
    public func getOtpLock(forOTP otp: String) -> Lock? {
        otpLockData.first { $0.otpString == otp }
    }
    
    /// 查（按 peripheralUUID）
    public func getOtpLock(forPeripheralUUID uuid: UUID) -> Lock? {
        otpLockData.first { $0.peripheral?.identifier == uuid }
    }
    
    /// 改（按 MAC，就地更新部分字段）
    private func updateOtpLock(deviceAddress: String, update: (inout Lock) -> Void) {
        guard let n = normalize(deviceAddress),
              let idx = otpLockData.firstIndex(where: { normalize($0.deviceAddress) == n }) else { return }
        update(&otpLockData[idx])
        markOtpLockUpdated(idx)
        otpLockData = otpLockData
    }
    
    /// 改（按 OTP，就地更新部分字段）
    private func updateOtpLock(otp: String, update: (inout Lock) -> Void) {
        guard let idx = otpLockData.firstIndex(where: { $0.otpString == otp }) else { return }
        update(&otpLockData[idx])
        markOtpLockUpdated(idx)
        otpLockData = otpLockData
    }
    
    /// 改（按 peripheralUUID，就地更新部分字段）
    private func updateOtpLock(peripheralUUID uuid: UUID, update: (inout Lock) -> Void) {
        guard let idx = otpLockData.firstIndex(where: { $0.peripheral?.identifier == uuid }) else { return }
        update(&otpLockData[idx])
        markOtpLockUpdated(idx)
        otpLockData = otpLockData
    }
    
    /// 增（按 OTP，存在则替换，不存在则追加）
    private func upsertOtpLock(_ lock: Lock) {
        if let idx = otpLockData.firstIndex(where: { $0.otpString == lock.otpString }) {
            otpLockData[idx] = lock
            markOtpLockUpdated(idx)
        } else {
            var new = lock
            new.updatedAt = Date()
            otpLockData.append(new)
        }
        otpLockData = otpLockData
    }
    
    /// 删（按 OTP）
    private func removeOtpLock(otp: String) {
        otpLockData.removeAll { $0.otpString == otp }
    }
}


// MARK: - Remove（统一入口 + 自动断开）
extension iREdLockAndSensorBluetooth {
    
    /// 统一删除：根据 DeviceType 自动断开并从数据源移除
    public func remove(device: DeviceType) {
        switch device {
        case .localLock(let qr):
            removeLock(qrCodeString: qr)
            
        case .otpLock(let otp):
            removeOtp(otp: otp)
            
        case .sensor(let qrOrDeviceAddress):
            _removeSensorByQR(qr: qrOrDeviceAddress)
        }
    }
    
    // Lock（按 QR 删除，内部自动断开 & 清理扫描/连接意图）
    private func removeLock(qrCodeString qr: String) {
        guard let l = getLock(forQRCode: qr) else {
            // 兜底：如果传的是 deviceAddress，也尝试按 MAC 删
            removeLock(deviceAddress: qr)
            _clearIntentIfMatch(.localLock(qrCodeString: qr))
            return
        }
        // 1) 停止与之相关的扫描意图
        if currentScanning_Lock_QRCodeString == qr { currentScanning_Lock_QRCodeString = nil }
        _clearIntentIfMatch(.localLock(qrCodeString: qr))
        
        // 2) 断开连接（若有）
        if let p = l.peripheral {
            central.cancelPeripheralConnection(p)
        }
        
        // 3) 移除
        lockData.removeAll { $0.qrCodeString == qr }
        
        // 4) 如果没有任何设备需要扫描，顺手停扫
        _stopScanIfNoTargets()
    }
    
    
    // OTP Lock（按 OTP 删除，内部自动断开 & 清理扫描/连接意图）
    private func removeOtp(otp: String) {
        if let l = getOtpLock(forOTP: otp), let p = l.peripheral {
            central.cancelPeripheralConnection(p)
        }
        // 清理扫描/连接意图
        if currentScanning_OTPLock_otpString == otp { currentScanning_OTPLock_otpString = nil }
        _clearIntentIfMatch(.otpLock(otp: otp))
        
        // 移除
        otpLockData.removeAll { $0.otpString == otp }
        _stopScanIfNoTargets()
    }
    
    // Sensor（按 QR 删除，内部自动断开）
    private func _removeSensorByQR(qr: String) {
        if let idx = sensorData.firstIndex(where: { $0.qrCodeString == qr }) {
            if let p = sensorData[idx].peripheral {
                central.cancelPeripheralConnection(p)
            }
            sensorData.remove(at: idx)
        }
        _stopScanIfNoTargets()
    }
}

// MARK: - 小工具（意图清理 & 条件停扫）
private extension iREdLockAndSensorBluetooth {
    
    /// 若 pendingConnect 与当前要删的设备匹配，则清空
    func _clearIntentIfMatch(_ device: DeviceType) {
        guard let pending = pendingConnect else { return }
        switch (pending, device) {
        case (.localLock(let a), .localLock(let b)) where a == b:
            pendingConnect = nil
        case (.otpLock(let a), .otpLock(let b)) where a == b:
            pendingConnect = nil
        case (.sensor(let a), .sensor(let b)) where a == b:
            pendingConnect = nil
        default:
            break
        }
    }
    
    /// 没有任何扫描目标时停扫
    func _stopScanIfNoTargets() {
        // 条件：无锁/OTP 正在特定扫描意图，且没有任何传感器标记 isScanning
        let anySensorScanning = sensorData.contains { $0.isScanning }
        if currentScanning_Lock_QRCodeString == nil,
           currentScanning_OTPLock_otpString == nil,
           !anySensorScanning,
           state.ble_isScanning {
            central.stopScan()
            state.ble_isScanning = false
        }
    }
    
    /// 若 pendingConnect 与目标一致，则清空
    func _clearPendingIfMatch(_ device: DeviceType) {
        guard let pending = pendingConnect else { return }
        switch (pending, device) {
        case (.localLock(let a), .localLock(let b)) where a == b:
            pendingConnect = nil
        case (.otpLock(let a), .otpLock(let b)) where a == b:
            pendingConnect = nil
        case (.sensor(let a), .sensor(let b)) where a == b:
            pendingConnect = nil
        default:
            break
        }
    }
    
    
    /// 锁（本地二维码）配对完成：赋值 peripheral、pairStatus、清 isPairing 和扫描意图
    func _markLocalLockPaired(qr: String, peripheral: CBPeripheral) {
        updateLock(qrCode: qr) {
            $0.peripheral = peripheral
            $0.pairStatus = .paired
            $0.isPairing = false
        }
        if currentScanning_Lock_QRCodeString == qr {
            currentScanning_Lock_QRCodeString = nil
        }
        _stopScanIfNoTargets()
    }
    
    /// OTP 锁配对完成
    func _markOTPLockPaired(otp: String, peripheral: CBPeripheral) {
        updateOtpLock(otp: otp) {
            $0.peripheral = peripheral
            $0.pairStatus = .paired
            $0.isPairing = false
        }
        if currentScanning_OTPLock_otpString == otp {
            currentScanning_OTPLock_otpString = nil
        }
        _stopScanIfNoTargets()
    }
}

extension iREdLockAndSensorBluetooth: @preconcurrency LockAndSensor.LockAndSensorFrameworkDelegate {
    
    // MARK: - 传感器回包
    public func doorSensorCallback(deviceAddress: String?, didDecodeSensor response: LockAndSensor.SensorResponse) {
        switch response {
        case .register(let qrCodeString, let isSuccess):
            upsertSensor(Sensor(qrCodeString: qrCodeString, isRegisterSuccess: isSuccess, deviceAddress: deviceAddress))
            
        case .batteryLevelEvent(let deviceAddress, let batteryPercentage):
            let pct = Int(max(0, min(100, batteryPercentage)))
            updateSensor(deviceAddress: deviceAddress) { s in
                s.batteryPercentage = pct
                s.deviceAddress = deviceAddress
            }
            
        case .doorStatusEvent(let deviceAddress, let isDoorOpen, let isDisassembled):
            updateSensor(deviceAddress: deviceAddress) { s in
                s.isOpened = isDoorOpen
                s.isDisassembled = isDisassembled
            }
        @unknown default:
            break
        }
    }
    
    // MARK: - 锁回包
    public func lockCallback(didDecode response: LockAndSensor.LockResponse) {
        switch response {
        case .register(let qrCodeString, let deviceAddress, let isSuccess):
            upsertLock(Lock(qrCodeString: qrCodeString, isRegisterSuccess: isSuccess, deviceAddress: deviceAddress))
        case .tokenRecievedEvent(let deviceAddress, let token, let batteryPercentage):
            updateLock(deviceAddress: deviceAddress) { l in
                l.batteryPercentage = batteryPercentage
                l.tempToken = token
            }
            // write(token) // request temp token
            
        case .unlockResponseEvent(let deviceAddress, let isLocked):
            updateLock(deviceAddress: deviceAddress) { l in
                l.lockStatus = isLocked ? .normalClose : .normallyOpen
            }
        case .queryLockStatus(let deviceAddress, let isLocked):
            updateLock(deviceAddress: deviceAddress) { l in
                l.lockStatus = isLocked ? .normalClose : .normallyOpen
            }
            state.lock_isQueryingStatus = false
            
            // MARK: - Card
        case .addCardEvent(let deviceAddress, let isSuccess, let cardType):
            updateLock(deviceAddress: deviceAddress) { l in
                l.cardOpMessage = isSuccess
                    ? "Card added successfully ✅ (\(cardType == .ic ? "IC Card" : "ID Card"))"
                    : "Failed to add card ❌"
            }

        case .deleteAllCardEvent(let deviceAddress, let isSuccess):
            updateLock(deviceAddress: deviceAddress) { l in
                l.cardOpMessage = isSuccess
                    ? "All cards deleted ✅"
                    : "Failed to delete cards ❌"
            }

        case .queryCardCountEvent(let deviceAddress, let ic, let id):
            updateLock(deviceAddress: deviceAddress) { l in
                l.icCardCount = ic
                l.idCardCount = id
            }

            updateLock(deviceAddress: deviceAddress) { l in
                l.cardOpMessage = "Card count: IC=\(ic) | ID=\(id)"
            }
            
            // MARK: - OTP（保持你现有的实现）
        case .otpReceivedEvent(let otp, let expiredTime):
            self.state.otp_generating = false
            upsertOtpLock(Lock(qrCodeString: otp, expiredTime: expiredTime))
            
        case .otpInvalidateOTPEvent(let otp, let isSuccess):
            updateOtpLock(otp: otp) { ol in
                ol.isExpired = isSuccess
                ol.invalidating = false
            }
            
        case .otpLockStatusEvent(let otp, let isLocked):
            updateOtpLock(otp: otp) { ol in
                ol.lockStatus = isLocked ? .normalClose : .normallyOpen
            }
            
        case .macAddressAndTokenCommandEvent(let otp, let deviceAddress, let requestTokenCommand):
            if let deviceAddress, let requestTokenCommand {
                upsertOtpLock(
                    Lock(
                        qrCodeString: otp,
                        deviceAddress: deviceAddress,
                        requestTokenCommand: requestTokenCommand,
                        requestingTempToken: false,
                        requestTempTokenError: false
                    )
                )
            } else {
                // 超时
                upsertOtpLock(
                    Lock(
                        qrCodeString: otp,
                        deviceAddress: deviceAddress,
                        requestTokenCommand: requestTokenCommand,
                        requestingTempToken: false,
                        requestTempTokenError: true
                    )
                )
            }
            
            
        case .lockDataAndUnlockCommand(let otp, let unlockCommand, let batteryPercent):
            updateOtpLock(otp: otp) { ol in
                ol.unlockCommand = unlockCommand
                ol.batteryPercentage = batteryPercent
            }
        case .unknown:
            break
        @unknown default:
            break
        }
    }
}
