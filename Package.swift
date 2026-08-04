// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.
// 需要导出 XCFramework 时，需要将以下注释内容取消，并在 BluetoothManager.swift 顶部的 import 解开注释

import PackageDescription

let package = Package(
    name: "iREdLockAndSensor",
    platforms: [.iOS(.v17), .macOS(.v15)],
    products: [
        .library(
            name: "iREdLockAndSensor",
            type: .dynamic,
            targets: ["iREdLockAndSensor"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "iREdLockAndSensor",
            dependencies: ["LockAndSensorFramework"],
            path: "Sources",
            swiftSettings: [
                .define("LOCKANDSENSOR_FRAMEWORK")
            ]
        ),
        .binaryTarget(
            name: "LockAndSensorFramework",
            path: "Frameworks/LockAndSensorFramework.xcframework"
        )

    ]
)
