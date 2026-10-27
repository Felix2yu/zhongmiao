import Foundation
import Testing

@testable import ZhongmiaoCore

@Suite("原生接入注册表")
struct IntegrationCatalogTests {

    @Test("覆盖全部服务且自身合法")
    func coversEveryService() {
        #expect(IntegrationCatalog.validate().isEmpty)
        #expect(IntegrationCatalog.all.count == ServiceCatalog.all.count)
        #expect(Set(IntegrationCatalog.all.map(\.serviceID)) == Set(ServiceCatalog.all.map(\.id)))
        #expect(IntegrationCatalog.all.filter { $0.priority == .web }.count == 2)
    }

    @Test("优先级分组完整")
    func priorityGroups() {
        let grouped = IntegrationCatalog.grouped
        #expect(grouped.map(\.priority) == [.p0, .p1, .p2, .web])
        #expect(grouped.flatMap(\.definitions).count == IntegrationCatalog.all.count)
    }

    @Test("点名场景的优先级与鉴权钉住")
    func namedScenarios() throws {
        let huozhi = try #require(IntegrationCatalog.definition(for: "huozhi"))
        #expect(huozhi.priority == .p0)
        #expect(huozhi.authKind == .login)
        #expect(huozhi.writes.contains { $0.title == "信用卡还款" })

        let qiansi = try #require(IntegrationCatalog.definition(for: "qiansi"))
        #expect(qiansi.priority == .p0)
        #expect(qiansi.authKind == .bearerToken)
        #expect(qiansi.credentialOptional)
        #expect(qiansi.supportsReminders)

        let qingye = try #require(IntegrationCatalog.definition(for: "qingye"))
        #expect(qingye.priority == .p0)
        #expect(qingye.authKind == .none)
        #expect(qingye.supportsReminders)
    }

    @Test("保留网页版的应用不声明原生能力")
    func webOnlyHasNoCapabilities() {
        for definition in IntegrationCatalog.all where definition.priority == .web {
            #expect(definition.capabilities.isEmpty)
        }
    }

    @Test("path 前缀格式合法")
    func basePaths() {
        for definition in IntegrationCatalog.all where !definition.basePath.isEmpty {
            #expect(definition.basePath.hasPrefix("/"))
            #expect(!definition.basePath.hasSuffix("/"))
        }
    }

    @Test("未登记的服务回退网页")
    func unknownFallsBackToWeb() {
        #expect(IntegrationCatalog.definition(for: "not-exist") == nil)
        #expect(IntegrationRouter.resolve(serviceID: "not-exist", hasExplicitURL: false, preferWeb: false) == .web)
    }
}
