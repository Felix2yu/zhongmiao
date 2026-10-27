import Foundation
import Observation
import ZhongmiaoCore

/// 原生接入的状态中枢：凭据、验证状态、提醒偏好与排程。
/// 不保存各应用的业务快照——那些由各页面自己的 Model 持有。
@MainActor
@Observable
final class IntegrationCenter {

    enum CredentialState: Equatable, Sendable {
        case noAuth
        case unconfigured
        case unknown
        case checking
        case valid(Date)
        case expired(String)
        case invalid(String)

        var isUsable: Bool {
            switch self {
            case .noAuth, .valid: true
            default: false
            }
        }

        var needsAttention: Bool {
            switch self {
            case .unconfigured, .unknown, .expired, .invalid: true
            default: false
            }
        }

        var title: String {
            switch self {
            case .noAuth: "无需凭据"
            case .unconfigured: "未配置"
            case .unknown: "待验证"
            case .checking: "验证中"
            case .valid: "已连接"
            case .expired: "已失效"
            case .invalid: "连接失败"
            }
        }

        var message: String? {
            switch self {
            case .expired(let value), .invalid(let value): value
            default: nil
            }
        }
    }

    let secrets: SecretStore
    let cache = IntegrationCache.shared

    private(set) var states: [String: CredentialState] = [:]
    private(set) var preferences: IntegrationPreferences
    private(set) var lastErrors: [String: String] = [:]
    private(set) var reminderCounts: [String: Int] = [:]
    /// 提醒时刻/开关变更后 +1，打开中的原生页据此重排。
    private(set) var reminderRevision = 0

    private let scheduler = IntegrationReminderScheduler()

    init(secrets: SecretStore = SecretStore()) {
        self.secrets = secrets
        self.preferences = IntegrationPreferencesStore.load()
        for definition in IntegrationCatalog.all {
            if definition.authKind == .none {
                states[definition.serviceID] = .noAuth
            } else if let credential = credential(for: definition.serviceID),
                      !credential.isEmpty || credential.username != nil {
                states[definition.serviceID] = .unknown
            } else {
                states[definition.serviceID] = .unconfigured
            }
        }
    }

    // MARK: - 状态

    func state(for serviceID: String) -> CredentialState {
        states[serviceID] ?? .unconfigured
    }

    func credential(for serviceID: String) -> IntegrationCredential? {
        if let credential = secrets.credential(for: serviceID) {
            return credential
        }
        // 迁移后的旧令牌（幕间、ntfy）仍是这两个应用的唯一凭据来源。
        guard let key = Self.legacyKey(for: serviceID) else { return nil }
        let token = secrets.value(for: key)
        return token.isEmpty ? nil : IntegrationCredential(token: token)
    }

    private static func legacyKey(for serviceID: String) -> SecretStore.LegacyKey? {
        switch serviceID {
        case "mujian": .mujian
        case "ntfy": .ntfy
        default: nil
        }
    }

    func preference(for serviceID: String) -> IntegrationPreference {
        preferences.preference(for: serviceID)
    }

    func updatePreference(_ serviceID: String, _ transform: (inout IntegrationPreference) -> Void) {
        preferences.update(serviceID, transform)
        IntegrationPreferencesStore.save(preferences)
        reminderRevision += 1
    }

    /// 一次成功的业务请求本身就是凭据可用的证据；用于可选令牌应用
    /// 在没有单独跑验证时也能把状态从“未配置/待验证”纠正过来。
    func markValid(serviceID: String) {
        guard IntegrationCatalog.definition(for: serviceID)?.authKind != IntegrationDefinition.AuthKind.none else {
            return
        }
        states[serviceID] = .valid(.now)
        lastErrors[serviceID] = nil
        updatePreference(serviceID) { $0.lastValidatedAt = .now }
    }

    func reportError(_ error: any Error, for serviceID: String) {
        let apiError = error as? IntegrationAPIError ?? .transport(error.localizedDescription)
        lastErrors[serviceID] = apiError.userMessage
        if apiError.needsReauthorization {
            states[serviceID] = .expired(apiError.userMessage)
            updatePreference(serviceID) { $0.lastAuthFailure = apiError.userMessage }
        }
    }

    func clearError(for serviceID: String) {
        lastErrors[serviceID] = nil
    }

    // MARK: - 保存并验证

    /// 先验证后落库：错误凭据不会覆盖已有的可用凭据。
    func saveAndValidate(
        serviceID: String,
        baseURL: URL,
        input: IntegrationCredentialInput
    ) async -> Bool {
        guard let definition = IntegrationCatalog.definition(for: serviceID) else {
            lastErrors[serviceID] = "未知的应用"
            return false
        }

        states[serviceID] = .checking
        let candidate = mergedCredential(serviceID: serviceID, input: input)

        if definition.authKind == .login || definition.authKind == .sessionCookie {
            guard let username = candidate.username, !username.isEmpty,
                  let password = candidate.password, !password.isEmpty else {
                states[serviceID] = .invalid("请填写账号和密码")
                lastErrors[serviceID] = "请填写账号和密码"
                return false
            }
        }

        do {
            let validated = try await IntegrationValidators.validate(
                definition: definition,
                baseURL: baseURL,
                credential: candidate
            )
            if definition.authKind == .none {
                try? secrets.removeCredential(for: serviceID)
            } else if let legacy = Self.legacyKey(for: serviceID) {
                try secrets.setValue(validated.bearer, for: legacy)
                try? secrets.removeCredential(for: serviceID)
            } else {
                try secrets.save(validated, for: serviceID)
            }
            states[serviceID] = definition.authKind == .none ? .noAuth : .valid(.now)
            lastErrors[serviceID] = nil
            updatePreference(serviceID) {
                $0.lastValidatedAt = .now
                $0.credentialExpiresAt = validated.expiresAt
                $0.lastAuthFailure = nil
            }
            return true
        } catch {
            handleValidationFailure(error, serviceID: serviceID, definition: definition)
            return false
        }
    }

    /// 冷启动/进入设置时静默验证，不弹任何输入。
    func validateIfConfigured(serviceID: String, baseURL: URL) async {
        guard let definition = IntegrationCatalog.definition(for: serviceID) else { return }
        let credential = secrets.credential(for: serviceID) ?? IntegrationCredential()

        if definition.authKind.needsCredential,
           credential.isEmpty,
           !definition.credentialOptional {
            states[serviceID] = .unconfigured
            return
        }

        let previous = states[serviceID]
        states[serviceID] = .checking
        do {
            let validated = try await IntegrationValidators.validate(
                definition: definition,
                baseURL: baseURL,
                credential: credential
            )
            if definition.authKind == .none {
                states[serviceID] = .noAuth
            } else {
                if !validated.isEmpty || validated.username != nil {
                    if let legacy = Self.legacyKey(for: serviceID) {
                        try? secrets.setValue(validated.bearer, for: legacy)
                        try? secrets.removeCredential(for: serviceID)
                    } else {
                        try? secrets.save(validated, for: serviceID)
                    }
                }
                states[serviceID] = .valid(.now)
            }
            lastErrors[serviceID] = nil
            updatePreference(serviceID) {
                $0.lastValidatedAt = .now
                $0.credentialExpiresAt = validated.expiresAt
                $0.lastAuthFailure = nil
            }
        } catch {
            let apiError = error as? IntegrationAPIError ?? .transport(error.localizedDescription)
            if case .unauthorized = apiError,
               definition.credentialOptional,
               credential.isEmpty {
                states[serviceID] = .unconfigured
                lastErrors[serviceID] = "需要访问令牌"
                return
            }
            if apiError.needsReauthorization {
                states[serviceID] = .expired(apiError.userMessage)
                updatePreference(serviceID) { $0.lastAuthFailure = apiError.userMessage }
            } else if let previous, case .valid = previous {
                // 网络抖动不该把“已连接”打回未配置；只记错误。
                states[serviceID] = previous
            } else {
                states[serviceID] = .invalid(apiError.userMessage)
            }
            lastErrors[serviceID] = apiError.userMessage
        }
    }

    private func mergedCredential(
        serviceID: String,
        input: IntegrationCredentialInput
    ) -> IntegrationCredential {
        var candidate = credential(for: serviceID) ?? IntegrationCredential()
        if let token = input.token {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            candidate.token = trimmed.isEmpty ? nil : trimmed
        }
        if let username = input.username {
            let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { candidate.username = trimmed }
        }
        if let password = input.password, !password.isEmpty {
            candidate.password = password
        }
        candidate.updatedAt = .now
        return candidate
    }

    private func handleValidationFailure(
        _ error: any Error,
        serviceID: String,
        definition: IntegrationDefinition
    ) {
        let apiError = error as? IntegrationAPIError ?? .transport(error.localizedDescription)
        if apiError.needsReauthorization {
            states[serviceID] = .expired(apiError.userMessage)
            updatePreference(serviceID) { $0.lastAuthFailure = apiError.userMessage }
        } else if case .unauthorized = apiError,
                  definition.credentialOptional {
            states[serviceID] = .unconfigured
        } else {
            states[serviceID] = .invalid(apiError.userMessage)
        }
        lastErrors[serviceID] = apiError.userMessage
    }

    // MARK: - 清除

    func clearCredential(for serviceID: String) {
        do {
            if let legacy = Self.legacyKey(for: serviceID) {
                try secrets.setValue("", for: legacy)
            }
            try secrets.removeCredential(for: serviceID)
            states[serviceID] = IntegrationCatalog.definition(for: serviceID)?.authKind == IntegrationDefinition.AuthKind.none
                ? .noAuth : .unconfigured
            lastErrors[serviceID] = nil
            reminderCounts[serviceID] = 0
            updatePreference(serviceID) {
                $0.lastValidatedAt = nil
                $0.credentialExpiresAt = nil
                $0.lastAuthFailure = nil
            }
            Task { await scheduler.cancel(serviceID: serviceID) }
        } catch {
            lastErrors[serviceID] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - 提醒

    @MainActor
    func registerReminderCategory() {
        scheduler.registerCategory()
    }

    func syncReminders(serviceID: String, plans: [PlannedReminder]) async {
        let preference = preference(for: serviceID)
        await scheduler.sync(
            serviceID: serviceID,
            reminders: plans,
            enabled: preference.remindersEnabled
        )
        let counts = await scheduler.pendingCounts()
        reminderCounts[serviceID] = counts[serviceID] ?? 0
    }

    func refreshReminderCounts() async {
        reminderCounts = await scheduler.pendingCounts()
    }

    func cancelReminders(serviceID: String) async {
        await scheduler.cancel(serviceID: serviceID)
        reminderCounts[serviceID] = 0
    }

    func pendingReminderIdentifiers() async -> [String] {
        await scheduler.pendingIdentifiers()
    }
}
