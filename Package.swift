// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "iREdLockAndSensor",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "iREdLockAndSensor",
            targets: ["iREdLockAndSensor"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "iREdLockAndSensor",
            dependencies: ["iREdLockAndSensorFramework"],
            path: "Sources",
            swiftSettings: [
                .define("IREDLOCKANDSENSOR_FRAMEWORK")
            ]
        ),
        .binaryTarget(
            name: "iREdLockAndSensorFramework",
            path: "./Frameworks/iREdLockAndSensorFramework.xcframework"
        )

    ]
)
