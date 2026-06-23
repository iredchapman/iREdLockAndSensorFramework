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
            dependencies: ["iREdSecureLinkFramework"],
            path: "Sources",
            swiftSettings: [
                .define("IREDSECURELINK_FRAMEWORK")
            ]
        ),
        .binaryTarget(
            name: "iREdSecureLinkFramework",
            path: "Frameworks/iREdSecureLinkFramework.xcframework"
        )

    ]
)
