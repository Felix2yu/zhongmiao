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

    /// 本机起的临时服务地址。模拟器用 127.0.0.1，真机要填 Mac 的局域网地址。
    private static var host: String {
        let raw = ProcessInfo.processInfo.environment["ZM_HOST"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return "127.0.0.1" }
        return raw
    }

    static func baseURL(for serviceID: String) -> URL? {
        // 只覆盖正在预览的那一个服务。早前对所有服务生效，会把用户在设置里
        // 改的地址一起盖掉，导致「改了地址还是连老 IP」。
        guard let preview = previewServiceID, preview == serviceID else { return nil }
        let ports: [String: Int] = [
            "qiansi": 18080,
            "qingye": 18081,
            "huozhi": 18082,
            "shenshi": 18083,
            "diarum": 18084,
            "yuexi": 18087,
            "mujian": 18088,
            "liuxia": 18089,
            "ntfy": 18090,
            "qbhive": 18091,
            "bili-history": 18092,
            "chaxin": 18093
        ]
        return ports[serviceID].flatMap { URL(string: "http://\(host):\($0)") }
    }

    /// 预览模式下在页面上标一条提示，避免「地址被调试覆盖」这种状态悄无声息。
    static func previewBadge(for serviceID: String) -> String? {
        guard previewServiceID == serviceID, let url = baseURL(for: serviceID) else { return nil }
        return "调试直连 \(url.host ?? ""):\(url.port ?? 0)"
    }


    /// 清掉调试种子写进钥匙串的凭据，让设备回到「什么都没配」的状态。
    /// 用途：本机临时服务跑完测试后，别把测试账号留在真机上。
    static func clearIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard env["ZM_SEED_CLEAR"] == "1" else { return }
        let keychain = KeychainStore()
        for serviceID in ["qiansi", "shenshi", "qbhive", "huozhi", "diarum", "yuexi"] {
            try? keychain.delete(account: serviceID)
        }
        try? keychain.delete(account: "legacy.mujian")
        try? keychain.delete(account: "legacy.ntfy")
        NSLog("[ZMSeed] cleared seeded credentials")
    }

    static func applyIfNeeded() {
        clearIfRequested()
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
