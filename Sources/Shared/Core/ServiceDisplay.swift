import Foundation
import ZhongmiaoCore

/// 通知来源的展示名与图标。
///
/// 除了注册表里的应用，收件箱还可能来自独立订阅的 ntfy 主题（伪服务 id `ntfy:<topic>`）。
/// 统一的解析入口，避免各处 `ServiceCatalog.service(id:)` 拿到 nil 后把原始 id 直接显示出来。
enum ServiceDisplay {

    static func name(for serviceID: String) -> String {
        if let topic = NtfyTopic.topic(fromServiceID: serviceID) {
            return topic
        }
        return ServiceCatalog.service(id: serviceID)?.name ?? serviceID
    }

    /// 伪服务借用 ntfy 的图标与配色。
    static func glyph(for serviceID: String) -> ServiceDefinition? {
        if NtfyTopic.isStandaloneServiceID(serviceID) {
            return ServiceCatalog.service(id: "ntfy")
        }
        return ServiceCatalog.service(id: serviceID)
    }

    /// 通知点击后实际要打开的应用 id：独立主题统一落到 ntfy 页面。
    static func routeServiceID(for serviceID: String) -> String {
        NtfyTopic.isStandaloneServiceID(serviceID) ? "ntfy" : serviceID
    }
}
