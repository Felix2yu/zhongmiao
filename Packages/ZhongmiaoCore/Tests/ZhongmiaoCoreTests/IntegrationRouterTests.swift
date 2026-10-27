import Testing

@testable import ZhongmiaoCore

@Suite("原生接入路由")
struct IntegrationRouterTests {

    @Test("普通进入走原生")
    func nativeByDefault() {
        #expect(IntegrationRouter.resolve(serviceID: "qingye", hasExplicitURL: false, preferWeb: false) == .native)
        #expect(IntegrationRouter.resolve(serviceID: "huozhi", hasExplicitURL: false, preferWeb: false) == .native)
    }

    @Test("带具体地址的深链必须走网页")
    func explicitURLStaysWeb() {
        #expect(IntegrationRouter.resolve(serviceID: "qiansi", hasExplicitURL: true, preferWeb: false) == .web)
    }

    @Test("用户选择优先网页版")
    func preferWebWins() {
        #expect(IntegrationRouter.resolve(serviceID: "huozhi", hasExplicitURL: false, preferWeb: true) == .web)
    }

    @Test("网页版应用永远走网页")
    func webOnlyStaysWeb() {
        #expect(IntegrationRouter.resolve(serviceID: "whoami", hasExplicitURL: false, preferWeb: false) == .web)
        #expect(IntegrationRouter.resolve(serviceID: "tuqie", hasExplicitURL: false, preferWeb: true) == .web)
    }
}
