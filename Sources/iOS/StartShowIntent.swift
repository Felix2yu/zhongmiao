import AppIntents
import Foundation
import ZhongmiaoCore

/// 快捷指令调用的「开启演出盯场」。
///
/// 这是无 APNs 场景下**唯一能在后台开岛**的官方路径：
/// `LiveActivityIntent` 允许系统直接拉起 App 进程执行本方法，而不打开界面。
/// 系统因此把它作为快捷指令自动化里的一个动作暴露出来。
///
/// 它只读本地缓存、不联网：被拉起的那十几毫秒里没有时间等幕间响应，
/// 而且自动化在深夜也可能触发，此时未必有网络。缓存由前台刷新写入，见 `ShowStore`。
struct StartShowIntent: LiveActivityIntent {

    // 协议里的这几个静态属性声明为 `var`，但实现必须用 `let`：
    // 全局可变状态在 Swift 6 严格并发下不可通过。
    static let title: LocalizedStringResource = "开启演出盯场"
    static let description = IntentDescription(
        "读取已缓存的演出，若开演时间已进入灵动岛窗口，就把岛亮起来；不在窗口内则什么也不做。"
    )

    /// 必须是 false：为 true 会强制打开 App 界面，自动化就不再是静默的了。
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        let settings = SettingsStorage.load()
        guard settings.showsEnabled else { return .result() }

        let library = await ShowStore.standard().snapshot()
        let shows = library.upcoming()

        // 顺带重排一次提醒：自动化一天跑两次，正好是排程的兜底时机，
        // 即便某次前台刷新失败，这里也能补上。
        await ShowScheduler().sync(shows, lead: settings.showsReminderLead)

        await ShowIslandController.shared.align(shows: shows, lead: settings.showsIslandLead)
        return .result()
    }
}
