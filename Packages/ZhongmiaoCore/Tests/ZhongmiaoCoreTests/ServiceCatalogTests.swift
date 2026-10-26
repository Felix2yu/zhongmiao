import Foundation
import Testing

@testable import ZhongmiaoCore

@Suite("服务注册表")
struct ServiceCatalogTests {

    @Test("注册表自身合法且 id 唯一")
    func catalogIsValid() {
        #expect(ServiceCatalog.validate().isEmpty)
        #expect(ServiceCatalog.all.count == 14)
        #expect(Set(ServiceCatalog.all.map(\.id)).count == 14)
    }

    @Test("分组覆盖全部分类且不丢服务")
    func groupingIsComplete() {
        let grouped = ServiceCatalog.grouped.flatMap(\.services)
        #expect(grouped.count == ServiceCatalog.all.count)
        #expect(Set(grouped.map(\.id)) == Set(ServiceCatalog.all.map(\.id)))
    }

    @Test("置顶排序稳定，不打扰注册表顺序")
    func prioritySortIsStable() throws {
        // 挑一个成员数足够多的分类，断言「其余服务相对顺序不变」才有意义。
        let baselineGroup = try #require(ServiceCatalog.grouped.first { $0.services.count >= 3 })
        let category = baselineGroup.category
        let baseline = baselineGroup.services
        let target = try #require(baseline.last)

        let ranked = ServiceCatalog.grouped { $0.id == target.id ? 0 : 1 }
        let after = try #require(ranked.first { $0.category == category }).services

        // 置顶的排到最前。
        #expect(after.first?.id == target.id)
        // 其余服务保持原有相对顺序 —— Swift 的 sorted 不稳定，这条就是防它把顺序打乱。
        #expect(Array(after.dropFirst()).map(\.id) == Array(baseline.dropLast()).map(\.id))
        // 分类顺序与总数不受影响。
        #expect(ranked.map(\.category) == ServiceCatalog.grouped.map(\.category))
        #expect(ranked.flatMap(\.services).count == ServiceCatalog.all.count)
    }

    @Test("优先级全相同时与默认分组完全一致")
    func zeroPriorityMatchesDefault() {
        let ranked = ServiceCatalog.grouped { _ in 0 }
        let baseline = ServiceCatalog.grouped
        #expect(ranked.map(\.category) == baseline.map(\.category))
        #expect(ranked.flatMap { $0.services.map(\.id) } == baseline.flatMap { $0.services.map(\.id) })
    }

    @Test("子域名模式生成 HTTPS 地址")
    func subdomainResolution() throws {
        let service = try #require(ServiceCatalog.service(id: "shenshi"))
        let settings = AddressSettings(mode: .subdomain, baseDomain: "example.com")
        let url = try #require(ServiceURLResolver.url(for: service, settings: settings))
        #expect(url.absoluteString == "https://shenshi.example.com/")
    }

    @Test("端口模式使用内网主机与端口")
    func portResolution() throws {
        let service = try #require(ServiceCatalog.service(id: "qbhive"))
        let settings = AddressSettings(mode: .port, lanHost: "10.0.0.2")
        let url = try #require(ServiceURLResolver.url(for: service, settings: settings))
        #expect(url.absoluteString == "http://10.0.0.2:8088/")
    }

    @Test("端口缺失时判定为不可解析")
    func missingPortIsNotResolvable() {
        let service = ServiceDefinition(
            id: "noport",
            name: "无端口",
            summary: "测试用",
            symbol: "questionmark",
            tint: "FFFFFF",
            category: .infrastructure,
            kind: .web
        )
        let settings = AddressSettings(mode: .port, lanHost: "10.0.0.2")
        #expect(ServiceURLResolver.url(for: service, settings: settings) == nil)
        #expect(!ServiceURLResolver.isResolvable(service, settings: settings))
    }

    @Test("子路径模式生成同主机的路径地址")
    func pathResolution() throws {
        let service = try #require(ServiceCatalog.service(id: "shenshi"))
        let settings = AddressSettings(mode: .path, baseDomain: "example.com")
        let url = try #require(ServiceURLResolver.url(for: service, settings: settings))
        #expect(url.absoluteString == "https://example.com/shenshi/")
    }

    @Test("容器内部端口取自 EXPOSE，且容器名可解析")
    func containerMetadata() throws {
        let qingye = try #require(ServiceCatalog.service(id: "qingye"))
        #expect(qingye.defaultPort == 8081)
        #expect(qingye.container == "qingye")

        let diarum = try #require(ServiceCatalog.service(id: "diarum"))
        #expect(diarum.defaultPort == 8090)

        // 按服务统计：8080 只应出现在不同容器上，不应出现同名容器重复端口
        let keys = ServiceCatalog.all.compactMap { service in
            service.defaultPort.map { "\(service.container ?? service.id):\($0)" }
        }
        #expect(Set(keys).count == keys.count)
    }

    @Test("用户覆盖优先于全局配置，并保留落地路径")
    func overrideWins() throws {
        let service = try #require(ServiceCatalog.service(id: "shenshi"))
        let settings = AddressSettings(mode: .subdomain, baseDomain: "example.com")
        let url = try #require(
            ServiceURLResolver.url(for: service, settings: settings, override: "http://192.168.1.5:8787")
        )
        #expect(url.absoluteString == "http://192.168.1.5:8787/")
    }

    @Test("地址清洗：去掉协议与路径、保留端口")
    func sanitizesHostInput() throws {
        let service = try #require(ServiceCatalog.service(id: "ntfy"))
        let settings = AddressSettings(mode: .port, lanHost: " http://192.168.1.10:8080/ntfy ")
        let url = try #require(ServiceURLResolver.url(for: service, settings: settings))
        #expect(url.host == "192.168.1.10")
        #expect(url.port == 80)
    }

    @Test("空域名回退为不可解析")
    func emptyDomain() throws {
        let service = try #require(ServiceCatalog.service(id: "shenshi"))
        let settings = AddressSettings(mode: .subdomain, baseDomain: "   ")
        #expect(ServiceURLResolver.url(for: service, settings: settings) == nil)
    }

    @Test("子域名前缀回退到 id 并过滤非法字符")
    func subdomainFallback() throws {
        let service = try #require(ServiceCatalog.service(id: "bili-history"))
        let settings = AddressSettings(mode: .subdomain, baseDomain: "example.com")
        let url = try #require(ServiceURLResolver.url(for: service, settings: settings))
        #expect(url.host == "bili.example.com")
    }

    @Test("离线能力文案不与「服务离线」状态撞车")
    func offlineCapabilityWording() {
        // 「离线」二字在中文里既能读成能力、也能读成状态。
        // 挂在卡片上的文案必须自带「可用／需要联网」这类限定词，
        // 否则会被理解成服务当前挂了。
        #expect(ServiceDefinition.Kind.pwa.offlineCapabilityDescription == "离线可用")
        #expect(ServiceDefinition.Kind.web.offlineCapabilityDescription == "需要联网")
        #expect(ServiceDefinition.Kind.utility.offlineCapabilityDescription == "需要联网")

        // 任何一种形态的文案都不能退化成裸的「离线」。
        for kind in ServiceDefinition.Kind.allCases {
            #expect(kind.offlineCapabilityDescription != "离线")
            #expect(kind.offlineCapabilityDescription.count > 2)
        }
    }

    @Test("无障碍描述带上离线能力限定词")
    func accessibilityDescriptionMentionsCapability() throws {
        let pwa = try #require(ServiceCatalog.service(id: "shenshi"))
        #expect(pwa.accessibilityDescription.contains("离线可用"))

        let web = try #require(ServiceCatalog.service(id: "qbhive"))
        #expect(web.accessibilityDescription.contains("需要联网"))
    }
}
