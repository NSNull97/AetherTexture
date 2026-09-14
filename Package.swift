// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AetherUI",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "AetherUI",
            targets: ["AetherUI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/SnapKit/SnapKit.git", from: "5.7.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
        .package(url: "https://github.com/FluidGroup/Texture.git", exact: "3.0.4")
    ],
    targets: [
        .target(
            name: "AetherUIBridging",
            dependencies: [
                .product(name: "AsyncDisplayKit", package: "Texture"),
            ],
            path: "Sources/AetherUIBridging",
            publicHeadersPath: "include",
            cSettings: [
//                .define("APPSTORE_SAFE", .when(configuration: .debug)),
//                .define("APPSTORE_SAFE", .when(configuration: .release))
            ]
        ),
        .target(
            name: "AetherUI",
            dependencies: [
                "AetherUIBridging",
                "SnapKit",
                .product(name: "AsyncDisplayKit", package: "Texture"),
            ],
            path: "Sources/AetherUI",
            resources: [
                .process("ListView/DustEffect/Metal")
            ],
            swiftSettings: [
//                .define("APPSTORE_SAFE", .when(configuration: .debug)),
//                .define("APPSTORE_SAFE", .when(configuration: .release))
            ]
        ),
        .testTarget(
            name: "AetherUITests",
            dependencies: ["AetherUI"],
            path: "Tests/AetherUITests",
            swiftSettings: [
//                .define("APPSTORE_SAFE", .when(configuration: .debug)),
//                .define("APPSTORE_SAFE", .when(configuration: .release))
            ]
        ),
    ]
)
