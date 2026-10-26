// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZhongmiaoCore",
    defaultLocalization: "zh-Hans",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "ZhongmiaoCore", targets: ["ZhongmiaoCore"]),
        .executable(name: "zm-catalog", targets: ["zm-catalog"])
    ],
    targets: [
        .target(
            name: "ZhongmiaoCore",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .executableTarget(
            name: "zm-catalog",
            dependencies: ["ZhongmiaoCore"]
        ),
        .testTarget(
            name: "ZhongmiaoCoreTests",
            dependencies: ["ZhongmiaoCore"]
        )
    ]
)
