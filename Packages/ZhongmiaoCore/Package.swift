// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "ZhongmiaoCore",
    defaultLocalization: "zh-Hans",
    platforms: [
        .iOS(.v27),
        .macOS(.v27)
    ],
    products: [
        .library(name: "ZhongmiaoCore", targets: ["ZhongmiaoCore"]),
        .executable(name: "zm-catalog", targets: ["zm-catalog"])
    ],
    targets: [
        .target(
            name: "ZhongmiaoCore",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                // Swift 6.2 的诊断组控制：升级到 6.4 后把警告当错误。
                .treatAllWarnings(as: .error)
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
