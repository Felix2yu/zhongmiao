import Foundation
import ZhongmiaoCore

/// 把内置注册表导出成 JSON，供部署脚本（Nginx 配置生成、证书清单）消费。
///
/// 用法：
///   swift run --package-path Packages/ZhongmiaoCore zm-catalog > deploy/catalog.json
///
/// 这样「应用里的服务清单」和「服务器上的反代配置」共用同一份事实，
/// 不会出现加了新服务但忘了改 Nginx 的情况。

struct Record: Encodable {
    let id: String
    let name: String
    let summary: String
    let category: String
    let kind: String
    /// 子域名前缀（已回退到 id）。
    let subdomain: String
    /// Docker 容器名 / compose 服务名（已回退到 id）。
    let container: String
    /// 容器内部端口。
    let port: Int?
    let path: String
    let feedPath: String?
    let ntfyTopic: String?
    let offline: Bool
}

let records = ServiceCatalog.all.map { service in
    Record(
        id: service.id,
        name: service.name,
        summary: service.summary,
        category: service.category.rawValue,
        kind: service.kind.rawValue,
        subdomain: service.subdomain ?? service.id,
        container: service.container ?? service.id,
        port: service.defaultPort,
        path: service.path,
        feedPath: service.notificationFeedPath,
        ntfyTopic: service.ntfyTopic,
        offline: service.kind.isOfflineCapable
    )
}

let problems = ServiceCatalog.validate()
if !problems.isEmpty {
    FileHandle.standardError.write(
        Data(("注册表自检失败：\n" + problems.map { "  - \($0)" }.joined(separator: "\n") + "\n").utf8)
    )
    exit(1)
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let data = try! encoder.encode(records)
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
