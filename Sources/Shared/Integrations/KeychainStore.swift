import Foundation
import Security

struct KeychainError: Error, LocalizedError, Sendable {

    let status: OSStatus
    let operation: String

    var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "未知错误"
        return "钥匙串\(operation)失败：\(message)（\(status)）"
    }
}

/// 无状态 Keychain 包装。`SecItem*` 本身线程安全，调用方无需异步化。
struct KeychainStore: Sendable {

    static let defaultService = "im.yufei.zhongmiao.integrations"

    let service: String

    init(service: String = KeychainStore.defaultService) {
        self.service = service
    }

    func read(account: String) throws -> Data? {
        for useDataProtection in Self.modes {
            var query = baseQuery(account: account, useDataProtection: useDataProtection)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            switch status {
            case errSecSuccess:
                return result as? Data
            case errSecItemNotFound:
                return nil
            case errSecMissingEntitlement, errSecParam:
                if useDataProtection { continue }
                throw KeychainError(status: status, operation: "读取")
            default:
                throw KeychainError(status: status, operation: "读取")
            }
        }
        return nil
    }

    func contains(account: String) -> Bool {
        (try? read(account: account)) != nil
    }

    func write(_ data: Data, account: String) throws {
        for useDataProtection in Self.modes {
            let deleteStatus = SecItemDelete(
                baseQuery(account: account, useDataProtection: useDataProtection) as CFDictionary
            )
            guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
                if useDataProtection, deleteStatus == errSecMissingEntitlement || deleteStatus == errSecParam {
                    continue
                }
                throw KeychainError(status: deleteStatus, operation: "写入")
            }

            var attributes = baseQuery(account: account, useDataProtection: useDataProtection)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

            let status = SecItemAdd(attributes as CFDictionary, nil)
            if status == errSecSuccess { return }
            if useDataProtection, status == errSecMissingEntitlement || status == errSecParam {
                continue
            }
            throw KeychainError(status: status, operation: "写入")
        }
        throw KeychainError(status: errSecParam, operation: "写入")
    }

    func delete(account: String) throws {
        for useDataProtection in Self.modes {
            let status = SecItemDelete(
                baseQuery(account: account, useDataProtection: useDataProtection) as CFDictionary
            )
            if status == errSecSuccess || status == errSecItemNotFound { return }
            if useDataProtection, status == errSecMissingEntitlement || status == errSecParam {
                continue
            }
            throw KeychainError(status: status, operation: "删除")
        }
    }

    private func baseQuery(account: String, useDataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
        if useDataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    /// 数据保护钥匙串需要签名能力。免费账号/未签名构建在 macOS 上可能失败，
    /// 这时退回传统钥匙串；绝不退回明文。
    private static let modes: [Bool] = {
        #if os(macOS)
        // macOS 上数据保护钥匙串需要签名能力，失败时退回传统钥匙串。
        [true, false]
        #else
        // iOS 默认就是数据保护钥匙串；显式传 kSecUseDataProtectionKeychain
        // 在模拟器/部分签名配置下反而会失败。
        [false]
        #endif
    }()
}
