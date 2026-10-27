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

    /// 没有任何可用于鉴权的凭据。
    ///
    /// 登录型应用（货殖、吾身、月汐）在拿到 JWT / Cookie 之前只有账号密码，
    /// 这同样是「已配置」——否则开机时的静默重登会被跳过，界面还会误报「未配置」。
    var isEmpty: Bool {
        let hasSecret = [token, jwt, sessionCookie].contains { value in
            !(value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if hasSecret { return false }
        let hasLogin = [username, password].allSatisfy { value in
            !(value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !hasLogin
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
