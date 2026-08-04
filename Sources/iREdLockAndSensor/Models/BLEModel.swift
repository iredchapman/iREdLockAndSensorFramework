import CoreBluetooth

public enum PairStatus: String, Codable, Sendable {
    case notPair = "Not Pair"
    case paired = "Paired"
    case pairing = "Pairing"
}

public enum ConnectStatus: String, Codable, Sendable {
    case unknown = "Unknown"
    case connected = "Connected"
    case connecting = "Connecting"
    case disconnected = "Disconnected"
    case connectionFailed = "Connection Failed"
}


public struct BLEPeripheralInfo {
    public var peripheral: CBPeripheral
    public var writeCharacteristic: CBCharacteristic?

    public init(
        peripheral: CBPeripheral,
        writeCharacteristic: CBCharacteristic? = nil
    ) {
        self.peripheral = peripheral
        self.writeCharacteristic = writeCharacteristic
    }
}


public extension String {
    /// 校验是否为有效的 MAC 地址
    var isValidMACAddress: Bool {
        // 匹配 00:1A:2B:3C:4D:5E 或 00-1A-2B-3C-4D-5E 或 001A2B3C4D5E
        let pattern = "^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$|^[0-9A-Fa-f]{12}$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(location: 0, length: utf16.count)
        return regex.firstMatch(in: self, options: [], range: range) != nil
    }
}
