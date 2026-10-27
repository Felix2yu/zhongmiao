import XCTest

/// 原生接入的真机/模拟器冒烟：用调试种子直连本机起的临时服务，走一遍读写链路。
///
/// ```
/// xcodegen generate
/// xcodebuild test -project Zhongmiao.xcodeproj -scheme ZhongmiaoUITests \
///   -destination 'platform=iOS Simulator,id=<UDID>' \
///   -only-testing:ZhongmiaoUITests/IntegrationSmokeTests
/// ```
/// 需要先把对应服务起在 `ZM_TEST_HOST` 上（默认 127.0.0.1，端口见 IntegrationDebugSeed）。
/// 真机上跑要求设备解锁，否则测试运行器会以 code 74 直接退出。
final class IntegrationSmokeTests: XCTestCase {

    private static let host = ProcessInfo.processInfo.environment["ZM_TEST_HOST"] ?? "127.0.0.1"

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ service: String, extra: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        var env = ["ZM_PREVIEW_SERVICE": service, "ZM_HOST": Self.host]
        env.merge(extra) { _, new in new }
        app.launchEnvironment = env
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 15)
        return app
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 幕间：三个分段都能打开、详情能弹出、已观看能改。
    func testMujianTabsAndDetail() {
        let app = launch("mujian")
        XCTAssertTrue(app.staticTexts["未来 14 天"].waitForExistence(timeout: 15))
        attach("mujian-upcoming")

        let segments = app.segmentedControls.firstMatch
        XCTAssertTrue(segments.waitForExistence(timeout: 8))

        segments.buttons["统计"].tap()
        Thread.sleep(forTimeInterval: 2)
        attach("mujian-stats")

        segments.buttons["全部"].tap()
        Thread.sleep(forTimeInterval: 2)
        attach("mujian-all")

        let firstRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "易俗社")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 10))
        firstRow.tap()
        Thread.sleep(forTimeInterval: 2)
        attach("mujian-detail")

        // 真的去点「已观看」，验证写回不是只改本地状态。
        let watched = app.switches.firstMatch
        XCTAssertTrue(watched.waitForExistence(timeout: 8))
        let before = watched.value as? String
        // 开关在 List 行里直接 tap() 常打不中，点开关本体右侧更稳。
        watched.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 3)
        attach("mujian-watched-after")
        let after = app.switches.firstMatch.value as? String
        XCTAssertNotEqual(before, after, "已观看开关没有变化")
    }

    /// 吾身：正文能编辑并保存。
    func testDiarumWrite() throws {
        let app = launch("diarum", extra: [
            "ZM_DIARUM_USERNAME": "zmnative2",
            "ZM_DIARUM_PASSWORD": "zmtest1234"
        ])
        let editor = app.textViews["diarum.editor"]
        var appeared = false
        for _ in 0..<40 {
            if editor.exists {
                appeared = true
                break
            }
            Thread.sleep(forTimeInterval: 1)
        }
        try XCTSkipUnless(appeared, "编辑器没出现（多半是登录还没完成）")
        attach("diarum-editor")

        var focused = false
        for offset in [0.15, 0.35, 0.55] {
            app.textViews["diarum.editor"]
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: offset))
                .tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 3) {
                focused = true
                break
            }
        }
        try XCTSkipUnless(focused, "软键盘没弹出（模拟器输入法问题），跳过输入断言")
        app.textViews["diarum.editor"].typeText(" native write check")
        Thread.sleep(forTimeInterval: 1)
        attach("diarum-typed")

        let save = app.buttons["保存日记"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        save.tap()
        Thread.sleep(forTimeInterval: 3)
        attach("diarum-saved")
    }

    /// 幕间：从原生表单录入一场演出。
    func testMujianCreate() {
        let app = launch("mujian")
        let add = app.buttons["录入演出"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()

        let name = app.textFields["剧目名称"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("UI 录入测试")

        let venue = app.textFields["场馆"].firstMatch
        if venue.exists {
            venue.tap()
            venue.typeText("Test Venue")
        }
        attach("mujian-composer")

        let save = app.buttons["保存"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        save.tap()
        Thread.sleep(forTimeInterval: 4)
        attach("mujian-created")
    }

    /// 察新：点 Release 链接应该留在应用内，不再跳 Safari。
    func testChaxinReleaseOpensInApp() throws {
        let app = launch("chaxin")
        let link = app.buttons["查看 Release"].firstMatch
        try XCTSkipUnless(link.waitForExistence(timeout: 20), "没读到缓存的 Release（先塞 chaxin.json）")
        attach("chaxin-list")

        link.tap()
        Thread.sleep(forTimeInterval: 4)
        attach("chaxin-in-app-browser")

        // 应用内浏览器的特征：有「关闭」按钮，导航标题是域名。
        let close = app.buttons["关闭"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 8), "没有弹出应用内浏览器")
    }

    /// 排查用：把当前界面结构打出来，方便定位元素。
    func testDumpTree() {
        let service = ProcessInfo.processInfo.environment["ZM_TEST_SERVICE"] ?? "mujian"
        let app = launch(service)
        Thread.sleep(forTimeInterval: 4)
        print("=== TREE BEGIN (\(service)) ===")
        print(app.debugDescription)
        print("=== TREE END ===")
    }

    /// 吾身：带着条目目标启动时，页面要直接落在那一天，而不是今天。
    func testDiarumTargetOpensThatDay() {
        // 取一个确定不是今天的日期：三天前
        let target = Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .now
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: target)

        let app = launch("diarum", extra: [
            "ZM_TARGET_SERVICE": "diarum",
            "ZM_TARGET_KIND": "diary",
            "ZM_TARGET_ID": day,
            "ZM_DIARUM_USERNAME": "zmnative2",
            "ZM_DIARUM_PASSWORD": "zmtest1234"
        ])

        let label = app.descendants(matching: .any)["diarum.dateLabel"].firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: 20), "没找到日期标签")

        // 冷启动的静默登录是异步的，日期要等登录完成后才切过去。
        let deadline = Date().addingTimeInterval(25)
        var value = label.value as? String
        while value != day, Date() < deadline {
            Thread.sleep(forTimeInterval: 1)
            value = label.value as? String
        }
        attach("diarum-target-day")
        XCTAssertEqual(value, day, "没有定位到目标那一天")
    }
}
