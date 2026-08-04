---
name: lock_sensor_framework
description: This skill provides instructions and code snippets for integrating the Lock_Sensor-Framework using BLEManager in SwiftUI. Use this when you need to interact with smart locks, one-time passwords (OTP), door/window sensors, or PIR motion sensors via Bluetooth. It is strictly for device interaction and state management, not for general UI styling.
---

# Lock & Sensor Framework 整合指南

本指南提供了在 SwiftUI 視圖中使用 `BLEManager` 與鎖具、一次性密碼 (OTP) 以及感應器進行互動的基礎代碼實現和高級管理方法。

## **權限設定（Info.plist / Capabilities）**


### **必填鍵值**


- Privacy - Bluetooth Always Usage Description

  例如：需要用藍牙連接鎖具和感應器

- Privacy - Camera Usage Description

  例如：用於掃描裝置二維碼


### **示例截圖**

<p align="center">
  <img src="https://github.com/iredchapman/iREdLockAndSensorFramework/blob/main/images/add_permissions.png?raw=true" width="500" alt="添加藍牙權限範例">
</p>


------

## Prerequisites (前提準備)

在需要使用這些功能的 View 中，請確保匯入框架並實例化 `BLEManager` 的 `StateObject`：

```swift
import iREdLockAndSensor
@StateObject var ble = BLEManager.shared
```

---

## 1. Lock (智能鎖管理)

### 步驟一：匯入框架與建立 ViewModel 綁定

`iREdLockAndSensor` 提供了單例物件 `BLEManager.shared` 用於集中管理藍牙互動。

在你的 `View` 中綁定藍牙管理器以及必要的輸入狀態變數：

```swift
struct LockView: View {
    // 綁定藍牙單例物件
    @StateObject var ble = BLEManager.shared
    
    // 輸入框綁定變數
    @State var qrCode: String = ""
    @State var invalidateOTPString: String = ""
    
    var body: some View {
        Form {
            // 後續步驟的控制項依次放入 Form 中
        }
    }
}
```

### 步驟二：實現裝置註冊功能

使用者輸入裝置二維碼字串（QR Code String）後，呼叫 `register(for:)` 異步方法完成鎖裝置的初始化註冊：

```swift
HStack {
    TextField("QR Code String", text: $qrCode)
    Button {
        Task {
            // 異步註冊鎖
            await ble.register(for: qrCode)
        }
    } label: {
        Text("Register Lock")
    }
}
```

### 步驟三：實現藍牙連接與基礎控制

透過走訪 `ble.locks` 獲取裝置列表，並針對單個鎖裝置綁定以下控制指令：

```swift
List(ble.locks) { lock in
    VStack(alignment: .leading, spacing: 4) {
        // 1. 基礎資訊展示
        Text("QR Code String: \(lock.qrCodeString.prefix(10)) ...")
        Text("Address: \(lock.deviceAddress ?? "Unknown")")
        Text("Pair Status: \(lock.pairStatus.rawValue)")
        Text("Connect Status: \(lock.connectStatus.rawValue)")
        Text("Battery: \(lock.batteryPercentage)")
        Text("Lock Status: \(lock.lockStatus.rawValue)")
        
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
}
```

### 步驟四：實現 IC/ID 卡管理

智能鎖支援讀取、清空及查詢卡片資訊：

```swift
// 1. 卡片數量資訊展示
Text("IC Card Count: \(lock.icCardCount)")
Text("ID Card Count: \(lock.idCardCount)")

// 2. 卡片操作按鈕組
HStack {
    // 進入錄卡模式
    Button("Add Card") {
        ble.addCard(identifier: lock.qrCodeString)
    }
    // 刪除所有已錄入的卡片
    Button("Delete All Cards") {
        ble.deleteAllCard(identifier: lock.qrCodeString)
    }
    // 查詢目前已儲存的卡片總數
    Button("Query number of Card Stored") {
        ble.queryCardCount(identifier: lock.qrCodeString)
    }
}
```

### 步驟五：實現 OTP 動態密碼生成與作廢

#### 1. 生成 OTP (生成 24 小時後過期的動態密碼)

傳入鎖標識及 Unix 時間戳記作為過期時間：

```swift
Button("Generate OTP") {
    let expiredTime = Int(Date().addingTimeInterval(86400).timeIntervalSince1970)
    Task {
        await ble.generateOTP(qrCodeString: lock.qrCodeString, expiredTime: expiredTime)
    }
}
```

#### 2. 作廢指定的 OTP

提供輸入框獲取目標 OTP 並呼叫作廢介面：

```swift
HStack {
    TextField(text: $invalidateOTPString, prompt: Text("Please enter the one-time password to be invalidated.")) {
        Text("Invalidate OTP")
    }
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

### 步驟六：初始化 OTP Key

在視圖載入（`.onAppear`）時，**必須**先設定應用程式的 OTP 金鑰：

```swift
.onAppear {
    ble.setOtpKey(otpKey: "CHANGE_THIS_KEY_FOR_YOUR_APP")
}
```

---



## 2. One Time Password (OTP 專用鎖管理)

### 步驟一：匯入框架與建立 View 狀態綁定

`iREdLockAndSensor` 的核心單例為 `BLEManager.shared`。

首先，在視圖中定義對 `BLEManager.shared` 的監聽，以及用於儲存輸入的 OTP 字串和註冊結果的本地狀態變數：

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
            // 後續步驟的 UI 元素放置於此
        }
    }
}
```

### 步驟二：實現 OTP 註冊功能

使用者在輸入框輸入一次性密碼（OTP）後，呼叫 `ble.register(for:)` 異步方法完成鎖的鑑權與註冊。

```swift
HStack {
    TextField("Input OTP", text: $inputOTP)
    Button {
        Task {
            // 異步提交 OTP 註冊，並更新註冊結果變數
            isRegisterSuccess = await ble.register(for: inputOTP)
        }
    } label: {
        Text("Register OTP")
    }
}

// 即時顯示註冊結果狀態
Text("Register Success: \(String(describing: isRegisterSuccess))")
```

### 步驟三：實現 OTP 鎖列表展示與狀態監聽

當透過 OTP 成功註冊鎖後，`ble.otpLocks` 陣列會自動包含該鎖的資訊。走訪該列表可以即時展示裝置狀態：

```swift
List(ble.otpLocks) { otpLock in
    // 配對狀態
    Text("Pair Status: \(otpLock.pairStatus.rawValue)")
    
    // 連接狀態
    Text("Connect Status: \(otpLock.connectStatus.rawValue)")
    
    // 電池電量
    Text("Battery: \(otpLock.batteryPercentage)")
    
    // 鎖開合狀態
    Text("Lock Status: \(otpLock.lockStatus.rawValue)")
    
    // ... 後續操作按鈕放置於此處
}
```

### 步驟四：實現藍牙連接與開鎖指令

針對列表中指定的 `otpLock`，使用其 `otp` 作為唯一識別碼（`identifier`）傳送藍牙指令：

```swift
HStack {
    // 1. 發起藍牙連接
    Button("Connect") {
        ble.connect(identifier: otpLock.otp)
    }
    
    // 2. 傳送解鎖指令
    Button("Unlock") {
        ble.unlock(identifier: otpLock.otp)
    }
}
.buttonStyle(.borderedProminent)
```

---



## 3. Sensor (門窗感應器管理)

### 步驟一：匯入框架與綁定 View 狀態

使用單例物件 `BLEManager.shared` 進行集中狀態管理。在 View 中建立綁定：

```swift
struct SensorView: View {
    // 監聽藍牙管理器單例
    @StateObject var ble = BLEManager.shared
    
    // 綁定二維碼輸入框字串
    @State var qrCode: String = ""
    
    var body: some View {
        Form {
            // 後續 UI 控制項依次放入 Form 中
        }
    }
}
```

### 步驟二：實現感應器註冊功能

使用者輸入感應器的二維碼字串（QR Code String）後，呼叫 `ble.register(for:)` 異步方法註冊裝置：

```swift
HStack {
    TextField("QR Code String", text: $qrCode)
    Button {
        Task {
            // 異步註冊感應器
            await ble.register(for: qrCode)
        }
    } label: {
        Text("Register Sensor")
    }
}
```

### 步驟三：實現感應器列表展示與數據監聽

註冊完成後，感應器物件會自動推入 `ble.sensors` 列表中。走訪該陣列，可以讀取並即時展示感應器的物理狀態與更新時間：

```swift
List(ble.sensors) { sensor in
    VStack(alignment: .leading, spacing: 4) {
        // 感應器基礎資訊與裝置地址
        Text("QR Code String: \(sensor.qrCodeString.prefix(10)) ...")
        Text("Address: \(sensor.deviceAddress ?? "Unknown")")
        
        // 電量與物理狀態（門磁觸點狀態、防拆防破壞狀態）
        Text("Battery: \(sensor.batteryPercentage)")
        Text("Contact Status: \(sensor.contactStatus.rawValue)")
        Text("Tamper Status: \(sensor.tamperStatus.rawValue)")
        
        // 數據最新更新時間戳記
        Text("Updated Time: \(String(describing: sensor.updatedAt))")
        
        // ... 控制按鈕放置於此處
    }
}
```

### 步驟四：控制廣播監聽狀態（開始 / 停止）

智能感應器主要透過藍牙廣播傳送狀態變更數據。使用感應器的 `qrCodeString` 標識開啟或停止對該裝置的廣播監聽：

```swift
HStack {
    // 開啟裝置廣播監聽
    Button("Start listening") {
        ble.startListeningToSensor(qrCodeString: sensor.qrCodeString)
    }
    
    // 停止裝置廣播監聽
    Button("Stop listening") {
        ble.stopListeningToSensor(qrCodeString: sensor.qrCodeString)
    }
}
.buttonStyle(.borderedProminent)
```

---

## 4. PIR Sensor (人體感應器管理)

### 步驟一：匯入框架與綁定 View 狀態

使用 `BLEManager.shared` 單例物件統一管理感應器狀態。在 View 中建立必要的狀態綁定：

```swift
struct PIRSensorView: View {
    // 監聽藍牙管理器單例
    @StateObject var ble = BLEManager.shared
    
    // 綁定二維碼輸入框字串
    @State var qrCode: String = ""
    
    var body: some View {
        Form {
            // 後續 UI 控制項依次放入 Form 中
        }
    }
}
```

### 步驟二：實現 PIR 感應器註冊功能

使用者輸入 PIR 感應器的二維碼字串（QR Code String）後，呼叫 `ble.register(for:)` 異步方法完成裝置註冊：

```swift
HStack {
    TextField("QR Code String", text: $qrCode)
    Button {
        Task {
            // 異步註冊 PIR 感應器
            await ble.register(for: qrCode)
        }
    } label: {
        Text("Register PIR Sensor")
    }
}
```

### 步驟三：實現數據監聽與環境多參數展示

註冊成功後，PIR 感應器物件會自動推入 `ble.pirSensors` 列表中。走訪該陣列，可以即時讀取感應器上報的環境與裝置狀態：

```swift
List(ble.pirSensors) { pirsensor in
    VStack(alignment: .leading, spacing: 4) {
        // 1. 基礎資訊與裝置地址
        Text("QR Code String: \(pirsensor.qrCodeString.prefix(10)) ...")
        Text("Address: \(pirsensor.deviceAddress ?? "Unknown")")
        
        // 2. 環境及狀態監測參數（包含預設空值備用處理）
        Text("Battery: \(pirsensor.battery ?? 0)")
        Text("PIR State: \(pirsensor.pirState ?? "Unknown")")  // 人體感應狀態
        Text("Humidity: \(pirsensor.humidity ?? 0)")           // 濕度
        Text("Lumens: \(pirsensor.lumens ?? 0)")               // 光照度 (流明)
        Text("Temperature: \(pirsensor.temperature ?? 0)")     // 溫度
        
        // 3. 三軸姿態數據 (XYZ Value)
        if let x = pirsensor.xValue, let y = pirsensor.yValue, let z = pirsensor.zValue {
            Text("XYZ value: \(x), \(y), \(z)")
        }
        
        // 4. 最新更新時間戳記
        Text("Updated Time: \(String(describing: pirsensor.lastUpdated))")
        
        // ... 控制按鈕放置於此處
    }
}
```

### 步驟四：控制廣播監聽狀態（開始 / 停止）

PIR 感應器透過藍牙廣播即時上報姿態與環境數據。使用感應器的 `qrCodeString` 標識控制是否開啟廣播監聽：

```swift
HStack {
    // 開啟對該 PIR 感應器的廣播監聽
    Button("Start listening") {
        ble.startListeningToSensor(qrCodeString: pirsensor.qrCodeString)
    }
    
    // 停止對該 PIR 感應器的廣播監聽
    Button("Stop listening") {
        ble.stopListeningToSensor(qrCodeString: pirsensor.qrCodeString)
    }
}
.buttonStyle(.borderedProminent)
```
