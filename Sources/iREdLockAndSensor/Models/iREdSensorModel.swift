import Foundation

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

public struct iREdSensorModel: Identifiable {
    public var id: UUID = UUID()
    
    public var qrCodeString: String
    public var deviceAddress: String? = nil

    public var batteryPercentage: Int = 0
    public var contactStatus: ContactStatus = .unknown
    public var tamperStatus: TamperStatus = .unknown
    
    public var updatedAt: Date? = Date()

    public init(qrCodeString: String, deviceAddress: String? = nil) {
        self.qrCodeString = qrCodeString
        self.deviceAddress = deviceAddress
    }
    
    public var blePeripheralInfo: BLEPeripheralInfo?
    public var isListening: Bool = false
    public var customName: String = "Door Sensor-\(Int.random(in: 10000...99999))"
}
