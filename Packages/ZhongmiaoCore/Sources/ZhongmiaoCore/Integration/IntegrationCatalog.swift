import Foundation

/// 原生接入能提供的一项能力。只用于展示与验收，不参与动态派发。
public struct IntegrationCapability: Hashable, Sendable, Codable {

    public var title: String
    public var isWrite: Bool

    public init(_ title: String, isWrite: Bool = false) {
        self.title = title
        self.isWrite = isWrite
    }
}

/// 一个应用的原生接入说明。
///
/// 与 `ServiceDefinition` 分开：后者描述“怎么访问”，这里描述“原生能做什么、
/// 需要什么凭据、哪些操作仍回网页”。这样 `zm-catalog` 与 Nginx 生成器都不受影响。
public struct IntegrationDefinition: Identifiable, Hashable, Sendable, Codable {

    public enum Priority: String, Codable, Sendable, CaseIterable, Identifiable {
        case p0
        case p1
        case p2
        case web

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .p0: "P0 · 深度接入"
            case .p1: "P1 · 原生看板"
            case .p2: "P2 · 只读看板"
            case .web: "保留网页版"
            }
        }

        public var shortTitle: String {
            switch self {
            case .p0: "P0"
            case .p1: "P1"
            case .p2: "P2"
            case .web: "网页"
            }
        }

        public var sortOrder: Int {
            switch self {
            case .p0: 0
            case .p1: 1
            case .p2: 2
            case .web: 3
            }
        }
    }

    public enum AuthKind: String, Codable, Sendable, CaseIterable {
        /// 服务端没有鉴权。
        case none
        /// 共享 Token / API Key，直接放在 Authorization 头里。
        case bearerToken
        /// 账号密码换 JWT。
        case login
        /// 账号密码换会话 Cookie。
        case sessionCookie

        public var title: String {
            switch self {
            case .none: "无需鉴权"
            case .bearerToken: "访问令牌 / API Key"
            case .login: "账号密码"
            case .sessionCookie: "账号密码（会话）"
            }
        }

        public var needsCredential: Bool { self != .none }
    }

    public var serviceID: String
    public var priority: Priority
    public var authKind: AuthKind
    /// 服务端不校验时令牌可以留空（如牵丝、幕间、蜂巢、ntfy）。
    public var credentialOptional: Bool
    /// API 前缀，例如 `/api`、`/api/v1`；ntfy 与月汐为空。
    public var basePath: String
    public var capabilities: [IntegrationCapability]
    public var summary: String
    public var webOnlyNote: String
    public var supportsReminders: Bool

    public var id: String { serviceID }

    public var reads: [IntegrationCapability] { capabilities.filter { !$0.isWrite } }
    public var writes: [IntegrationCapability] { capabilities.filter(\.isWrite) }

    public init(
        serviceID: String,
        priority: Priority,
        authKind: AuthKind,
        credentialOptional: Bool = false,
        basePath: String,
        capabilities: [IntegrationCapability],
        summary: String,
        webOnlyNote: String,
        supportsReminders: Bool = false
    ) {
        self.serviceID = serviceID
        self.priority = priority
        self.authKind = authKind
        self.credentialOptional = credentialOptional
        self.basePath = basePath
        self.capabilities = capabilities
        self.summary = summary
        self.webOnlyNote = webOnlyNote
        self.supportsReminders = supportsReminders
    }
}

/// 全部已接入应用的原生接入矩阵。
public enum IntegrationCatalog {

    public static let all: [IntegrationDefinition] = [
        IntegrationDefinition(
            serviceID: "huozhi",
            priority: .p0,
            authKind: .login,
            basePath: "/api",
            capabilities: [
                IntegrationCapability("账户余额与资产概览"),
                IntegrationCapability("信用卡账单与还款日"),
                IntegrationCapability("分类与书籍"),
                IntegrationCapability("近期流水"),
                IntegrationCapability("支出", isWrite: true),
                IntegrationCapability("收入", isWrite: true),
                IntegrationCapability("转账", isWrite: true),
                IntegrationCapability("信用卡还款", isWrite: true)
            ],
            summary: "原生记账、信用卡还款与资产概览",
            webOnlyNote: "预算、分期、借贷、报销、导入导出、对账、账户与分类管理仍在网页版。",
            supportsReminders: false
        ),
        IntegrationDefinition(
            serviceID: "qiansi",
            priority: .p0,
            authKind: .bearerToken,
            credentialOptional: true,
            basePath: "/api/v1",
            capabilities: [
                IntegrationCapability("联系人"),
                IntegrationCapability("生日与纪念日"),
                IntegrationCapability("近期提醒"),
                IntegrationCapability("约会与往来"),
                IntegrationCapability("新建纪念日", isWrite: true),
                IntegrationCapability("新建约会", isWrite: true),
                IntegrationCapability("编辑纪念日", isWrite: true),
                IntegrationCapability("归档纪念日与约会", isWrite: true),
                IntegrationCapability("完成提醒", isWrite: true)
            ],
            summary: "联系人、生日与约会提醒",
            webOnlyNote: "关系图谱、批量编辑、vCard 导入、约会编辑与往来金额挂账仍在网页版。",
            supportsReminders: true
        ),
        IntegrationDefinition(
            serviceID: "qingye",
            priority: .p0,
            authKind: .none,
            basePath: "/api",
            capabilities: [
                IntegrationCapability("房间"),
                IntegrationCapability("植物"),
                IntegrationCapability("养护任务"),
                IntegrationCapability("养护记录"),
                IntegrationCapability("完成/推迟任务", isWrite: true),
                IntegrationCapability("记录浇水施肥", isWrite: true),
                IntegrationCapability("新建植物", isWrite: true)
            ],
            summary: "植物养护待办与提醒",
            webOnlyNote: "照片、图库、植物库导入、天气、房间管理仍在网页版。",
            supportsReminders: true
        ),
        IntegrationDefinition(
            serviceID: "mujian",
            priority: .p1,
            authKind: .bearerToken,
            credentialOptional: true,
            basePath: "/api",
            capabilities: [
                IntegrationCapability("未来演出"),
                IntegrationCapability("全部记录与搜索"),
                IntegrationCapability("演出详情"),
                IntegrationCapability("看板与剧种/城市分布"),
                IntegrationCapability("录入演出", isWrite: true),
                IntegrationCapability("标记已观看", isWrite: true)
            ],
            summary: "演出浏览、录入与统计",
            webOnlyNote: "剧种/演员/场馆管理、照片、批量编辑、导入导出、备份仍在网页版。",
            supportsReminders: false
        ),
        IntegrationDefinition(
            serviceID: "diarum",
            priority: .p1,
            authKind: .login,
            basePath: "/api/v1",
            capabilities: [
                IntegrationCapability("按日期读日记"),
                IntegrationCapability("最近日记"),
                IntegrationCapability("搜索正文"),
                IntegrationCapability("连续天数与总数"),
                IntegrationCapability("写/改当天正文", isWrite: true)
            ],
            summary: "日记浏览、检索与原生撰写",
            webOnlyNote: "情绪/场景/标签编辑、媒体、AI 润色、导入导出仍在网页版。",
            supportsReminders: true
        ),
        IntegrationDefinition(
            serviceID: "shenshi",
            priority: .p1,
            authKind: .bearerToken,
            credentialOptional: true,
            basePath: "/api",
            capabilities: [
                IntegrationCapability("今日/逾期任务"),
                IntegrationCapability("习惯"),
                IntegrationCapability("到期提醒"),
                IntegrationCapability("统计"),
                IntegrationCapability("完成任务", isWrite: true),
                IntegrationCapability("习惯打卡", isWrite: true)
            ],
            summary: "今日任务、习惯与到期提醒",
            webOnlyNote: "项目/清单管理、任务编辑、复盘、CalDAV 仍在网页版。",
            supportsReminders: true
        ),
        IntegrationDefinition(
            serviceID: "qbhive",
            priority: .p1,
            authKind: .bearerToken,
            credentialOptional: true,
            basePath: "/api",
            capabilities: [
                IntegrationCapability("下载/做种/错误统计"),
                IntegrationCapability("种子列表"),
                IntegrationCapability("RSS 状态"),
                IntegrationCapability("暂停/继续", isWrite: true),
                IntegrationCapability("校验", isWrite: true),
                IntegrationCapability("限速", isWrite: true)
            ],
            summary: "下载看板与可逆操作",
            webOnlyNote: "删除文件、RSS 编辑、文件管理、设置仍在网页版。",
            supportsReminders: false
        ),
        IntegrationDefinition(
            serviceID: "ntfy",
            priority: .p1,
            authKind: .bearerToken,
            credentialOptional: true,
            basePath: "",
            capabilities: [
                IntegrationCapability("主题"),
                IntegrationCapability("消息时间线"),
                IntegrationCapability("搜索"),
                IntegrationCapability("标记已读", isWrite: true),
                IntegrationCapability("删除消息", isWrite: true)
            ],
            summary: "主题与消息浏览",
            webOnlyNote: "发布消息、账户/ACL、Web Push 仍在网页版。",
            supportsReminders: false
        ),
        IntegrationDefinition(
            serviceID: "yuexi",
            priority: .p1,
            authKind: .sessionCookie,
            basePath: "",
            capabilities: [
                IntegrationCapability("周期倒计时"),
                IntegrationCapability("异常提示"),
                IntegrationCapability("通知状态")
            ],
            summary: "周期倒计时与脱敏提醒",
            webOnlyNote: "经期记录/编辑、日记录入、导出、成员管理仍在网页版。",
            supportsReminders: true
        ),
        IntegrationDefinition(
            serviceID: "bili-history",
            priority: .p2,
            authKind: .none,
            basePath: "/api",
            capabilities: [
                IntegrationCapability("今日观看"),
                IntegrationCapability("历史列表"),
                IntegrationCapability("月度统计"),
                IntegrationCapability("热力图")
            ],
            summary: "观看记录与统计看板",
            webOnlyNote: "搜索、导出、视频详情仍在网页版。",
            supportsReminders: false
        ),
        IntegrationDefinition(
            serviceID: "chaxin",
            priority: .p2,
            authKind: .none,
            basePath: "/api",
            capabilities: [
                IntegrationCapability("仓库列表"),
                IntegrationCapability("Release 通知"),
                IntegrationCapability("未读/失败计数"),
                IntegrationCapability("添加监控仓库", isWrite: true),
                IntegrationCapability("立即检查全部仓库", isWrite: true),
                IntegrationCapability("重发失败通知", isWrite: true)
            ],
            summary: "版本发布动态",
            webOnlyNote: "仓库删除、监控设置与 GitHub Token 仍在网页版。",
            supportsReminders: false
        ),
        IntegrationDefinition(
            serviceID: "liuxia",
            priority: .p2,
            authKind: .none,
            basePath: "/api",
            capabilities: [
                IntegrationCapability("今明两天的朝霞与晚霞"),
                IntegrationCapability("下一场倒计时"),
                IntegrationCapability("未来一周的优质场次"),
                IntegrationCapability("多模型取最优与城市筛选")
            ],
            summary: "朝霞晚霞预报与观赏窗口",
            webOnlyNote: "历史归档、导出仍在网页版。",
            supportsReminders: false
        ),
        IntegrationDefinition(
            serviceID: "whoami",
            priority: .web,
            authKind: .none,
            basePath: "",
            capabilities: [],
            summary: "网络身份诊断",
            webOnlyNote: "结论依赖浏览器 JS 与 Client Hints，原生请求会失真，保留网页版。"
        ),
        IntegrationDefinition(
            serviceID: "tuqie",
            priority: .web,
            authKind: .none,
            basePath: "/api",
            capabilities: [],
            summary: "图片切割工具",
            webOnlyNote: "核心是交互式切图且没有持久数据，保留网页版。"
        )
    ]

    public static var integrated: [IntegrationDefinition] {
        all.filter { $0.priority != .web }
    }

    public static func definition(for serviceID: String) -> IntegrationDefinition? {
        all.first { $0.serviceID == serviceID }
    }

    public static var grouped: [(priority: IntegrationDefinition.Priority, definitions: [IntegrationDefinition])] {
        IntegrationDefinition.Priority.allCases.compactMap { priority in
            let definitions = all.filter { $0.priority == priority }
            return definitions.isEmpty ? nil : (priority, definitions)
        }
    }

    /// 覆盖完整性校验：每个服务恰好一条，且注册表里没有多余项。
    public static func validate() -> [String] {
        var issues: [String] = []
        let catalogIDs = Set(ServiceCatalog.all.map(\.id))
        let integrationIDs = all.map(\.serviceID)

        if Set(integrationIDs).count != integrationIDs.count {
            issues.append("接入注册表存在重复 serviceID")
        }
        if Set(integrationIDs) != catalogIDs {
            let missing = catalogIDs.subtracting(integrationIDs).sorted()
            let extra = Set(integrationIDs).subtracting(catalogIDs).sorted()
            if !missing.isEmpty { issues.append("缺少接入说明：\(missing.joined(separator: ", "))") }
            if !extra.isEmpty { issues.append("接入说明指向不存在的服务：\(extra.joined(separator: ", "))") }
        }
        for definition in all {
            if !definition.basePath.isEmpty,
               !definition.basePath.hasPrefix("/") || definition.basePath.hasSuffix("/") {
                issues.append("\(definition.serviceID)：basePath 必须形如 /api，不能以 / 结尾")
            }
            if definition.authKind == .none && !definition.credentialOptional && definition.priority != .web {
                // 无鉴权应用天然不需要凭据，credentialOptional 只是展示用。
            }
            if definition.priority == .web && !definition.capabilities.isEmpty {
                issues.append("\(definition.serviceID)：保留网页版的应用不应声明原生能力")
            }
            if definition.authKind == .login && definition.credentialOptional {
                issues.append("\(definition.serviceID)：账号密码登录不能是可选凭据")
            }
        }
        if !all.contains(where: { $0.priority == .p0 }) {
            issues.append("缺少 P0 应用")
        }
        return issues
    }
}
