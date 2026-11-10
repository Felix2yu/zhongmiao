import Foundation
import Testing
import ZhongmiaoCore

@Suite("深链解析")
struct DeepLinkTests {

    private func serviceID() -> String {
        // 取注册表里确实存在的一个应用，避免测试绑定具体的业务语义。
        guard let first = ServiceCatalog.all.first else {
            Issue.record("注册表为空，无法测试深链")
            return ""
        }
        return first.id
    }

    @Test("带 service 前缀的路径写法能解析出服务")
    func pathForm() {
        let id = serviceID()
        let link = DeepLink.parse(URL(string: "zhongmiao://service/\(id)")!)
        #expect(link.service?.serviceID == id)
        #expect(link.service?.target == nil)
    }

    @Test("host 直接写服务 ID 也能解析")
    func hostForm() {
        let id = serviceID()
        let link = DeepLink.parse(URL(string: "zhongmiao://\(id)")!)
        #expect(link.service?.serviceID == id)
    }

    @Test("target 与 id 齐全时才产生目标，缺一个就当没有")
    func targetParsing() {
        let id = serviceID()
        let full = DeepLink.parse(URL(string: "zhongmiao://service/\(id)?target=event&id=42")!)
        #expect(full.service?.target == NativeTarget(kind: "event", identifier: "42"))

        let missing = DeepLink.parse(URL(string: "zhongmiao://service/\(id)?target=event")!)
        #expect(missing.service?.target == nil)
        #expect(missing.service?.serviceID == id)
    }

    @Test("非本应用 scheme、空 host、未知服务都解析为空")
    func rejects() {
        let id = serviceID()
        #expect(DeepLink.parse(URL(string: "https://service/\(id)")!).service == nil)
        #expect(DeepLink.parse(URL(string: "zhongmiao://")!).service == nil)
        #expect(DeepLink.parse(URL(string: "zhongmiao://service/")!).service == nil)
        #expect(DeepLink.parse(URL(string: "zhongmiao://service/not-a-service")!).service == nil)
    }

    @Test("构造与解析互为逆运算")
    func roundTrip() {
        let id = serviceID()
        let target = NativeTarget(kind: "diary", identifier: "2026-10-27")
        guard let url = DeepLink.url(serviceID: id, target: target) else {
            Issue.record("构造深链失败")
            return
        }
        let link = DeepLink.parse(url)
        #expect(link.service?.serviceID == id)
        #expect(link.service?.target == target)
    }

    @Test("服务不在注册表时构造不出链接")
    func refusesUnknownService() {
        #expect(DeepLink.url(serviceID: "definitely-not-a-service") == nil)
    }
}
