import Foundation

/// 顶层分区：应用 / 通知 / 设置。
///
/// iOS 上是 `TabView` 的三页；macOS 上只剩应用与通知两页，设置拆成了独立窗口
/// （`ZhongmiaoApp` 的 `Settings` 场景，⌘, 打开），但 `⌘3` 与深链回跳仍走这份取值。
/// 抽成独立类型是因为切换来源不止一处（点击标签、菜单命令、通知点击后的
/// `consumePendingRoute()`），三处必须指向同一份取值。
enum AppSection: String, Hashable, CaseIterable {
    case catalog
    case inbox
    case settings
}
