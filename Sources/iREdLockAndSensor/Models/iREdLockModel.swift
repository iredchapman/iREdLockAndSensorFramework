import Foundation

// 状态枚举保持不变
public enum LockStatus: String, Codable, Sendable {
    case normallyOpen = "Normally Open"
    case normalClose = "Normal Close"
    case unknown = "Unknown"
}


public struct OTPBaseInfo: Codable, Identifiable {
    public var id: UUID = UUID()
    public var otp: String
    public var exp: Int
    public var name: String?
    public var label: String?
    public var description: String?
    
    private enum CodingKeys: String, CodingKey {
        case otp, exp, name, label, description
    }
}

// 终极扁平版的锁模型
public struct iREdLockModel: Codable, Identifiable {
    public var id: UUID = UUID()
    
    public var qrCodeString: String
    public var deviceAddress: String?
    
    public var batteryPercentage: Int = 0
    public var lockStatus: LockStatus = .unknown
    public var icCardCount: Int = 0
    public var idCardCount: Int = 0

    public var pairStatus: PairStatus = .notPair
    public var connectStatus: ConnectStatus = .unknown
    public var tempToken: Data?
    
    // --- 原 CustomInfo (自定义信息) ---
    // (如果里面有具体字段，直接写在这里，比如 var customName: String?)
    
    // --- 临时密码列表 ---
    public var otpList: [OTPBaseInfo] = []
    
    public var updatedAt: Date? = Date()

    public init(qrCodeString: String, deviceAddress: String? = nil) {
        self.qrCodeString = qrCodeString
        self.deviceAddress = deviceAddress
    }
}
