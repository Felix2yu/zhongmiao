import XCTest

/// 真机冒烟：用调试种子直连本机起的临时服务，验证原生接入的读写链路。
///
/// 只在需要时手动跑：
/// ```
/// xcodegen generate
/// xcodebuild test -project Zhongmiao.xcodeproj -scheme ZhongmiaoUITests \
///   -destination 'platform=iOS,id=<UDID>' DEVELOPMENT_TEAM=<TEAM> -allowProvisioningUpdates
/// ```
/// 需要先把青野(18081)、牵丝(18080)、货殖(18082) 起在 `ZM_HOST` 上。
final class IntegrationSmokeTests: XCTestCase {

    private static let host = ProcessInfo.processInfo.environment["ZM_TEST_HOST"] ?? "192.168.0.15"

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ service: String, extra: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        var env = ["ZM_PREVIEW_SERVICE": service, "ZM_HOST": Self.host]
        env.merge(extra) { _, new in new }
        app.launchEnvironment = env
        app.launch()
        return app
    }

    /// 排查用：把当前界面结构打出来，方便定位元素。
    func testDumpTree() {
        let service = ProcessInfo.processInfo.environment["ZM_TEST_SERVICE"] ?? "qingye"
        let app = launch(service)
        _ = app.wait(for: .runningForeground, timeout: 10)
        Thread.sleep(forTimeInterval: 4)
        print("=== TREE BEGIN (\(service)) ===")
        print(app.debugDescription)
        print("=== TREE END ===")
    }
}
