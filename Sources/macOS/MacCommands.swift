#if os(macOS)
import SwiftUI

extension Notification.Name {
    /// 切分区（「视图」菜单的 ⌘1/2/3、设置…）。
    static let zmSelectSection = Notification.Name("im.yufei.zhongmiao.selectSection")
    /// 刷新当前页（⌘R）：由 `RootView` 按当前页类型分派。
    static let zmReloadPage = Notification.Name("im.yufei.zhongmiao.reloadPage")
    /// 重载网页（服务页内）。
    static let zmReloadWebPage = Notification.Name("im.yufei.zhongmiao.reloadWebPage")
    /// 绕过缓存重载网页（⇧⌘R）。
    static let zmForceReloadWebPage = Notification.Name("im.yufei.zhongmiao.forceReloadWebPage")
}

/// macOS 菜单栏命令。
///
/// 只把 App 已有的动作映射成菜单项与快捷键，不新增业务能力；
/// 文案与界面上的按钮保持一致（「同步全部」不写成「全部同步」）。
struct MacCommands: Commands {

    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // 设置窗口由 `Settings` 场景提供，App 菜单里的「设置…（⌘,）」是系统自动加的，
        // 这里不再重复建一个同义项。

        CommandGroup(after: .newItem) {
            Button("同步全部") { model.syncNow(reason: "菜单") }
                .disabled(model.isSyncing)
        }

        // 插进系统自带的「显示」菜单，不再新建一个同义的「视图」菜单。
        CommandGroup(after: .toolbar) {
            Divider()
            Button("应用") { select(.catalog) }
                .keyboardShortcut("1", modifiers: .command)
            Button("通知") { select(.inbox) }
                .keyboardShortcut("2", modifiers: .command)
            Button("设置…") { select(.settings) }
                .keyboardShortcut("3", modifiers: .command)

            Divider()

            Button("刷新当前页") {
                NotificationCenter.default.post(name: .zmReloadPage, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("强制刷新（绕过缓存）") {
                NotificationCenter.default.post(name: .zmForceReloadWebPage, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Toggle("显示服务能力标签", isOn: capabilityBinding)
        }

        CommandGroup(replacing: .help) {
            Button("诊断与日志") { openWindow(id: MacWindow.diagnostics) }
        }
    }

    private func select(_ section: AppSection) {
        NotificationCenter.default.post(
            name: .zmSelectSection,
            object: nil,
            userInfo: ["section": section.rawValue]
        )
    }

    /// 与「设置 → 服务」里那个开关是同一份数据。
    private var capabilityBinding: Binding<Bool> {
        Binding(
            get: { model.settings.showServiceCapabilityTags },
            set: { newValue in
                model.updateSettings { settings in
                    settings.showServiceCapabilityTags = newValue
                }
            }
        )
    }
}

enum MacWindow {
    static let diagnostics = "diagnostics"
}
#endif
