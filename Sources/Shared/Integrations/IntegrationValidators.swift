import Foundation
import ZhongmiaoCore

struct IntegrationCredentialInput: Sendable {
    var token: String?
    var username: String?
    var password: String?
}

/// 各应用的凭据校验。登录型应用在这里换取 JWT / 会话 Cookie，
/// 返回的凭据只有校验成功才会被写入 Keychain。
enum IntegrationValidators {

    private struct HuozhiLoginBody: Encodable {
        let username: String
        let password: String
    }

    private struct HuozhiLoginPayload: Decodable {
        let token: String
        let expire_in: Int?
    }

    private struct DiarumLoginBody: Encodable {
        let usernameOrEmail: String
        let password: String
    }

    private struct DiarumLoginResponse: Decodable {
        let token: String
    }

    private struct ShenshiAuthStatus: Decodable {
        let required: Bool
        let authenticated: Bool
    }

    static func validate(
        definition: IntegrationDefinition,
        baseURL: URL,
        credential: IntegrationCredential
    ) async throws -> IntegrationCredential {
        switch definition.serviceID {
        case "huozhi":
            return try await validateHuozhi(baseURL: baseURL, credential: credential)
        case "qiansi":
            try await checkToken(
                baseURL: baseURL,
                basePath: definition.basePath,
                token: credential.token,
                path: "/health"
            )
            return credential
        case "qingye":
            let http = IntegrationHTTP(baseURL: baseURL, basePath: "")
            _ = try await http.data("/healthz")
            return credential
        case "mujian":
            try await checkToken(
                baseURL: baseURL,
                basePath: definition.basePath,
                token: credential.token,
                path: "/stats"
            )
            return credential
        case "diarum":
            return try await validateDiarum(baseURL: baseURL, credential: credential)
        case "shenshi":
            try await validateShenshi(baseURL: baseURL, credential: credential)
            return credential
        case "qbhive":
            try await checkToken(
                baseURL: baseURL,
                basePath: definition.basePath,
                token: credential.token,
                path: "/torrents/stats"
            )
            return credential
        case "ntfy":
            let token = credential.token?.trimmingCharacters(in: .whitespacesAndNewlines)
            let http = IntegrationHTTP(baseURL: baseURL, basePath: "", token: token)
            if (token ?? "").isEmpty {
                _ = try await http.data("/v1/topics")
            } else {
                _ = try await http.data("/v1/account")
            }
            return credential
        case "yuexi":
            return try await validateYuexi(baseURL: baseURL, credential: credential)
        case "bili-history", "chaxin", "liuxia":
            let http = IntegrationHTTP(baseURL: baseURL, basePath: definition.basePath)
            _ = try await http.data("/health")
            return credential
        case "whoami":
            let http = IntegrationHTTP(baseURL: baseURL, basePath: "")
            _ = try await http.data("/api/whoami")
            return credential
        case "tuqie":
            let http = IntegrationHTTP(baseURL: baseURL, basePath: "")
            _ = try await http.data("/api/health")
            return credential
        default:
            throw IntegrationAPIError.notConfigured
        }
    }

    // MARK: - 简单令牌

    private static func checkToken(
        baseURL: URL,
        basePath: String,
        token: String?,
        path: String
    ) async throws {
        let http = IntegrationHTTP(baseURL: baseURL, basePath: basePath, token: token)
        _ = try await http.data(path)
    }

    // MARK: - 货殖

    private static func validateHuozhi(
        baseURL: URL,
        credential: IntegrationCredential
    ) async throws -> IntegrationCredential {
        guard let username = credential.username, !username.isEmpty,
              let password = credential.password, !password.isEmpty else {
            throw IntegrationAPIError.server(code: -1, message: "请填写货殖账号和密码")
        }

        let body = try JSONEncoder().encode(HuozhiLoginBody(username: username, password: password))
        let loginData = try await IntegrationHTTP(baseURL: baseURL, basePath: "/api").data(
            "/auth/login",
            method: "POST",
            body: body
        )
        let payloadData = try IntegrationEnvelope.unwrapCode(loginData)
        let payload: HuozhiLoginPayload
        do {
            payload = try JSONDecoder().decode(HuozhiLoginPayload.self, from: payloadData)
        } catch {
            throw IntegrationAPIError.decoding("货殖登录响应：\(error.localizedDescription)")
        }

        let http = IntegrationHTTP(baseURL: baseURL, basePath: "/api", token: payload.token)
        _ = try IntegrationEnvelope.unwrapCode(try await http.data("/auth/me"))

        var result = credential
        result.jwt = payload.token
        result.expiresAt = payload.expire_in.map { Date().addingTimeInterval(TimeInterval($0)) }
        result.updatedAt = .now
        return result
    }

    // MARK: - 吾身

    private static func validateDiarum(
        baseURL: URL,
        credential: IntegrationCredential
    ) async throws -> IntegrationCredential {
        guard let username = credential.username, !username.isEmpty,
              let password = credential.password, !password.isEmpty else {
            throw IntegrationAPIError.server(code: -1, message: "请填写吾身账号和密码")
        }

        let body = try JSONEncoder().encode(DiarumLoginBody(usernameOrEmail: username, password: password))
        let loginData = try await IntegrationHTTP(baseURL: baseURL, basePath: "/api/v1").data(
            "/auth/login",
            method: "POST",
            body: body
        )
        let payload: DiarumLoginResponse
        do {
            payload = try JSONDecoder().decode(DiarumLoginResponse.self, from: loginData)
        } catch {
            throw IntegrationAPIError.decoding("吾身登录响应：\(error.localizedDescription)")
        }

        let http = IntegrationHTTP(baseURL: baseURL, basePath: "/api/v1", token: payload.token)
        let zone = TimeZone.current.identifier
        _ = try await http.data("/diaries/stats", query: [URLQueryItem(name: "tz", value: zone)])

        var result = credential
        result.jwt = payload.token
        result.expiresAt = Date().addingTimeInterval(30 * 24 * 3600)
        result.updatedAt = .now
        return result
    }

    // MARK: - 慎始

    private static func validateShenshi(
        baseURL: URL,
        credential: IntegrationCredential
    ) async throws {
        let statusData = try await IntegrationHTTP(baseURL: baseURL, basePath: "/api")
            .data("/auth/status")
        let status: ShenshiAuthStatus
        do {
            status = try JSONDecoder().decode(ShenshiAuthStatus.self, from: statusData)
        } catch {
            throw IntegrationAPIError.decoding("慎始鉴权状态：\(error.localizedDescription)")
        }
        let token = credential.token?.trimmingCharacters(in: .whitespacesAndNewlines)
        if status.required && (token ?? "").isEmpty {
            throw IntegrationAPIError.unauthorized
        }
        let http = IntegrationHTTP(baseURL: baseURL, basePath: "/api", token: token)
        _ = try await http.data("/bootstrap")
    }

    // MARK: - 月汐

    private static func validateYuexi(
        baseURL: URL,
        credential: IntegrationCredential
    ) async throws -> IntegrationCredential {
        guard let username = credential.username, !username.isEmpty,
              let password = credential.password, !password.isEmpty else {
            throw IntegrationAPIError.server(code: -1, message: "请填写月汐账号和密码")
        }

        let form = "username=\(formEncode(username))&password=\(formEncode(password))"
        let (_, loginResponse) = try await IntegrationHTTP(
            baseURL: baseURL,
            basePath: "",
            session: NoRedirectSession.shared
        ).raw(
            "/login",
            method: "POST",
            body: Data(form.utf8),
            contentType: "application/x-www-form-urlencoded"
        )

        guard let cookie = sessionCookie(from: loginResponse) else {
            throw IntegrationAPIError.server(code: -1, message: "月汐账号或密码不正确")
        }

        let http = IntegrationHTTP(
            baseURL: baseURL,
            basePath: "",
            cookie: "session=\(cookie)"
        )
        _ = try await http.data("/api/records")

        var result = credential
        result.sessionCookie = cookie
        result.expiresAt = Date().addingTimeInterval(30 * 24 * 3600)
        result.updatedAt = .now
        return result
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func sessionCookie(from response: HTTPURLResponse) -> String? {
        let headers = response.allHeaderFields
        var raw: String?
        for (key, value) in headers {
            guard let key = key as? String, key.lowercased() == "set-cookie" else { continue }
            raw = (raw.map { $0 + "\n" } ?? "") + String(describing: value)
        }
        guard let raw else { return nil }
        let pattern = #"(?:^|\n)\s*session=([^;\n]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(raw.startIndex..., in: raw)
        guard let match = regex.firstMatch(in: raw, range: range),
              let valueRange = Range(match.range(at: 1), in: raw) else {
            return nil
        }
        return String(raw[valueRange])
    }
}

/// 月汐登录返回 303，默认 URLSession 会跟随并把 Set-Cookie 丢掉。
/// 这里固定不跟随重定向，改为自己读响应头。
private final class NoRedirectSession: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = ["User-Agent": "Zhongmiao/0.1"]
        let delegate = NoRedirectSession()
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
