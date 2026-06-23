---
name: lock_sensor_framework
description: This skill provides instructions and code snippets for integrating the Lock_Sensor-Framework using BLEManager in SwiftUI. Use this when you need to interact with smart locks, one-time passwords (OTP), or door/window sensors via Bluetooth. It is strictly for device interaction and state management, not for general UI styling.
---

# Lock & Sensor Framework Integration Guide

本指南提供了在 SwiftUI 视图中使用 `BLEManager` 与锁具、一次性密码 (OTP) 以及传感器进行交互的基础代码实现和高级管理方法。

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

## Prerequisites (前提准备)

在需要使用这些能力的 View 中，请确保导入框架并实例化 `BLEManager` 的 `StateObject`：

```swift
import iREdLockAndSensor
@StateObject var ble = BLEManager.shared
```

---

## 1. Lock (智能锁管理)

### 获取所有注册成功的锁具

```swift
List(ble.getLocks(), id: \.id) { lock in
    Text("QR Code String: \(lock.qrCodeString)")
}
```

### 单锁具基础用法

#### 1.1 锁具状态展示

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

#### 1.2 注册锁具

```swift
@State var qrCodeString: String = ""
@State var isRegisterSuccess: Bool = false

VStack {
    Text("Registration status：\(isRegisterSuccess ? "成功" : "失败")")
    Button(action: {
        Task {
            isRegisterSuccess = await ble.register(for: qrCodeString)
        }
    }) {
        Text("注册")
    }
}
```

#### 1.3 连接与断开蓝牙连接

```swift
// 连接锁具
ble.connect(identifier: qrCodeString)

// 断开锁具蓝牙连接
ble.disconnect(identifier: qrCodeString)
```

#### 1.4 触发开锁

```swift
ble.unlock(identifier: qrCodeString)
```

### 锁具高级管理

#### 2.1 查询锁具当前闭合状态

```swift
ble.queryStatus(identifier: qrCodeString)
```

#### 2.2 门禁卡管理

```swift
// 添加门禁卡 (触发后，建议显示“请将识别卡片靠近锁具识别区域”的提示框)
ble.addCard(identifier: qrCodeString) 

// 查询门禁卡数量
ble.queryCardCount(identifier: qrCodeString)

// 删除所有门禁卡
ble.deleteAllCard(identifier: qrCodeString)
```

#### 2.3 生成一次性密码（One Time Password）

```swift
Button(action: {
    ble.setOtpKey(otpKey: "LEO_KEY")
    // expiredTime 最大设定 30 天
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

#### 2.4 获取锁具的所有一次性密码记录

```swift
VStack {
    Text("OTP Lock List")

    if let lock = ble.getLock(identifier: qrCodeString) {
        ForEach(lock.otpList, id: \.id) { item in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OTP: \(item.otp)")
                    Text("过期时间: \(formatTimestamp(item.exp))")
                }
                Spacer()
                Button(action: {
                    UIPasteboard.general.string = item.otp
                }) {
                    Text("复制")
                }
            }
        }
    }
}
```

---

## 2. One Time Password (OTP 专用锁管理)

### OTP 基础用法

#### 1.1 用户填写 OTP 密码

```swift
@State var inputOTP: String = ""

TextField("请输入 OTP 密码", text: $inputOTP)
    .font(.system(.body, design: .monospaced))
    .padding()
    .background(Color(.systemGray6))
    .cornerRadius(10)
```

#### 1.2 获取 OTP 锁具状态

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

#### 1.3 注册 OTP 锁具

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

#### 1.4 连接与开锁

```swift
// 连接锁具
Button(action: {
     ble.connect(identifier: inputOTP)
}) {
    Text("connect")
}

// 执行开锁
Button(action: {
    ble.unlock(identifier: inputOTP)
}) {
    Text("unlock")
}
```

---

## 3. Sensor (门窗传感器管理)

### 单门窗传感器基础用法

#### 1.1 传感器状态展示

```swift
VStack(alignment: .leading) {
    if let sensor = ble.getSensor(identifier: qrCodeString) {
        Text("Battery: \(sensor.batteryPercentage)%")
        Text("Contact status: \(sensor.contactStatus.rawValue)")
        Text("Tamper status: \(sensor.tamperStatus.rawValue)")
    }
}
```

#### 1.2 注册传感器

```swift
@State var qrCodeString: String = ""
@State var isRegisterSuccess: Bool = false

VStack(alignment: .leading) {
    Text("Registration status：\(isRegisterSuccess ? "成功" : "失败")")
    Button(action: {
        Task {
            isRegisterSuccess = await ble.register(for: qrCodeString)
        }
    }) {
        Text("注册")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
    }
    .buttonStyle(.borderedProminent)
    .tint(.blue)
}
```

#### 1.3 开始监听传感器数据

```swift
Button(action: {
    ble.startListeningToSensor(qrCodeString: qrCodeString)
}) {
    Text("开始监听传感器")
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding()
}
.buttonStyle(.borderedProminent)
.tint(.green)
```

