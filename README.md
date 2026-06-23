---
name: lock_sensor_framework
description: This skill provides instructions and code snippets for integrating the Lock_Sensor-Framework using BLEManager in SwiftUI. Use this when you need to interact with smart locks, one-time passwords (OTP), or door/window sensors via Bluetooth. It is strictly for device interaction and state management, not for general UI styling.
---

# Lock & Sensor Framework Integration Guide

本指南提供了在 SwiftUI 視圖中使用 `BLEManager` 與鎖具、一次性密碼 (OTP) 以及傳感器進行互動的基礎代碼實現和高級管理方法。

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

## Prerequisites (前提準備)

在需要使用這些能力的 View 中，請確保導入框架並實例化 `BLEManager` 的 `StateObject`：

```swift
import iREdLockAndSensor
@StateObject var ble = BLEManager.shared
```

---

## 1. Lock (智能鎖管理)

### 獲取所有註冊成功的鎖具

```swift
List(ble.getLocks(), id: \.id) { lock in
    Text("QR Code String: \(lock.qrCodeString)")
}
```

### 單鎖具基礎用法

#### 1.1 鎖具狀態展示

```swift
VStack(alignment: .leading) {
    if let lock = ble.getLock(identifier: qrCodeString) {
        Text("Pairing status：\(lock.pairStatus.rawValue)")
        Text("Connection status：\(lock.connectStatus.rawValue)")
        Text("Battery：\(lock.batteryPercentage)%")
        Text("Lock status：\(lock.lockStatus.rawValue)")
        Text("IC Card Count：\(lock.icCardCount)")
        Text("ID Card Count：\(lock.idCardCount)")
    }
}
```

#### 1.2 註冊鎖具

```swift
@State var qrCodeString: String = ""
@State var isRegisterSuccess: Bool = false

VStack {
    Text("Registration status：\(isRegisterSuccess ? "成功" : "失敗")")
    Button(action: {
        Task {
            isRegisterSuccess = await ble.register(for: qrCodeString)
        }
    }) {
        Text("註冊")
    }
}
```

#### 1.3 連接與斷開藍牙連接

```swift
// 連接鎖具
ble.connect(identifier: qrCodeString)

// 斷開鎖具藍牙連接
ble.disconnect(identifier: qrCodeString)
```

#### 1.4 觸發開鎖

```swift
ble.unlock(identifier: qrCodeString)
```

### 鎖具高級管理

#### 2.1 查詢鎖具當前閉合狀態

```swift
ble.queryStatus(identifier: qrCodeString)
```

#### 2.2 門禁卡管理

```swift
// 添加門禁卡 (觸發後，建議顯示「請將識別卡片靠近鎖具識別區域」的提示框)
ble.addCard(identifier: qrCodeString) 

// 查詢門禁卡數量
ble.queryCardCount(identifier: qrCodeString)

// 刪除所有門禁卡
ble.deleteAllCard(identifier: qrCodeString)
```

#### 2.3 生成一次性密碼（One Time Password）

```swift
Button(action: {
    ble.setOtpKey(otpKey: "LEO_KEY")
    // expiredTime 最大設定 30 天
    let sevenDayExp = Int(Date().addingTimeInterval(7 * 24 * 60 * 60).timeIntervalSince1970)
    Task {
        isGeneratingOTP = true
        isGeneratedOTPSuccess = await ble.generateOTP(qrCodeString: qrCodeString, expiredTime: sevenDayExp) 
        isGeneratingOTP = false
    }
}) {
    HStack(spacing: 6) {
        if isGeneratingOTP {
            ProgressView()
        }
        Text("生成OTP")
    }
}
```

#### 2.4 獲取鎖具的所有一次性密碼記錄

```swift
VStack {
    Text("OTP Lock List")

    if let lock = ble.getLock(identifier: qrCodeString) {
        ForEach(lock.otpList, id: \.id) { item in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OTP: \(item.otp)")
                    Text("過期時間: \(formatTimestamp(item.exp))")
                }
                Spacer()
                Button(action: {
                    UIPasteboard.general.string = item.otp
                }) {
                    Text("複製")
                }
            }
        }
    }
}
```

---

## 2. One Time Password (OTP 專用鎖管理)

### OTP 基礎用法

#### 1.1 用戶填寫 OTP 密碼

```swift
@State var inputOTP: String = ""

TextField("請輸入 OTP 密碼", text: $inputOTP)
    .font(.system(.body, design: .monospaced))
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(10)
```

#### 1.2 獲取 OTP 鎖具狀態

```swift
VStack(alignment: .leading) {
    if let lock = ble.getOtpLock(otp: inputOTP) {
        Text("Pairing status：\(lock.pairStatus.rawValue)")
        Text("Connection status：\(lock.connectStatus.rawValue)")
        Text("Device Address：\(lock.deviceAddress ?? "Unknown")")
        Text("Battery：\(lock.batteryPercentage)%")
        Text("Lock status：\(lock.lockStatus.rawValue)")
    }
}
```

#### 1.3 註冊 OTP 鎖具

```swift
VStack(alignment: .leading) {
    Text("Register status：\(isRegisterSuccess ? "Success" : "Failure")")
    Button(action: {
        Task {
            isRegistering = true
            isRegisterSuccess = await ble.register(for: inputOTP)
            isRegistering = false
        }
    }) {
        if isRegistering {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .frame(maxWidth: .infinity)
                .padding()
        } else {
            Text("register OTP")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
    }
    .buttonStyle(.borderedProminent)
    .tint(.blue)
    .disabled(isRegistering)
}
```

#### 1.4 連接與開鎖

```swift
// 連接鎖具
Button(action: {
     ble.connect(identifier: inputOTP)
}) {
    Text("connect")
}

// 執行開鎖
Button(action: {
    ble.unlock(identifier: inputOTP)
}) {
    Text("unlock")
}
```

---

## 3. Sensor (門窗傳感器管理)

### 單門窗傳感器基礎用法

#### 1.1 傳感器狀態展示

```swift
VStack(alignment: .leading) {
    if let sensor = ble.getSensor(identifier: qrCodeString) {
        Text("Battery: \(sensor.batteryPercentage)%")
        Text("Contact status: \(sensor.contactStatus.rawValue)")
        Text("Tamper status: \(sensor.tamperStatus.rawValue)")
    }
}
```

#### 1.2 註冊傳感器

```swift
@State var qrCodeString: String = ""
@State var isRegisterSuccess: Bool = false

VStack(alignment: .leading) {
    Text("Registration status：\(isRegisterSuccess ? "成功" : "失敗")")
    Button(action: {
        Task {
            isRegisterSuccess = await ble.register(for: qrCodeString)
        }
    }) {
        Text("註冊")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
    }
    .buttonStyle(.borderedProminent)
    .tint(.blue)
}
```

#### 1.3 開始監聽傳感器數據

```swift
Button(action: {
    ble.startListeningToSensor(qrCodeString: qrCodeString)
}) {
    Text("開始監聽傳感器")
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding()
}
.buttonStyle(.borderedProminent)
.tint(.green)
```
