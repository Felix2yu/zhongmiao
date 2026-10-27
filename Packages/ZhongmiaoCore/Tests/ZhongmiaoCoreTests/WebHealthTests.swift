import Foundation
import Testing

@testable import ZhongmiaoCore

@Suite("内嵌浏览器导航策略")
struct WebContentPolicyTests {

    /// 关掉「站外链接在应用内打开」后的策略（出栈行为）。
    private let policy = WebContentPolicy(keepsExternalLinksInApp: false)
    /// 默认策略：站外链接也留在应用内。
    private let inAppPolicy = WebContentPolicy()
    private let host = "shenshi.example.com"

    @Test("同主机留在 App 内")
    func sameHost() {
        let url = URL(string: "https://shenshi.example.com/tasks/1")!
        #expect(policy.decision(for: url, serviceHost: host) == .allowInApp)
    }

    @Test("子域留在 App 内")
    func subdomain() {
        let url = URL(string: "https://cdn.shenshi.example.com/a.js")!
        #expect(policy.decision(for: url, serviceHost: host) == .allowInApp)
    }

    @Test("父域也可用（反向代理常见的 host 差异）")
    func parentDomain() {
        let url = URL(string: "https://example.com/")!
        #expect(policy.decision(for: url, serviceHost: host) == .allowInApp)
    }

    @Test("站外链接出栈")
    func external() {
        let url = URL(string: "https://example.org/article")!
        #expect(policy.decision(for: url, serviceHost: host) == .openExternally)
    }

    @Test("相似但不同站的主机不会被误判")
    func lookalikeHost() {
        let url = URL(string: "https://evilshenshi.example.com.attacker.net/")!
        #expect(policy.decision(for: url, serviceHost: host) == .openExternally)
    }

    @Test("登录授权域留在 App 内")
    func trustedAuthHost() {
        let url = URL(string: "https://appleid.apple.com/auth")!
        #expect(policy.decision(for: url, serviceHost: host) == .allowInApp)
    }

    @Test("系统协议交给外部处理")
    func systemSchemes() {
        #expect(policy.decision(for: URL(string: "mailto:a@b.com")!, serviceHost: host) == .openExternally)
        #expect(policy.decision(for: URL(string: "tel:10086")!, serviceHost: host) == .openExternally)
        #expect(policy.decision(for: URL(string: "itms-apps://apps.apple.com")!, serviceHost: host) == .openExternally)
    }

    @Test("未知协议直接丢弃，避免崩溃")
    func unknownScheme() {
        #expect(policy.decision(for: URL(string: "weird-scheme://payload")!, serviceHost: host) == .cancel)
    }

    @Test("blob 与 about 放行（编辑器、打印等场景）")
    func inlineSchemes() {
        #expect(policy.decision(for: URL(string: "about:blank")!, serviceHost: host) == .allowInApp)
        #expect(policy.decision(for: URL(string: "blob:https://shenshi.example.com/uuid")!, serviceHost: host) == .allowInApp)
    }

    @Test("站外链接默认留在应用内（不丢给 Safari）")
    func externalStaysInAppByDefault() {
        let url = URL(string: "https://example.org/article")!
        #expect(inAppPolicy.decision(for: url, serviceHost: host) == .allowInApp)
        // 相似域名同样留在应用内，但不会被判定为同站（桥不注入）。
        let lookalike = URL(string: "https://evilshenshi.example.com.attacker.net/")!
        #expect(inAppPolicy.decision(for: lookalike, serviceHost: host) == .allowInApp)
        #expect(!inAppPolicy.shouldInjectBridge(for: lookalike, serviceHost: host))
    }

    @Test("即使留在应用内，系统协议仍然出栈")
    func systemSchemesStayExternalInAppMode() {
        #expect(inAppPolicy.decision(for: URL(string: "tel:10086")!, serviceHost: host) == .openExternally)
        #expect(inAppPolicy.decision(for: URL(string: "mailto:a@b.com")!, serviceHost: host) == .openExternally)
        #expect(inAppPolicy.decision(for: URL(string: "weird-scheme://payload")!, serviceHost: host) == .cancel)
    }

    @Test("只给自己的站点注入原生桥")
    func bridgeInjection() {
        #expect(policy.shouldInjectBridge(for: URL(string: "https://shenshi.example.com/")!, serviceHost: host))
        #expect(!policy.shouldInjectBridge(for: URL(string: "https://example.org/")!, serviceHost: host))
    }
}

@Suite("服务体检")
struct ServiceHealthTests {

    @Test("状态码分类")
    func statusCodes() {
        #expect(HealthClassifier.classify(statusCode: 200).isUsable)
        #expect(HealthClassifier.classify(statusCode: 302).isUsable)
        #expect(HealthClassifier.classify(statusCode: 401) == .needsAuth)
        #expect(HealthClassifier.classify(statusCode: 403) == .needsAuth)
        #expect(HealthClassifier.classify(statusCode: 502) == .serverError(status: 502))
    }

    @Test("延迟合并只对成功状态生效")
    func latencyMerge() {
        #expect(HealthClassifier.merging(.ok(latencyMilliseconds: 0), latencyMilliseconds: 37) == .ok(latencyMilliseconds: 37))
        #expect(HealthClassifier.merging(.needsAuth, latencyMilliseconds: 12) == .needsAuth)
    }

    @Test("常见网络错误给出中文原因")
    func errorClassification() {
        #expect(
            HealthClassifier.classify(errorCode: NSURLErrorCannotFindHost, description: "")
                == .unreachable(reason: "域名解析失败")
        )
        #expect(
            HealthClassifier.classify(errorCode: NSURLErrorTimedOut, description: "")
                == .unreachable(reason: "连接超时")
        )
        #expect(
            HealthClassifier.classify(errorCode: NSURLErrorNotConnectedToInternet, description: "")
                == .unreachable(reason: "当前无网络")
        )
        #expect(
            HealthClassifier.classify(errorCode: -12345, description: "")
                == .unreachable(reason: "错误 -12345")
        )
    }

    @Test("可读文案")
    func titles() {
        #expect(ServiceHealth.ok(latencyMilliseconds: 42).title == "可达 · 42 ms")
        #expect(ServiceHealth.notConfigured.title == "未配置地址")
        #expect(ServiceHealth.ok(latencyMilliseconds: 1).symbol == "checkmark.circle.fill")
        #expect(!ServiceHealth.serverError(status: 500).isUsable)
    }
}
