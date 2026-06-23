import Foundation

public protocol DeviceIdentifiable: Identifiable {
    var id: UUID { get }
    var deviceAddress: String { get set }
    var updatedAt: Date? { get set }
}

public enum ContactStatus: String, Codable, Sendable {
    case closed = "Closed"
    case opened = "Opened"
    case unknown = "Unknown"
}

public enum TamperStatus: String, Codable, Sendable {
    case normal = "Normal"
    case tampered = "Tampered"
    case unknown = "Unknown"
}

public struct iREdSensorModel: DeviceIdentifiable, Equatable, Codable {
    public var id: UUID = UUID()
    
    public var qrCodeString: String
    public var deviceAddress: String

    public var batteryPercentage: Int = 0
    public var contactStatus: ContactStatus = .unknown
    public var tamperStatus: TamperStatus = .unknown
    
    public var updatedAt: Date? = Date()
    
    public var customName: String?
    public var customLabel: String?
    public var customDescription: String?
    
    private enum CodingKeys: String, CodingKey {
        case qrCodeString, deviceAddress
        case batteryPercentage, contactStatus, tamperStatus
        case updatedAt
        case customName, customLabel, customDescription
    }

    public init(qrCodeString: String, deviceAddress: String) {
        self.qrCodeString = qrCodeString
        self.deviceAddress = deviceAddress
    }
}
