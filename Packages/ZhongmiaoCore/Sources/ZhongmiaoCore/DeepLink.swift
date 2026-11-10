import Foundation

/// `zhongmiao://` 深链。
///
/// 免费个人账号拿不到 Associated Domains（官方能力表中仅限付费会员），
/// 因此 Universal Links 不可用——网页与系统表面（小组件、日历事件、提醒事项、
/// 快捷指令）要回到应用里的某一页，只能靠自定义 URL scheme。
///
/// 形态：
/// ```
/// zhongmiao://service/<serviceID>?target=<kind>&id=<identifier>
/// zhongmiao://<serviceID>?target=<kind>&id=<identifier>
/// ```
///
/// `target` 与 `id` 必须同时出现才会解析成 `NativeTarget`；
/// 服务 ID 不在注册表里时结果为 `nil`，调用方直接忽略即可。
/// 解析是纯函数，放在 Core 里由 `swift test` 覆盖。
public struct DeepLink: Hashable, Sendable {

    public static let scheme = "zhongmiao"

    /// 要打开的服务页，以及页内的具体条目。
    public struct Service: Hashable, Sendable {
        public var serviceID: String
        public var target: NativeTarget?

        public init(serviceID: String, target: NativeTarget? = nil) {
            self.serviceID = serviceID
            self.target = target
        }
    }

    public var service: Service?

    public init(service: Service? = nil) {
        self.service = service
    }

    // MARK: - 解析

    public static func parse(_ url: URL) -> DeepLink {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              components.scheme?.lowercased() == scheme,
              let host = components.host?.lowercased(), !host.isEmpty
        else {
            return DeepLink(service: nil)
        }

        // 两种写法都认：`service/<id>` 与直接把 id 写在 host 上。
        // 后者的 host 恰好是 "service" 时按前者解释（注册表里没有叫 service 的应用）。
        let rawID: String
        if host == "service" {
            let segment = components.path.split(separator: "/").first
            guard let segment, !segment.isEmpty else { return DeepLink(service: nil) }
            rawID = String(segment)
        } else {
            rawID = host
        }

        let serviceID = rawID.lowercased()
        guard ServiceCatalog.service(id: serviceID) != nil else { return DeepLink(service: nil) }

        let items = components.queryItems ?? []
        let kind = items.first { $0.name == "target" }?.value ?? ""
        let identifier = items.first { $0.name == "id" }?.value ?? ""
        let target: NativeTarget? = kind.isEmpty || identifier.isEmpty
            ? nil
            : NativeTarget(kind: kind, identifier: identifier)

        return DeepLink(service: Service(serviceID: serviceID, target: target))
    }

    // MARK: - 构造

    /// 生成深链。服务不在注册表时返回 nil——宁可没有链接，也不要生成打不开的链接。
    public static func url(serviceID: String, target: NativeTarget? = nil) -> URL? {
        guard ServiceCatalog.service(id: serviceID) != nil else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "service"
        components.path = "/\(serviceID)"
        if let target, !target.isEmpty {
            components.queryItems = [
                URLQueryItem(name: "target", value: target.kind),
                URLQueryItem(name: "id", value: target.identifier)
            ]
        }
        return components.url
    }
}
