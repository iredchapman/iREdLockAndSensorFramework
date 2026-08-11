import Foundation
import CoreBluetooth

public enum LockStatus: String, Codable, Sendable {
    case normallyOpen = "Normally Open"
    case normalClose = "Normal Close"
    case unknown = "Unknown"
}


public struct OTPBaseInfo: Codable, Identifiable {
    public var id: UUID = UUID()
    public var otp: String
    public var exp: Int
    
    private enum CodingKeys: String, CodingKey {
        case otp, exp
    }
    
    public init(otp: String, exp: Int) {
        self.otp = otp
        self.exp = exp
    }
}

public struct iREdLockModel: Identifiable {
    public var id: UUID = UUID()
    
    public var qrCodeString: String
    public var deviceAddress: String?
    
    public var batteryPercentage: Int = 0
    public var lockStatus: LockStatus = .unknown
    public var icCardCount: Int = 0
    public var idCardCount: Int = 0

    public var pairStatus: PairStatus = .notPair
    public var connectStatus: ConnectStatus = .unknown
    
    public var otpList: [OTPBaseInfo] = []
    
    public var updatedAt: Date? = Date()

    public init(qrCodeString: String, deviceAddress: String? = nil) {
        self.qrCodeString = qrCodeString
        self.deviceAddress = deviceAddress
    }
    
    public var blePeripheralInfo: BLEPeripheralInfo?
    public var isConnection: Bool = false
    public var customName: String = "Lock-\(Int.random(in: 10000...99999))"
    public var cardMessage: String = "Unknown"
}
