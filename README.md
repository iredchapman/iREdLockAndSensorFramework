# **iREdLockAndSensorFramework**


面向 iOS 嘅 BLE 鎖具 & 傳感器統一通訊框架。
支援 **本地二維碼鎖、OTP 一次性密碼鎖、門磁傳感器** 等裝置嘅 **配對、連接、指令下發同數據解析**，並且提供 SwiftUI 友善嘅狀態模型。
**最低系統版本**：iOS 17+

------

## **安裝方式（SPM）**

喺 Xcode 入面：

**File Add Package Dependency…**

輸入：

```
https://github.com/iredchapman/iREdLockAndSensorFramework.git
```

揀返主 App target，打咗剔就可以加依賴。

------


## **權限設定（Info.plist / Capabilities）**


### **必填鍵值**


- Privacy - Bluetooth Always Usage Description

  例如：需要用藍牙連接鎖具同傳感器

- Privacy - Camera Usage Description

  例如：用嚟掃裝置二維碼


### **示例截圖**

<p align="center">
  <img src="https://github.com/iredchapman/iREdLockAndSensorFramework/blob/main/images/add_permissions.png?raw=true" width="500" alt="添加藍牙權限範例">
</p>


------

## **1. 獲取藍牙實例**

```swift
@StateObject var ble = iREdLockAndSensorBluetooth.shared
```

內置單例 shared 已經包咗喺主線程，可以直接用喺 SwiftUI 數據綁定。

------

## **2. 本地二維碼鎖（Lock）**

```swift
// 註冊鎖（導入二維碼）
ble.registerLock(qrCodeString: "<your-qr")

// 掃描同配對
ble.startScan(device: .localLock(qrCodeString: "<your-qr"))

// 連接鎖
ble.connect(to: .localLock(qrCodeString: "<your-qr"))

// 常用操作
ble.fetchTempToken(qrCodeString: "<your-qr")
ble.unlock(qrCodeString: "<your-qr")
ble.queryStatus(qrCodeString: "<your-qr")

// 斷開
ble.disconnect(.localLock(qrCodeString: "<your-qr"))
```

```swift
// 打印 Lock 全部狀態屬性示例
if let lock = ble.lockData.first {
    print("isRegisterSuccess: \(lock.isRegisterSuccess)")         // 是否已經註冊成功
    print("isPairing: \(lock.isPairing)")                         // 是否處於配對中
    print("pairStatus: \(lock.pairStatus)")                       // 配對狀態
    print("connectStatus: \(lock.connectStatus)")                 // 鎖當前連接狀態
    print("tempToken: \(lock.tempToken)")                         // 臨時令牌
    print("batteryPercentage: \(lock.batteryPercentage)")         // 電池電量百分比
    print("lockStatus: \(lock.lockStatus)")                       // 鎖的狀態（開鎖或關鎖）
    print("icCardCount: \(lock.icCardCount)")                     // IC 卡數量
    print("idCardCount: \(lock.idCardCount)")                     // 身份證卡數量
    print("cardOpMessage: \(lock.cardOpMessage)")                 // 卡操作信息
}
```
------

## **3. OTP 鎖**

```swift
// 設定 OTP Key（建議 App 啟動時叫一次）
ble.setOtpKey(otpKey: "<your-otp-key")

// 產生 OTP（有效期 = 秒級時間戳）
let expire = Int(Date().addingTimeInterval(600).timeIntervalSince1970)
ble.generateOTP(qrCodeString: "<your-qr", expiredTime: expire)

// 已有 OTP（手動輸入或者產生）
let otp = "<your-otp"

// 獲取 MAC & 臨時指令
ble.getMACAddressAndTokenCommand(otp: otp)

// 配對 & 連接
ble.startScan(device: .otpLock(otp: otp))
ble.connect(to: .otpLock(otp: otp))

// 請求臨時 Token + 電量
ble.requestTokenOTP(otp: otp)

// 開鎖
ble.unlockOTP(otp: otp)

// 失效 OTP
ble.invalidateOTP(otp: otp)
```

```swift
// 打印 OTP Lock 全部狀態屬性示例
if let otpLock = ble.otpLockData.first {
    print("pairStatus: \(otpLock.pairStatus)")                     // 配對狀態
    print("connectStatus: \(otpLock.connectStatus)")               // 連接狀態
    print("deviceAddress: \(otpLock.deviceAddress)")               // 裝置地址
    print("batteryPercentage: \(otpLock.batteryPercentage)")       // 電池百分比
    print("lockStatus: \(otpLock.lockStatus)")                     // 鎖狀態
    print("isExpired: \(otpLock.isExpired)")                       // 是否已過期
    print("requestingTempToken: \(otpLock.requestingTempToken)")   // 是否正在請求臨時令牌
    print("requestTempTokenError: \(otpLock.requestTempTokenError)") // 請求臨時令牌錯誤
    print("invalidating: \(otpLock.invalidating)")                 // 是否正在失效中
}
```

------

## **4. 傳感器（Sensor）**

```swift
// 註冊傳感器
ble.registerSensor(qrCodeString: "<your-qr")

// 開始/停止掃描
ble.startScan(device: .sensor(qrCodeString: "<your-qr"))
ble.stopScan(for: .sensor(qrCodeString: "<your-qr"))

// 刪除傳感器
ble.remove(device: .sensor(qrCodeString: "<your-qr"))
```

```swift
// 打印 Sensor 全部狀態屬性示例
if let sensor = ble.sensorData.first {
    print("isRegisterSuccess: \(sensor.isRegisterSuccess)")       // 是否已註冊成功
    print("isScanning: \(sensor.isScanning)")                     // 是否正在掃描中
    print("deviceAddress: \(sensor.deviceAddress)")               // 裝置地址
    print("batteryPercentage: \(sensor.batteryPercentage)")       // 電池電量百分比
    print("isOpened: \(sensor.isOpened)")                         // 門磁是否打開
    print("isDisassembled: \(sensor.isDisassembled)")             // 是否被拆卸
}
```

傳感器廣播可以即時更新：

- 電池電量（batteryPercentage）
- 門磁狀態（isOpened）
- 拆卸警報（isDisassembled）
------

## **5. 狀態同數據監聽**

你可以透過存取裝置數據模型去監聽同讀取裝置嘅狀態資訊，例如配對狀態（pairStatus）、連接狀態（connectStatus）、鎖狀態（lockStatus）等。
```swift
// 藍牙整體狀態
ble.state.ble_isOpenedBluetooth   // 有冇開啟
ble.state.ble_isScanning          // 掃描緊冇
ble.state.otp_generating          // 係咪生成緊 OTP
```

```swift
// 讀取本地二維碼鎖狀態
if let lock = ble.lockData.first {
    print("Lock pair status: \(lock.pairStatus)")
    print("Lock connect status: \(lock.connectStatus)")
    print("Lock status: \(lock.lockStatus)")
}

// 讀取 OTP 鎖狀態
if let otpLock = ble.otpLockData.first {
    print("OTP Lock pair status: \(otpLock.pairStatus)")
    print("OTP Lock connect status: \(otpLock.connectStatus)")
    print("OTP Lock lock status: \(otpLock.lockStatus)")
}

// 讀取傳感器狀態
if let sensor = ble.sensorData.first {
    print("Sensor pair status: \(sensor.pairStatus)")
    print("Sensor connect status: \(sensor.connectStatus)")
    print("Sensor lock status: \(sensor.lockStatus)")
}
```
------
