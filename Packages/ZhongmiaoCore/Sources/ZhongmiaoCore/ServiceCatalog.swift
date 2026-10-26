import Foundation

/// 内置服务注册表。
///
/// 事实来源：
/// - `~/Git/PWA支持现状审计.md`（PWA 成熟度、图标契约、2026-10-10 整改记录）
/// - 各仓库 `Dockerfile` 的 `EXPOSE`（**容器内部端口**，Nginx 反代就用它）
/// - 各仓库 `docker-compose.yml` 的 `container_name` / 服务名（Docker DNS 可解析）
/// - 部署方式已确认为 **Docker + Nginx + HTTPS**，因此默认走子域名模式
///
/// 注意：容器内部端口与宿主机映射端口不是一回事。`mujian / liuxia / huozhi / chaxin / qiansi`
/// 内部都是 8080，宿主机不可能都映射到 8080 —— 这正是反代存在的意义。
/// 端口模式下若发现地址重复，请逐个服务改成实际映射端口。
public enum ServiceCatalog {

    public static let all: [ServiceDefinition] = [
        ServiceDefinition(
            id: "shenshi",
            name: "慎始",
            summary: "任务、清单与看板",
            symbol: "checklist",
            tint: "5B5BD6",
            category: .productivity,
            kind: .pwa,
            defaultPort: 8787,
            container: "shenshi"
            // 慎始尚未实现 `GET /api/notifications`，这里不预填路径：
            // 填了会让每轮同步多出 3 次 404，并挡住中继兜底（见 AppModel.buildTargets）。
        ),
        ServiceDefinition(
            id: "mujian",
            name: "幕间",
            summary: "观演与观影记录",
            symbol: "theatermasks",
            tint: "8E5BD9",
            category: .media,
            kind: .pwa,
            defaultPort: 8080,
            container: "mujian"
        ),
        ServiceDefinition(
            id: "bili-history",
            name: "拾帧集",
            summary: "B 站观看历史与统计",
            symbol: "play.square.stack",
            tint: "D9527A",
            category: .media,
            kind: .pwa,
            defaultPort: 8899,
            container: "bili-history",
            subdomain: "bili"
        ),
        ServiceDefinition(
            id: "liuxia",
            name: "流霞",
            summary: "图片流与归档",
            symbol: "photo.stack",
            tint: "C96A9B",
            category: .media,
            kind: .pwa,
            defaultPort: 8080,
            container: "liuxia"
        ),
        ServiceDefinition(
            id: "tuqie",
            name: "图切",
            summary: "图片切割与导出",
            symbol: "scissors",
            tint: "6B7A8F",
            category: .media,
            kind: .pwa,
            defaultPort: 7423,
            container: "tuqie"
        ),
        ServiceDefinition(
            id: "huozhi",
            name: "货殖",
            summary: "记账与资产概览",
            symbol: "chart.pie",
            tint: "B8862F",
            category: .finance,
            kind: .pwa,
            defaultPort: 8080,
            container: "huozhi"
        ),
        ServiceDefinition(
            id: "diarum",
            name: "吾身",
            summary: "日记与定期回顾",
            symbol: "book.closed",
            tint: "4C8DF6",
            category: .knowledge,
            kind: .pwa,
            defaultPort: 8090,
            container: "diarum"
        ),
        ServiceDefinition(
            id: "qingye",
            name: "青野集",
            summary: "摘录与收藏",
            symbol: "leaf",
            tint: "3F9A6B",
            category: .knowledge,
            kind: .pwa,
            defaultPort: 8081,
            container: "qingye"
        ),
        ServiceDefinition(
            id: "chaxin",
            name: "察新",
            summary: "资讯聚合与阅读",
            symbol: "newspaper",
            tint: "4E8299",
            category: .knowledge,
            kind: .pwa,
            defaultPort: 8080,
            container: "chaxin"
        ),
        ServiceDefinition(
            id: "qiansi",
            name: "牵丝",
            summary: "关系与脉络整理",
            symbol: "point.3.filled.connected.trianglepath.dotted",
            tint: "8F63C9",
            category: .knowledge,
            kind: .pwa,
            defaultPort: 8080,
            container: "qiansi"
        ),
        ServiceDefinition(
            id: "yuexi",
            name: "月汐",
            summary: "周期与身体记录",
            symbol: "moon.stars",
            tint: "6E7BD4",
            category: .life,
            kind: .pwa,
            defaultPort: 8080,
            container: "yuexi"
        ),
        ServiceDefinition(
            id: "ntfy",
            name: "ntfy",
            summary: "自托管推送与告警",
            symbol: "bell.badge",
            tint: "2A9D8F",
            category: .infrastructure,
            kind: .pwa,
            defaultPort: 80,
            container: "ntfy",
            notificationsEnabledByDefault: true
        ),
        ServiceDefinition(
            id: "qbhive",
            name: "蜂巢",
            summary: "下载任务管理",
            symbol: "arrow.down.circle.fill",
            tint: "3B82C4",
            category: .infrastructure,
            kind: .web,
            defaultPort: 8088,
            container: "qbhive"
        ),
        ServiceDefinition(
            id: "whoami",
            name: "whoami",
            summary: "网络出口与身份信息",
            symbol: "network",
            tint: "6B7280",
            category: .infrastructure,
            kind: .utility,
            defaultPort: 8080,
            container: "whoami"
        )
    ]

    /// 按分类分组，保持注册表顺序。
    /// 按类别分组的服务列表，组内保持注册表顺序。
    public static var grouped: [(category: ServiceDefinition.Category, services: [ServiceDefinition])] {
        grouped(prioritizing: { _ in 0 })
    }

    /// 按类别分组，组内按 `priority` 升序排列（值小的在前）。
    ///
    /// `priority` 相同时**必须**保持注册表顺序：Swift 的 `sorted` 不保证稳定，
    /// 只按优先级排会把人工维护的顺序打乱，所以显式用注册表下标做第二排序键。
    /// 首页的「置顶」靠它把置顶服务提到所属分类最前。
    public static func grouped(
        prioritizing priority: (ServiceDefinition) -> Int
    ) -> [(category: ServiceDefinition.Category, services: [ServiceDefinition])] {
        let registryIndex = Dictionary(
            all.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        return ServiceDefinition.Category.allCases.compactMap { category in
            let matches = all
                .filter { $0.category == category }
                .sorted {
                    let lhs = priority($0)
                    let rhs = priority($1)
                    if lhs != rhs { return lhs < rhs }
                    return (registryIndex[$0.id] ?? 0) < (registryIndex[$1.id] ?? 0)
                }
            return matches.isEmpty ? nil : (category, matches)
        }
    }

    public static func service(id: String) -> ServiceDefinition? {
        all.first { $0.id == id }
    }

    /// 校验注册表自身的完整性：id 唯一、色值合法、容器端口不冲突。
    public static func validate() -> [String] {
        var problems: [String] = []
        var seen = Set<String>()
        var containerPorts: [String: String] = [:]
        for service in all {
            if !seen.insert(service.id).inserted {
                problems.append("重复 id：\(service.id)")
            }
            if service.tint.count != 6 || Int(service.tint, radix: 16) == nil {
                problems.append("色值非法：\(service.id) → \(service.tint)")
            }
            if service.symbol.isEmpty {
                problems.append("缺少 SF Symbol：\(service.id)")
            }
            if service.name.isEmpty || service.summary.isEmpty {
                problems.append("缺少名称或说明：\(service.id)")
            }
            if let port = service.defaultPort {
                let key = "\(service.container ?? service.id):\(port)"
                if let existing = containerPorts[key] {
                    problems.append("容器端口冲突：\(existing) 与 \(service.id) 都是 \(key)")
                }
                containerPorts[key] = service.id
            }
        }
        return problems
    }
}
