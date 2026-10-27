import Foundation
import ZhongmiaoCore

/// 把旧版 `AppSettings` 里的三处明文密钥搬进 Keychain。
///
/// 必须先于 `SettingsStorage.load()` 执行：迁移成功就删掉原始 JSON 里的键，
/// 避免后续每次保存设置又把明文写回去。Keychain 写入失败时保留原键并报告，
/// 不做“写失败也当成功”的假迁移。
enum LegacySecretMigration {

    struct Report: Sendable {
        var migrated = 0
        var skipped = 0
        var failed: [String] = []

        var isEmpty: Bool { migrated == 0 && skipped == 0 && failed.isEmpty }

        var logText: String {
            var parts: [String] = []
            if migrated > 0 { parts.append("迁移 \(migrated) 项密钥到钥匙串") }
            if skipped > 0 { parts.append("跳过 \(skipped) 项已迁移密钥") }
            if !failed.isEmpty { parts.append("失败：\(failed.joined(separator: "、"))") }
            return parts.joined(separator: "；")
        }
    }

    private static let mappings: [(jsonKey: String, key: SecretStore.LegacyKey)] = [
        ("relaySecret", .relay),
        ("ntfyToken", .ntfy),
        ("mujianToken", .mujian)
    ]

    static func run(
        defaults: UserDefaults = .standard,
        keychain: KeychainStore = KeychainStore()
    ) -> Report {
        var report = Report()

        guard let data = defaults.data(forKey: SettingsStorage.userDefaultsKey),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return report
        }

        var changed = false
        for mapping in mappings {
            // Keychain 已有值：只清理明文，不覆盖。
            if (try? keychain.read(account: mapping.key.account)) != nil {
                if object.removeValue(forKey: mapping.jsonKey) != nil {
                    changed = true
                }
                report.skipped += 1
                continue
            }

            guard let raw = object[mapping.jsonKey] as? String else {
                if object.removeValue(forKey: mapping.jsonKey) != nil {
                    changed = true
                }
                continue
            }

            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                object.removeValue(forKey: mapping.jsonKey)
                changed = true
                continue
            }

            let payload = Data(value.utf8)
            do {
                try keychain.write(payload, account: mapping.key.account)
                guard try keychain.read(account: mapping.key.account) == payload else {
                    throw KeychainError(status: errSecInternalError, operation: "校验")
                }
                object.removeValue(forKey: mapping.jsonKey)
                changed = true
                report.migrated += 1
            } catch {
                report.failed.append(mapping.jsonKey)
            }
        }

        if changed, let cleaned = try? JSONSerialization.data(withJSONObject: object) {
            defaults.set(cleaned, forKey: SettingsStorage.userDefaultsKey)
        }
        return report
    }
}
