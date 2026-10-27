import Foundation

/// 原生接入统一错误。各应用的信封不同，但最终都归到这里。
public enum IntegrationAPIError: Error, Sendable, Equatable {
    case unauthorized
    case forbidden
    case rateLimited(retryAfter: Int?)
    case http(status: Int, message: String?)
    case server(code: Int, message: String)
    case decoding(String)
    case transport(String)
    case notJSON
    case notConfigured

    public var needsReauthorization: Bool {
        switch self {
        case .unauthorized, .forbidden: true
        default: false
        }
    }

    public var isConnectivityFailure: Bool {
        switch self {
        case .transport: true
        default: false
        }
    }

    public var userMessage: String {
        switch self {
        case .unauthorized:
            "登录状态已失效，请重新授权。"
        case .forbidden:
            "没有访问权限，请检查凭据。"
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter > 0 {
                "请求过于频繁，请 \(retryAfter) 秒后再试。"
            } else {
                "请求过于频繁，请稍后再试。"
            }
        case .http(let status, let message):
            message.map { "服务返回 HTTP \(status)：\($0)" } ?? "服务返回 HTTP \(status)。"
        case .server(_, let message):
            message
        case .decoding(let detail):
            // 带出具体原因，别只说一句「可能接口版本已变化」，那没法定位。
            detail.isEmpty
                ? "返回数据无法解析，可能接口版本已变化。"
                : "返回数据无法解析：\(detail)"
        case .transport(let message):
            "网络请求失败：\(message)"
        case .notJSON:
            "接口返回的不是 JSON，请检查地址或登录状态。"
        case .notConfigured:
            "尚未配置可用的接入地址。"
        }
    }
}

extension IntegrationAPIError: LocalizedError {
    public var errorDescription: String? { userMessage }
}

/// 各应用响应信封的拆包工具。只处理“从 JSON 里拿到 data / 判断业务错误”，
/// 不做通用请求抽象。
public enum IntegrationEnvelope {

    public static func object(from data: Data) -> [String: Any]? {
        guard !data.isEmpty,
              let value = try? JSONSerialization.jsonObject(with: data),
              let object = value as? [String: Any] else {
            return nil
        }
        return object
    }

    /// 用于非 2xx 时提取可读错误。
    public static func message(from data: Data) -> String? {
        if let object = object(from: data) {
            if let message = object["message"] as? String, !message.isEmpty {
                return message
            }
            if let error = object["error"] as? String, !error.isEmpty {
                return error
            }
            if let message = object["msg"] as? String, !message.isEmpty {
                return message
            }
        }
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty else {
            return nil
        }
        let prefix = text.prefix(200)
        return prefix.hasPrefix("<") ? nil : String(prefix)
    }

    /// `{ "code": 0, "message": "ok", "data": ... }`
    /// 青野、货殖使用；业务错误可能仍是 HTTP 200。
    public static func unwrapCode(_ data: Data) throws -> Data {
        guard let object = object(from: data) else { throw IntegrationAPIError.notJSON }
        if let code = object["code"] as? Int {
            if code != 0 {
                let message = (object["message"] as? String)
                    ?? (object["error"] as? String)
                    ?? "接口返回错误（\(code)）"
                throw IntegrationAPIError.server(code: code, message: message)
            }
        } else if let success = object["success"] as? Bool, success == false {
            let message = (object["message"] as? String) ?? "接口返回失败"
            throw IntegrationAPIError.server(code: -1, message: message)
        }
        let payload = object["data"] ?? NSNull()
        return try JSONSerialization.data(withJSONObject: payload)
    }

    /// `{ "status": "success", "data": ... }`，失败时通常仍是 HTTP 200。
    public static func unwrapStatus(_ data: Data) throws -> Data {
        guard let object = object(from: data) else { throw IntegrationAPIError.notJSON }
        if let status = object["status"] as? String, status != "success" {
            throw IntegrationAPIError.server(
                code: -1,
                message: (object["message"] as? String) ?? "接口返回 \(status)"
            )
        }
        if let success = object["success"] as? Bool, success == false {
            throw IntegrationAPIError.server(
                code: -1,
                message: (object["message"] as? String) ?? "接口返回失败"
            )
        }
        let payload = object["data"] ?? NSNull()
        return try JSONSerialization.data(withJSONObject: payload)
    }

    public static func isLikelyJSON(_ data: Data) -> Bool {
        let whitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
        guard let first = data.first(where: { !whitespace.contains($0) }) else { return false }
        return first == UInt8(ascii: "{") || first == UInt8(ascii: "[")
    }
}
