import Foundation

/// 一个应用的原生凭据。整包作为 JSON 存进 Keychain，不落 UserDefaults。
struct IntegrationCredential: Codable, Hashable, Sendable {

    /// 共享 Token / API Key（牵丝、幕间、慎始、蜂巢、ntfy）。
    var token: String?
    var username: String?
    var password: String?
    /// 登录换来的 JWT（货殖、吾身）。
    var jwt: String?
    /// 月汐的会话 Cookie 值（不含 `session=` 前缀）。
    var sessionCookie: String?
    var expiresAt: Date?
    var updatedAt: Date?

    init(
        token: String? = nil,
        username: String? = nil,
        password: String? = nil,
        jwt: String? = nil,
        sessionCookie: String? = nil,
        expiresAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.token = token
        self.username = username
        self.password = password
        self.jwt = jwt
        self.sessionCookie = sessionCookie
        self.expiresAt = expiresAt
        self.updatedAt = updatedAt
    }

    var isEmpty: Bool {
        [token, jwt, sessionCookie].allSatisfy { value in
            (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var bearer: String {
        (jwt ?? token ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var cookieHeader: String? {
        guard let sessionCookie, !sessionCookie.isEmpty else { return nil }
        return "session=\(sessionCookie)"
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= .now
    }
}
