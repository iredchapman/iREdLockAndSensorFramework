import Foundation

public struct iREdOtpLockModel: Identifiable {
    public var id: UUID = UUID()
    
    public var otp: String
    public var deviceAddress: String?
    public var expiredTime: Int?
    
    public var requestTokenCommand: Data?
    public var unlockCommand: Data?
    
    public var isInvalidateOTP: Bool? = false
    
    public var isExpired: Bool {
        guard let expired = expiredTime else { return false }
        let currentTimestamp = Int(Date().timeIntervalSince1970)
        return currentTimestamp > expired
    }
    
    public var batteryPercentage: Int = 0
    public var lockStatus: LockStatus = .unknown

    public var pairStatus: PairStatus = .notPair
    public var connectStatus: ConnectStatus = .unknown
    public var tempToken: Data?
    
    public var updatedAt: Date = Date()

    public init(otp: String, deviceAddress: String? = nil, requestTokenCommand: Data? = nil) {
        self.otp = otp
        self.deviceAddress = deviceAddress
        self.requestTokenCommand = requestTokenCommand
    }
}
