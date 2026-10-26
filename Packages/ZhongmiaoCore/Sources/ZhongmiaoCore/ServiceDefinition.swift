import Foundation

/// 一个被聚合的 Go 应用。
///
/// 只描述"这个应用是什么、默认怎么访问"，不包含用户改动。
/// 用户级覆盖（自定义 URL、通知开关）由 App 层的 `CatalogPreferences` 承担，
/// 这样核心包保持无状态、可测试。
public struct ServiceDefinition: Codable, Identifiable, Hashable, Sendable {

    /// 应用形态，用于决定入口行为与提示文案。
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// 具备完整 PWA 能力（Manifest + Service Worker + 离线）。
        case pwa
        /// 有前端页面但无离线能力。
        case web
        /// 工具型页面（一次性的查询/状态页）。
        case utility

        public var isOfflineCapable: Bool { self == .pwa }

        /// 离线能力的说明文案。
        ///
        /// 这里刻意避开单独的「离线」二字：它既可以读成「支持离线（能力）」，
        /// 也可以读成「当前离线（状态）」。中文里这两种含义完全撞车，
        /// 挂在卡片上会被误解成服务挂了，所以统一带上「可用／需要联网」。
        public var offlineCapabilityDescription: String {
            isOfflineCapable ? "离线可用" : "需要联网"
        }
    }

    public enum Category: String, Codable, Sendable, CaseIterable, Identifiable {
        case productivity
        case media
        case finance
        case knowledge
        case infrastructure
        case life

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .productivity: "效率与任务"
            case .media: "影像与媒体"
            case .finance: "财务"
            case .knowledge: "知识与阅读"
            case .infrastructure: "基建与运维"
            case .life: "生活"
            }
        }

        public var symbol: String {
            switch self {
            case .productivity: "checklist"
            case .media: "photo.on.rectangle.angled"
            case .finance: "chart.line.uptrend.xyaxis"
            case .knowledge: "books.vertical"
            case .infrastructure: "server.rack"
            case .life: "leaf"
            }
        }
    }

    /// 稳定标识，同时用作子域名前缀与通知去重命名空间。
    public var id: String
    public var name: String
    /// 一句话说明，用于卡片副标题与 VoiceOver。
    public var summary: String
    /// SF Symbol 名称。
    public var symbol: String
    /// 十六进制色值（不含 #），用于卡片点缀色。
    public var tint: String
    public var category: Category
    public var kind: Kind
    /// 进入后的落地路径，默认 `/`。
    public var path: String
    /// 容器内部监听端口。Nginx 反代与 Docker 网络都用它，与宿主机映射端口无关。
    public var defaultPort: Int?
    /// Docker 容器名 / compose 服务名，用于生成 Nginx upstream。为 nil 时回退到 id。
    public var container: String?
    /// 子域名模式下的前缀；为 nil 时回退到 `id`。
    public var subdomain: String?
    /// 已知的绝对地址（如已被独立域名接管的应用），优先级最高。
    public var absoluteURL: String?
    /// 该应用暴露通知流时使用的路径，例如 `/api/notifications`。
    public var notificationFeedPath: String?
    /// 若该应用把事件投递到 ntfy 主题，这里填主题名。
    public var ntfyTopic: String?
    /// 是否默认纳入后台通知同步。
    public var notificationsEnabledByDefault: Bool

    public init(
        id: String,
        name: String,
        summary: String,
        symbol: String,
        tint: String,
        category: Category,
        kind: Kind,
        path: String = "/",
        defaultPort: Int? = nil,
        container: String? = nil,
        subdomain: String? = nil,
        absoluteURL: String? = nil,
        notificationFeedPath: String? = nil,
        ntfyTopic: String? = nil,
        notificationsEnabledByDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.symbol = symbol
        self.tint = tint
        self.category = category
        self.kind = kind
        self.path = path
        self.defaultPort = defaultPort
        self.container = container
        self.subdomain = subdomain
        self.absoluteURL = absoluteURL
        self.notificationFeedPath = notificationFeedPath
        self.ntfyTopic = ntfyTopic
        self.notificationsEnabledByDefault = notificationsEnabledByDefault
    }

    /// 用于无障碍朗读的完整描述。
    public var accessibilityDescription: String {
        "\(name)，\(summary)，\(kind.offlineCapabilityDescription)"
    }
}
