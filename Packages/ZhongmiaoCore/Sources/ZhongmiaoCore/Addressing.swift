import Foundation

/// 应用地址的解析方式。
///
/// 部署事实：所有应用跑在 Docker 里，外层是 Nginx + HTTPS。
/// 因此默认用「子域名」模式；同时保留「子路径」（Nginx 按 location 分流）
/// 与「内网端口」（排障直连）两种退路。
public enum AddressMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// `https://<subdomain>.<baseDomain>/<path>`
    case subdomain
    /// `https://<baseDomain>/<subdomain>/<path>`
    case path
    /// `http://<lanHost>:<hostPort>/<path>`
    case port

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .subdomain: "子域名"
        case .path: "子路径"
        case .port: "内网端口"
        }
    }

    public var hint: String {
        switch self {
        case .subdomain:
            "一个应用一个子域名，直接复用现有 Nginx 反代。HTTPS 下 Service Worker 才能注册，离线缓存也才可用。"
        case .path:
            "Nginx 用 location /应用名/ 分流时选这个。注意单页应用通常把资源写成根绝对路径，子路径反代容易 404，除非应用本身支持 base path。"
        case .port:
            "仅用于局域网排障直连。这里填的是宿主机映射端口，不是容器内部端口；多个应用内部同为 8080，务必逐个核对。"
        }
    }
}

/// 全局地址配置（可在设置中改，改一处即可重算全部服务地址）。
public struct AddressSettings: Codable, Hashable, Sendable {
    public var mode: AddressMode
    /// 子域名模式的基础域名，例如 `example.com`。
    public var baseDomain: String
    /// 端口模式的局域网主机，例如 `192.168.1.10`。
    public var lanHost: String

    public init(
        mode: AddressMode = .subdomain,
        baseDomain: String = "qfpqhyl.top",
        lanHost: String = "192.168.1.10"
    ) {
        self.mode = mode
        self.baseDomain = baseDomain
        self.lanHost = lanHost
    }

    public static let `default` = AddressSettings()
}

/// 把「服务定义 + 地址配置 + 用户覆盖」解析成可访问的 URL。
public enum ServiceURLResolver {

    /// - Parameters:
    ///   - service: 服务定义。
    ///   - settings: 全局地址配置。
    ///   - override: 用户为单个服务填写的绝对地址，优先级最高。
    ///
    /// 解析优先级：用户覆盖 > 服务内置绝对地址 > 全局模式。
    /// `port` 模式下的端口按宿主机映射端口理解；Nginx 场景请用子域名模式。
    public static func url(
        for service: ServiceDefinition,
        settings: AddressSettings,
        override: String? = nil
    ) -> URL? {
        if let raw = normalized(override), let url = URL(string: raw) {
            return appendPath(service.path, to: url)
        }
        if let raw = normalized(service.absoluteURL), let url = URL(string: raw) {
            return appendPath(service.path, to: url)
        }

        switch settings.mode {
        case .subdomain:
            let host = sanitizedHost(settings.baseDomain)
            guard !host.isEmpty else { return nil }
            let prefix = sanitizedLabel(service.subdomain ?? service.id)
            guard !prefix.isEmpty else { return nil }
            var components = URLComponents()
            components.scheme = "https"
            components.host = "\(prefix).\(host)"
            components.path = service.path.hasPrefix("/") ? service.path : "/" + service.path
            return components.url
        case .path:
            let host = sanitizedHost(settings.baseDomain)
            guard !host.isEmpty else { return nil }
            let prefix = sanitizedLabel(service.subdomain ?? service.id)
            guard !prefix.isEmpty else { return nil }
            var components = URLComponents()
            components.scheme = "https"
            components.host = host
            let tail = service.path.hasPrefix("/") ? service.path : "/" + service.path
            components.path = "/" + prefix + (tail == "/" ? "/" : tail)
            return components.url
        case .port:
            let host = sanitizedHost(settings.lanHost)
            guard !host.isEmpty, let port = service.defaultPort else { return nil }
            var components = URLComponents()
            components.scheme = "http"
            components.host = host
            components.port = port
            components.path = service.path.hasPrefix("/") ? service.path : "/" + service.path
            return components.url
        }
    }

    /// 该服务在当前配置下是否"可解析"（端口模式下缺少端口的服务会解析失败）。
    public static func isResolvable(_ service: ServiceDefinition, settings: AddressSettings) -> Bool {
        url(for: service, settings: settings) != nil
    }

    /// 用于健康检查与同源判断的 host（含端口）。
    public static func host(for service: ServiceDefinition, settings: AddressSettings, override: String? = nil) -> String? {
        url(for: service, settings: settings, override: override)?.host
    }

    private static func normalized(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        if trimmed.contains("://") { return trimmed }
        return "https://" + trimmed
    }

    /// 允许用户粘贴完整 URL：去掉协议、路径与端口，只留主机名。
    private static func sanitizedHost(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
        }
        if let slash = value.firstIndex(of: "/") {
            value = String(value[value.startIndex..<slash])
        }
        if let colon = value.firstIndex(of: ":") {
            value = String(value[value.startIndex..<colon])
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    private static func sanitizedLabel(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    private static func appendPath(_ path: String, to url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let base = components?.path ?? ""
        if path == "/" || path.isEmpty {
            // 统一根路径写法，避免 `http://host:8787` 与 `http://host:8787/` 两种形态混用。
            if base.isEmpty { components?.path = "/" }
            return components?.url ?? url
        }
        let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        components?.path = trimmedBase + (path.hasPrefix("/") ? path : "/" + path)
        return components?.url ?? url
    }
}
