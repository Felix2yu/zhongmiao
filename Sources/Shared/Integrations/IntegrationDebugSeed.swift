#if DEBUG
import Foundation
import ZhongmiaoCore

/// 仅调试构建使用：通过模拟器启动环境变量预置凭据并直达某个原生页，
/// 方便在没有 UI 自动化的情况下做端到端截图验证。Release 不编译。
enum IntegrationDebugSeed {

    static var previewServiceID: String? {
        let raw = ProcessInfo.processInfo.environment["ZM_PREVIEW_SERVICE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    static func baseURL(for serviceID: String) -> URL? {
        guard previewServiceID != nil else { return nil }
        let map: [String: String] = [
            "qiansi": "http://127.0.0.1:18080",
            "qingye": "http://127.0.0.1:18081",
            "huozhi": "http://127.0.0.1:18082",
            "shenshi": "http://127.0.0.1:18083",
            "diarum": "http://127.0.0.1:18084",
            "yuexi": "http://127.0.0.1:18087",
            "mujian": "http://127.0.0.1:18088",
            "liuxia": "http://127.0.0.1:18089",
            "qbhive": "http://127.0.0.1:18091",
            "ntfy": "http://127.0.0.1:18090",
            "bili-history": "http://127.0.0.1:18092",
            "chaxin": "http://127.0.0.1:18093"
        ]
        return map[serviceID].flatMap(URL.init(string:))
    }

    static func applyIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        NSLog("[ZMSeed] preview=%@ huozhi=%@ qiansi=%@", env["ZM_PREVIEW_SERVICE"] ?? "nil", env["ZM_HUOZHI_USERNAME"] ?? "nil", env["ZM_QIANSI_TOKEN"] ?? "nil")
        let keychain = KeychainStore()

        save(env["ZM_QIANSI_TOKEN"], serviceID: "qiansi", keychain: keychain)
        save(env["ZM_SHENSHI_TOKEN"], serviceID: "shenshi", keychain: keychain)
        save(env["ZM_QBHIVE_TOKEN"], serviceID: "qbhive", keychain: keychain)

        saveLogin(
            username: env["ZM_HUOZHI_USERNAME"],
            password: env["ZM_HUOZHI_PASSWORD"],
            serviceID: "huozhi",
            keychain: keychain
        )
        saveLogin(
            username: env["ZM_DIARUM_USERNAME"],
            password: env["ZM_DIARUM_PASSWORD"],
            serviceID: "diarum",
            keychain: keychain
        )
        saveLogin(
            username: env["ZM_YUEXI_USERNAME"],
            password: env["ZM_YUEXI_PASSWORD"],
            serviceID: "yuexi",
            keychain: keychain
        )

        if let token = env["ZM_MUJIAN_TOKEN"], !token.isEmpty {
            try? keychain.write(Data(token.utf8), account: "legacy.mujian")
        }
        if let token = env["ZM_NTFY_TOKEN"], !token.isEmpty {
            try? keychain.write(Data(token.utf8), account: "legacy.ntfy")
        }
    }

    private static func save(_ token: String?, serviceID: String, keychain: KeychainStore) {
        guard let token, !token.isEmpty else { return }
        let credential = IntegrationCredential(token: token, updatedAt: .now)
        guard let data = try? JSONEncoder().encode(credential) else { return }
        do {
            try keychain.write(data, account: serviceID)
            NSLog("[ZMSeed] wrote %@ token", serviceID)
        } catch {
            NSLog("[ZMSeed] write %@ failed: %@", serviceID, error.localizedDescription)
        }
    }

    private static func saveLogin(
        username: String?,
        password: String?,
        serviceID: String,
        keychain: KeychainStore
    ) {
        guard let username, !username.isEmpty, let password, !password.isEmpty else { return }
        let credential = IntegrationCredential(
            username: username,
            password: password,
            updatedAt: .now
        )
        guard let data = try? JSONEncoder().encode(credential) else { return }
        try? keychain.write(data, account: serviceID)
    }
}
#endif
