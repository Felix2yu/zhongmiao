import Foundation
import Observation
import ZhongmiaoCore

/// 凭据的唯一入口。内存里保留一份快照，改动即写 Keychain。
@MainActor
@Observable
final class SecretStore {

    enum LegacyKey: String, CaseIterable, Sendable {
        case relay
        case ntfy
        case mujian

        var account: String { "legacy.\(rawValue)" }

        var title: String {
            switch self {
            case .relay: "推送中继共享密钥"
            case .ntfy: "ntfy 访问令牌"
            case .mujian: "幕间访问令牌"
            }
        }
    }

    private let keychain: KeychainStore

    private(set) var credentials: [String: IntegrationCredential] = [:]
    private(set) var legacyValues: [LegacyKey: String] = [:]
    /// 供设置页/演出排程观察的变更计数。
    private(set) var revision = 0
    private(set) var lastError: String?

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
        hydrate()
    }

    func credential(for serviceID: String) -> IntegrationCredential? {
        credentials[serviceID]
    }

    func save(_ credential: IntegrationCredential, for serviceID: String) throws {
        var value = credential
        value.updatedAt = .now
        let data = try JSONEncoder().encode(value)
        do {
            try keychain.write(data, account: serviceID)
        } catch {
            // 钥匙串写不进去也不能让本次会话失效：内存里这份是当前唯一可用的凭据
            // （登录型应用的会话 cookie 就靠它）。错误照抛，让上层知道没持久化成功。
            credentials[serviceID] = value
            revision += 1
            lastError = error.localizedDescription
            throw error
        }
        credentials[serviceID] = value
        revision += 1
        lastError = nil
    }

    func removeCredential(for serviceID: String) throws {
        try keychain.delete(account: serviceID)
        credentials[serviceID] = nil
        revision += 1
        lastError = nil
    }

    func value(for key: LegacyKey) -> String {
        legacyValues[key] ?? ""
    }

    func setValue(_ raw: String, for key: LegacyKey) throws {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            try keychain.delete(account: key.account)
            legacyValues[key] = nil
        } else {
            try keychain.write(Data(value.utf8), account: key.account)
            legacyValues[key] = value
        }
        revision += 1
        lastError = nil
    }

    private func hydrate() {
        for definition in IntegrationCatalog.all {
            guard let data = try? keychain.read(account: definition.serviceID) else { continue }
            do {
                credentials[definition.serviceID] = try JSONDecoder().decode(IntegrationCredential.self, from: data)
            } catch {
                lastError = "「\(definition.serviceID)」的钥匙串凭据无法解码：\(error.localizedDescription)"
            }
        }
        NSLog("[ZMSecret] hydrated %@", credentials.keys.sorted().joined(separator: ","))
        for key in LegacyKey.allCases {
            guard let data = try? keychain.read(account: key.account) else { continue }
            if let text = String(data: data, encoding: .utf8) {
                legacyValues[key] = text
            }
        }
    }
}
