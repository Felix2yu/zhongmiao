import Foundation
import Testing

@testable import ZhongmiaoCore

@Suite("接入响应信封")
struct IntegrationEnvelopeTests {

    @Test("code 为 0 时取出 data")
    func unwrapCodeSuccess() throws {
        let data = Data(#"{"code":0,"message":"ok","data":{"id":7,"name":"青野"}}"#.utf8)
        let payload = try IntegrationEnvelope.unwrapCode(data)
        let object = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect(object["id"] as? Int == 7)
        #expect(object["name"] as? String == "青野")
    }

    @Test("HTTP 200 但业务 code 非 0 也抛错")
    func unwrapCodeBusinessFailure() {
        let data = Data(#"{"code":1004,"message":"密码错误","data":null}"#.utf8)
        #expect(throws: IntegrationAPIError.server(code: 1004, message: "密码错误")) {
            try IntegrationEnvelope.unwrapCode(data)
        }
    }

    @Test("status 信封的失败也抛错")
    func unwrapStatusFailure() {
        let data = Data(#"{"status":"error","message":"数据库不可用"}"#.utf8)
        #expect(throws: IntegrationAPIError.server(code: -1, message: "数据库不可用")) {
            try IntegrationEnvelope.unwrapStatus(data)
        }
    }

    @Test("success 信封的失败也抛错")
    func unwrapSuccessFailure() {
        let data = Data(#"{"success":false,"message":"未授权"}"#.utf8)
        #expect(throws: IntegrationAPIError.server(code: -1, message: "未授权")) {
            try IntegrationEnvelope.unwrapCode(data)
        }
    }

    @Test("错误信息优先取 message/error")
    func messageExtraction() {
        #expect(IntegrationEnvelope.message(from: Data(#"{"error":"需要访问口令"}"#.utf8)) == "需要访问口令")
        #expect(IntegrationEnvelope.message(from: Data(#"{"message":"接口不存在"}"#.utf8)) == "接口不存在")
        #expect(IntegrationEnvelope.message(from: Data("<html>hello</html>".utf8)) == nil)
    }

    @Test("HTML 不会被当成 JSON")
    func htmlIsNotJSON() {
        let html = Data("<html><body>SPA</body></html>".utf8)
        #expect(!IntegrationEnvelope.isLikelyJSON(html))
        #expect(IntegrationEnvelope.isLikelyJSON(Data(#"{"a":1}"#.utf8)))
        #expect(IntegrationEnvelope.isLikelyJSON(Data(#"  [1,2]"#.utf8)))
    }
}
