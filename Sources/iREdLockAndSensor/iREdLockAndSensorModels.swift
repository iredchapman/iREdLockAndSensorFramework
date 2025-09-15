import Foundation
import CoreBluetooth

public enum PairStatus {
    case notPair, paired
}

public enum ConnectStatus {
    case connected, disconnected
}

public enum LockStatus {
    case normallyOpen
    case normalClose
}

public struct Lock {
    public let id: UUID = UUID()
    public var qrCodeString: String
    public var isRegisterSuccess: Bool = false
    public var isPairing: Bool = false
    public var deviceAddress: String?
    public var peripheral: CBPeripheral?
    public var writeCh: CBCharacteristic?
    public var notifyCh: CBCharacteristic?
    public var pairStatus: PairStatus = .notPair
    public var connectStatus: ConnectStatus = .disconnected
    
    public var tempToken: Data? = nil
    public var batteryPercentage: Int?
    public var lockStatus: LockStatus?
    
    public var icCardCount: Int?
    public var idCardCount: Int?
    
    public var requestTokenCommand: Data? = nil
    public var unlockCommand: Data? = nil
    public var cardOpMessage: String? = nil
    
    public var expiredTime: Int?
    public var isExpired: Bool = false
    
    // OTP
    public var requestingTempToken: Bool = false
    public var requestTempTokenError: Bool = false
    public var invalidating: Bool = false
    
    public var updatedAt: Date = Date()
    
    public var peripheralUUID: UUID? {
        peripheral?.identifier
    }
}
// 使用 qrCodeString 作为 OTP 存储，提供便捷访问器
public typealias OTPLock = Lock
extension OTPLock {
    public var otpString: String {
        get { qrCodeString }
        set { qrCodeString = newValue }
    }
}
public struct Status {
    public var ble_isOpenedBluetooth: Bool = false
    public var ble_isScanning: Bool = false
    public var ble_isConnecting: Bool = false
    
    public var lock_isQueryingStatus: Bool = false
    public var otp_generating: Bool = false
}

public struct Sensor: Identifiable, Equatable {
    public let id = UUID()
    public var qrCodeString: String
    public var isRegisterSuccess: Bool
    public var deviceAddress: String?
    public var batteryPercentage: Int?
    public var isOpened: Bool?
    public var isDisassembled: Bool?
    public var isScanning: Bool = false
    public var peripheral: CBPeripheral?
    
    public var updatedAt: Date = Date()
}

public enum DeviceType {
    case localLock(qrCodeString: String)
    case otpLock(otp: String)
    case sensor(qrCodeString: String)
}
