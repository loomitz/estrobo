// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Estrobo",
    platforms: [
        .macOS(.v13),
        .iOS(.v18),
    ],
    products: [
        .library(name: "EstroboCore", targets: ["EstroboCore"]),
        .library(name: "EstroboBluetooth", targets: ["EstroboBluetooth"]),
        .library(name: "EstroboPersistence", targets: ["EstroboPersistence"]),
    ],
    targets: [
        .target(
            name: "EstroboCore",
            path: "Sources/EstroboCore",
            swiftSettings: [.define("ESTROBO_CORE_TARGET")]
        ),
        .target(
            name: "EstroboBluetooth",
            dependencies: ["EstroboCore"],
            path: "Sources/EstroboBluetooth",
            linkerSettings: [.linkedFramework("CoreBluetooth")]
        ),
        .target(
            name: "EstroboPersistence",
            dependencies: ["EstroboCore"],
            path: "Sources/EstroboPersistence",
            linkerSettings: [.linkedFramework("Security")]
        ),
        .testTarget(
            name: "EstroboCoreTests",
            dependencies: ["EstroboCore"],
            path: "Tests/EstroboCoreTests"
        ),
        .testTarget(
            name: "EstroboBluetoothTests",
            dependencies: ["EstroboCore", "EstroboBluetooth"],
            path: "Tests/EstroboBluetoothTests"
        ),
        .testTarget(
            name: "EstroboPersistenceTests",
            dependencies: ["EstroboCore", "EstroboPersistence"],
            path: "Tests/EstroboPersistenceTests"
        ),
    ]
)
