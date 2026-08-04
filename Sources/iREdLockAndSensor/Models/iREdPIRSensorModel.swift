import Foundation

public struct PIRSensorDeviceModel: Identifiable {
    public let id: UUID = UUID()           // 设备的唯一标识符
    public var qrCodeString: String
    public var deviceAddress: String?          // 物理 MAC 地址
    public var battery: Int?               // 电池电量 (%)
    public var temperature: Double?        // 温度
    public var humidity: Double?           // 湿度
    public var xValue: Double?                // X轴加速度 (gee 单位)
    public var yValue: Double?                // Y轴加速度 (gee 单位)
    public var zValue: Double?                // Z轴加速度 (gee 单位)
    public var pirState: String?           // 红外感应状态
    public var name: String?               // 设备名称
    public var lumens: Int?                // 流明值
    public var rssi: Int = 0                   // 信号强度
    public var lastUpdated: Date           // 最近更新时间
    public var isListening: Bool = false    // 是否开启监听
    
    public var blePeripheralInfo: BLEPeripheralInfo?
    
    public init(
        qrCodeString: String,
        deviceAddress: String? = nil,
        battery: Int? = nil,
        temperature: Double? = nil,
        humidity: Double? = nil,
        xValue: Double? = nil,
        yValue: Double? = nil,
        zValue: Double? = nil,
        pirState: String? = nil,
        name: String? = nil,
        lumens: Int? = nil,
        rssi: Int = 0,
        lastUpdated: Date = Date(),
        isListening: Bool = false,
        blePeripheralInfo: BLEPeripheralInfo? = nil
    ) {
        self.qrCodeString = qrCodeString
        self.deviceAddress = deviceAddress
        self.battery = battery
        self.temperature = temperature
        self.humidity = humidity
        self.xValue = xValue
        self.yValue = yValue
        self.zValue = zValue
        self.pirState = pirState
        self.name = name
        self.lumens = lumens
        self.rssi = rssi
        self.lastUpdated = lastUpdated
        self.isListening = isListening
        self.blePeripheralInfo = blePeripheralInfo
    }
}
