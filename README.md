---
name: lock_sensor_framework
description: Provides comprehensive integration instructions and SwiftUI code snippets for the iREdLockAndSensor framework via BLEManager. Covers Bluetooth lifecycle management, device registration, OTP authentication, IC/ID card operations, real-time broadcast monitoring, custom device naming, device unbinding/removal, PIR motion & environmental telemetry (humidity, lumens, temperature, 3-axis motion), and MAC whitelist configuration for smart locks and IoT sensors.
---

# Lock & Sensor Framework 整合指南

本指南提供了在 SwiftUI 視圖中使用 `BLEManager` 與鎖具、一次性密碼 (OTP) 以及感應器進行互動的基礎代碼實現和高級管理方法，包含自訂裝置名稱、監聽狀態控制及裝置移除等最新功能。

------

## Prerequisites (前提準備)

在需要使用這些功能的 View 中，請確保匯入框架並實例化 `BLEManager` 的 `StateObject`：

```swift
import SwiftUI
import iREdLockAndSensor

@StateObject var ble = BLEManager.shared
```

---

## 1. Lock (智能鎖管理)

### 步驟一：匯入框架與建立 ViewModel 綁定

在你的 `View` 中綁定藍牙單例物件 `BLEManager.shared` 以及相關狀態變數：

```swift
struct LockView: View {
    // 綁定藍牙單例物件
    @StateObject var ble = BLEManager.shared
    
    // 輸入框與狀態變數
    @State var invalidateOTPString: String = ""
    @State var customName: String = ""
    @State var qrCode: String = ""
    
    var body: some View {
        VStack {
            List {
                // 控制項與列表內容
            }
        }
    }
}
```

### 步驟二：實現裝置註冊功能

使用者輸入鎖具二維碼字串（QR Code String）後，呼叫 `register(for:)` 異步方法完成鎖裝置的初始化註冊：

```swift
HStack {
    TextField("QR Code String", text: $qrCode)
    Button {
        Task {
            // 異步註冊鎖
            await ble.register(for: qrCode)
        }
    } label: {
        Text("Add Lock")
    }
    .buttonStyle(.borderedProminent)
}
```

### 步驟三：實現藍牙連接與基礎控制

走訪 `ble.locks` 獲取裝置列表，並展示名稱及控制指令：

```swift
ForEach(ble.locks) { lock in
    VStack(alignment: .leading, spacing: 12) {
        // 1. 基礎資訊展示（包含自訂名稱）
        VStack(alignment: .leading) {
            Text("Name: \(lock.customName)")
            Text("Connect Status: \(lock.connectStatus.rawValue)")
            Text("Battery: \(lock.batteryPercentage)")
            Text("Lock Status: \(lock.lockStatus.rawValue)")
            Text("IC Card Count: \(lock.icCardCount)")
            Text("ID Card Count: \(lock.idCardCount)")
            Text("Card Message: \(lock.cardMessage)")
            Text("Updated Time: \(String(describing: lock.updatedAt))")
        }
        
        // 2. 連接 / 斷開連接
        HStack {
            Button("Connect") {
                ble.connect(identifier: lock.qrCodeString)
            }
            Button("Disconnect") {
                ble.disconnect(identifier: lock.qrCodeString)
            }
        }
        
        // 3. 開鎖 / 查詢狀態
        HStack {
            Button("Unlock") {
                ble.unlock(identifier: lock.qrCodeString)
            }
            Button("Query Status") {
                ble.queryStatus(identifier: lock.qrCodeString)
            }
        }
    }
    .buttonStyle(.borderedProminent)
}
```

### 步驟四：實現 IC/ID 卡管理

智能鎖支援讀取、清空及查詢卡片資訊：

```swift
// 1. 卡片資訊與反饋展示
Text("IC Card Count: \(lock.icCardCount)")
Text("ID Card Count: \(lock.idCardCount)")
Text("Card Message: \(lock.cardMessage)")

// 2. 卡片操作按鈕組
VStack(alignment: .leading) {
    HStack {
        // 進入錄卡模式
        Button("Add Card") {
            ble.addCard(identifier: lock.qrCodeString)
        }
        // 刪除所有已錄入的卡片
        Button("Delete All Cards") {
            ble.deleteAllCard(identifier: lock.qrCodeString)
        }
    }
    
    // 查詢目前已儲存的卡片總數
    Button("Query number of Card Stored") {
        ble.queryCardCount(identifier: lock.qrCodeString)
    }
}
```

### 步驟五：設定自訂名稱 (`setName`)

傳入裝置二維碼標識及自訂名稱：

```swift
HStack {
    TextField("Set a custom name", text: $customName)
        .textFieldStyle(.roundedBorder)
    Button("Confirm") {
        ble.setName(for: lock.qrCodeString, name: customName)
    }
}
```

### 步驟六：移除 / 解綁裝置 (`remove`)

呼叫 `ble.remove(for:)` 即可刪除指定的鎖裝置：

```swift
Button(role: .destructive) {
    ble.remove(for: lock.qrCodeString)
} label: {
    Text("Remove")
}
```

### 步驟七：實現 OTP 動態密碼生成與作廢

#### 1. 生成 OTP (生成 24 小時後過期的動態密碼)

```swift
Button("Generate OTP") {
    let expiredTime = Int(Date().addingTimeInterval(86400).timeIntervalSince1970)
    Task {
        await ble.generateOTP(qrCodeString: lock.qrCodeString, expiredTime: expiredTime)
    }
}
```

#### 2. 作廢指定的 OTP

```swift
VStack(alignment: .leading) {
    TextField(text: $invalidateOTPString, prompt: Text("Please enter the one-time password to be invalidated.")) {
        Text("Invalidate OTP")
    }
    .textFieldStyle(.roundedBorder)
    Button("Invalidate OTP") {
        ble.invalidateOTP(otp: invalidateOTPString)
    }
}
```

#### 3. 展示裝置目前的 OTP 列表

```swift
List(lock.otpList) { otp in
    HStack {
        Text(otp.otp).textSelection(.enabled)
        let dateString = DateFormatter.localizedString(
            from: Date(timeIntervalSince1970: TimeInterval(otp.exp)), 
            dateStyle: .medium, 
            timeStyle: .medium
        )
        Text("Exp Date: \(dateString)")
    }
}
```

### 步驟八：初始化 OTP Key

在視圖載入（`.onAppear`）時，**必須**先設定應用程式的 OTP 金鑰：

```swift
.onAppear {
    ble.setOtpKey(otpKey: "CHANGE_THIS_KEY_FOR_YOUR_APP")
}
```

---

## 2. One Time Password (OTP 專用鎖管理)

### 步驟一：匯入框架與建立 View 狀態綁定

```swift
struct OTPLockView: View {
    // 監聽藍牙單例物件
    @StateObject var ble = BLEManager.shared
    
    // 使用者輸入的 OTP 密碼
    @State var inputOTP: String = ""
    
    // 註冊結果狀態標記
    @State var isRegisterSuccess: Bool = false
    
    var body: some View {
        Form {
            // UI 內容
        }
    }
}
```

### 步驟二：實現 OTP 註冊功能

使用者輸入一次性密碼（OTP）後，呼叫 `ble.register(for:)` 異步方法完成鎖的解鎖與註冊：

```swift
HStack {
    TextField("Input OTP", text: $inputOTP)
    Button {
        Task {
            isRegisterSuccess = await ble.register(for: inputOTP)
        }
    } label: {
        Text("Add OTP")
    }
}

// 即時顯示註冊結果狀態
Text("Register Success: \(String(describing: isRegisterSuccess))")
```

### 步驟三：實現 OTP 鎖列表展示與藍牙連接解鎖

走訪 `ble.otpLocks` 列表展示裝置狀態，並透過 OTP 識別碼傳送控制指令：

```swift
List(ble.otpLocks) { otpLock in
    Text("Pair Status: \(otpLock.pairStatus.rawValue)")
    Text("Connect Status: \(otpLock.connectStatus.rawValue)")
    Text("Battery: \(otpLock.batteryPercentage)")
    Text("Lock Status: \(otpLock.lockStatus.rawValue)")
    
    HStack {
        Button("Connect") {
            ble.connect(identifier: otpLock.otp)
        }
        
        Button("Unlock") {
            ble.unlock(identifier: otpLock.otp)
        }
    }
    .buttonStyle(.borderedProminent)
}
```

---

## 3. Sensor (門窗感應器管理)

### 步驟一：匯入框架與綁定 View 狀態

```swift
struct SensorView: View {
    @StateObject var ble = BLEManager.shared
    @State var qrCode: String = ""
    @State var customName: String = ""
    
    var body: some View {
        VStack {
            List {
                // UI 內容
            }
        }
    }
}
```

### 步驟二：實現感應器註冊功能

使用者輸入感應器二維碼字串（QR Code String）後，呼叫 `ble.register(for:)` 異步方法註冊裝置：

```swift
HStack {
    TextField("QR Code String", text: $qrCode)
    Button {
        Task {
            await ble.register(for: qrCode)
        }
    } label: {
        Text("Add Sensor")
    }
    .buttonStyle(.borderedProminent)
}
```

### 步驟三：實現感應器列表展示與數據監聽

走訪 `ble.sensors` 列表，展示包含自訂名稱、門磁與防拆狀態，以及**廣播監聽狀態 (`isListening`)**：

```swift
ForEach(ble.sensors) { sensor in
    VStack(alignment: .leading, spacing: 4) {
        Text("Name: \(sensor.customName)")
        Text("Battery: \(sensor.batteryPercentage)")
        Text("Contact Status: \(sensor.contactStatus.rawValue)")
        Text("Tamper Status: \(sensor.tamperStatus.rawValue)")
        Text("Monitoring status: \(String(describing: sensor.isListening))")
        Text("Updated Time: \(String(describing: sensor.updatedAt))")
        
        // ... 控制按鈕
    }
}
```

### 步驟四：控制廣播監聽狀態（開始 / 停止）

使用感應器的 `qrCodeString` 標識控制開啟或停止廣播數據監聽：

```swift
HStack {
    Button("Start listening") {
        ble.startListeningToSensor(qrCodeString: sensor.qrCodeString)
    }
    
    Button("Stop listening") {
        ble.stopListeningToSensor(qrCodeString: sensor.qrCodeString)
    }
}
.buttonStyle(.borderedProminent)
```

### 步驟五：設定自訂名稱 (`setName`)

```swift
HStack {
    TextField("Set a custom name", text: $customName)
        .textFieldStyle(.roundedBorder)
    Button("Confirm") {
        ble.setName(for: sensor.qrCodeString, name: customName)
    }
}
```

### 步驟六：移除 / 解綁感應器 (`remove`)

```swift
Button(role: .destructive) {
    ble.remove(for: sensor.qrCodeString)
} label: {
    Text("Remove")
}
```

---

## 4. PIR Sensor (人體感應器管理)

### 步驟一：匯入框架與綁定 View 狀態

```swift
struct PIRSensorView: View {
    @StateObject var ble = BLEManager.shared
    @State var qrCode: String = ""
    @State var customName: String = ""
    
    var body: some View {
        VStack {
            List {
                // UI 內容
            }
        }
    }
}
```

### 步驟二：實現 PIR 感應器註冊功能

使用者輸入 PIR 感應器二維碼字串（QR Code String）後，呼叫 `ble.register(for:)` 異步方法完成裝置註冊：

```swift
HStack {
    TextField("QR Code String", text: $qrCode)
    Button {
        Task {
            await ble.register(for: qrCode)
        }
    } label: {
        Text("Add PIR Sensor")
    }
    .buttonStyle(.borderedProminent)
}
```

### 步驟三：實現數據監聽與環境多參數展示 (包含物理單位)

走訪 `ble.pirSensors` 列表，展示人體感應狀態、濕度（`%`）、光照度（`lx`）、溫度（`℃`）、XYZ 姿態數據及監聽狀態（`isListening`）：

```swift
ForEach(ble.pirSensors) { pirsensor in
    VStack(alignment: .leading, spacing: 4) {
        Text("Name: \(pirsensor.customName)")
        Text("Battery: \(pirsensor.battery ?? 0)")
        Text("PIR State: \(pirsensor.pirState ?? "Unknown")")
        Text("Humidity: \(pirsensor.humidity ?? 0) %")
        Text("Lumens: \(pirsensor.lumens ?? 0) lx")
        Text("Temperature: \(pirsensor.temperature ?? 0) ℃")
        Text("Monitoring status: \(String(describing: pirsensor.isListening))")
        
        if let x = pirsensor.xValue, let y = pirsensor.yValue, let z = pirsensor.zValue {
            Text("XYZ value: \(x), \(y), \(z)")
        }
        
        Text("Updated Time: \(String(describing: pirsensor.lastUpdated))")
    }
    .buttonStyle(.borderedProminent)
}
```

### 步驟四：控制廣播監聽狀態（開始 / 停止）

```swift
HStack {
    Button("Start listening") {
        ble.startListeningToSensor(qrCodeString: pirsensor.qrCodeString)
    }
    
    Button("Stop listening") {
        ble.stopListeningToSensor(qrCodeString: pirsensor.qrCodeString)
    }
}
```

### 步驟五：設定自訂名稱 (`setName`)

```swift
HStack {
    TextField("Set a custom name", text: $customName)
        .textFieldStyle(.roundedBorder)
    Button("Confirm") {
        ble.setName(for: pirsensor.qrCodeString, name: customName)
    }
}
```

### 步驟六：移除 / 解綁 PIR 感應器 (`remove`)

```swift
Button(role: .destructive) {
    ble.remove(for: pirsensor.qrCodeString)
} label: {
    Text("Remove")
}
```

