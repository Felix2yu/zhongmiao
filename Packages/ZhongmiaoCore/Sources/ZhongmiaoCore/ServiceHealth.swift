import Foundation

/// 单个服务的连通性体检结果。
public enum ServiceHealth: Equatable, Sendable {
    case unknown
    /// 地址解析不出来（端口模式下缺端口、域名留空）。
    case notConfigured
    case ok(latencyMilliseconds: Int)
    case needsAuth
    case serverError(status: Int)
    case unreachable(reason: String)

    public var isUsable: Bool {
        switch self {
        case .ok, .needsAuth: true
        default: false
        }
    }

    public var title: String {
        switch self {
        case .unknown: "未检测"
        case .notConfigured: "未配置地址"
        case .ok(let latency): "可达 · \(latency) ms"
        case .needsAuth: "可达 · 需要登录"
        case .serverError(let status): "服务异常 · HTTP \(status)"
        case .unreachable(let reason): "不可达 · \(reason)"
        }
    }

    public var symbol: String {
        switch self {
        case .unknown: "questionmark.circle"
        case .notConfigured: "slash.circle"
        case .ok: "checkmark.circle.fill"
        case .needsAuth: "lock.circle.fill"
        case .serverError: "exclamationmark.triangle.fill"
        case .unreachable: "xmark.circle.fill"
        }
    }
}

public enum HealthClassifier {

    /// 依据 HTTP 状态码判定。3xx 视为可用（重定向到登录页是正常现象）。
    public static func classify(statusCode: Int) -> ServiceHealth {
        switch statusCode {
        case 200..<400: .ok(latencyMilliseconds: 0)
        case 401, 403: .needsAuth
        default: .serverError(status: statusCode)
        }
    }

    /// 把 URLSession 的错误码翻译成用户能看懂的原因。
    public static func classify(errorCode: Int, description: String) -> ServiceHealth {
        switch errorCode {
        case NSURLErrorCannotFindHost: .unreachable(reason: "域名解析失败")
        case NSURLErrorCannotConnectToHost: .unreachable(reason: "无法连接主机")
        case NSURLErrorTimedOut: .unreachable(reason: "连接超时")
        case NSURLErrorNotConnectedToInternet: .unreachable(reason: "当前无网络")
        case NSURLErrorNetworkConnectionLost: .unreachable(reason: "连接中断")
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
            .unreachable(reason: "证书校验失败")
        case NSURLErrorAppTransportSecurityRequiresSecureConnection:
            .unreachable(reason: "被 ATS 拦截，需要 HTTPS")
        default: .unreachable(reason: description.isEmpty ? "错误 \(errorCode)" : description)
        }
    }

    /// 结合延迟生成最终结果。
    public static func merging(_ health: ServiceHealth, latencyMilliseconds: Int) -> ServiceHealth {
        if case .ok = health { return .ok(latencyMilliseconds: latencyMilliseconds) }
        return health
    }
}
