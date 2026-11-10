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
    /// 本次会话内已验证通过的凭据。持久化失败也不影响它。
    private var runtimeCredentials: [String: IntegrationCredential] = [:]
    let cache = IntegrationCache.shared

    private(set) var states: [String: CredentialState] = [:]
    private(set) var preferences: IntegrationPreferences
    private(set) var lastErrors: [String: String] = [:]
    private(set) var reminderCounts: [String: Int] = [:]
    /// 已写进系统日历与提醒事项的条数（iOS）。
    private(set) var systemReminderCounts: [String: Int] = [:]
    /// 系统写入的结果说明；成功时为 nil。
    private(set) var systemReminderNotes: [String: String] = [:]
    /// 提醒时刻/开关变更后 +1，打开中的原生页据此重排。
    private(set) var reminderRevision = 0

    private let scheduler = IntegrationReminderScheduler()
    /// 由 AppModel 注册：用持久化快照重建某服务的提醒计划，不依赖页面是否打开。
    private var reminderRebuilders: [String: @MainActor () async -> Void] = [:]

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
        // 运行时的凭据优先：登录型应用换来的会话 cookie / JWT 先落在这里。
        // 它不依赖持久化成功——钥匙串写不进去时（模拟器、权限受限），
        // 本次会话仍然要用这份凭据，否则会出现「明明登录成功了却读不到凭据」。
        if let runtime = runtimeCredentials[serviceID] { return runtime }
        if let credential = secrets.credential(for: serviceID) {
            return credential
        }
        // 迁移后的旧令牌（幕间、ntfy）仍是这两个应用的唯一凭据来源。
        guard let key = Self.legacyKey(for: serviceID) else { return nil }
        let token = secrets.value(for: key)
        return token.isEmpty ? nil : IntegrationCredential(token: token)
    }

    /// 记住一次验证通过的凭据，供本次会话使用。
    private func rememberRuntime(_ credential: IntegrationCredential, for serviceID: String) {
        runtimeCredentials[serviceID] = credential
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
        let previous = preference(for: serviceID)
        preferences.update(serviceID, transform)
        IntegrationPreferencesStore.save(preferences)
        let updated = preference(for: serviceID)

        // 关闭提醒必须立即撤销已排程的条目：用户可能在「设置」里直接关，
        // 此时没有原生页在场，不能等下次打开页面才生效。
        if previous.remindersEnabled && !updated.remindersEnabled {
            Task {
                await scheduler.cancel(serviceID: serviceID)
                reminderCounts[serviceID] = 0
            }
        }
        if previous.systemRemindersEnabled && !updated.systemRemindersEnabled {
            Task { await clearSystemReminders(serviceID: serviceID) }
        }

        // 开启或改时刻也要立即生效，而不是等用户再打开一次原生页。
        // 重建动作由 AppModel 注册：用持久化快照重新生成计划，不依赖页面生命周期。
        let reminderConfigurationChanged =
            previous.remindersEnabled != updated.remindersEnabled ||
            previous.reminderHour != updated.reminderHour ||
            previous.reminderMinute != updated.reminderMinute ||
            previous.eventLeadDays != updated.eventLeadDays ||
            previous.systemRemindersEnabled != updated.systemRemindersEnabled
        if reminderConfigurationChanged, updated.remindersEnabled || updated.systemRemindersEnabled {
            Task { await rebuildReminders(serviceID: serviceID) }
        }
        reminderRevision += 1
    }

    /// 注册某个服务的提醒重建动作。中心不持有页面模型，只用快照重新排程。
    func registerReminderRebuilder(serviceID: String, _ action: @escaping @MainActor () async -> Void) {
        reminderRebuilders[serviceID] = action
    }

    func rebuildReminders(serviceID: String) async {
        guard let action = reminderRebuilders[serviceID] else { return }
        await action()
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
                rememberRuntime(validated, for: serviceID)
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

    /// 状态已失效/未知，但钥匙串里还留着账号密码时，静默重登一次。
    /// 用途：页面先落地、登录后到导致首页 401（旧 JWT），不要把「还没登录」变成
    /// 「凭据已失效」让用户去重新授权。
    @discardableResult
    func reauthenticateIfPossible(serviceID: String, baseURL: URL) async -> Bool {
        guard let definition = IntegrationCatalog.definition(for: serviceID),
              definition.authKind == .login || definition.authKind == .sessionCookie else { return false }
        guard let credential = secrets.credential(for: serviceID),
              !(credential.username ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
              !(credential.password ?? "").isEmpty else { return false }
        await validateIfConfigured(serviceID: serviceID, baseURL: baseURL)
        return state(for: serviceID).isUsable
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
                        // 先记住再落盘：落盘失败也不该让本次会话失去凭据。
                        rememberRuntime(validated, for: serviceID)
                        do {
                            try secrets.save(validated, for: serviceID)
                        } catch {
                            // 内存里已经是新凭据（SecretStore 会兜底），但没持久化成功，
                            // 记一笔，别再像以前一样 try? 吞掉。
                            NSLog("[ZMIntegration] 保存 %@ 凭据到钥匙串失败：%@", serviceID, error.localizedDescription)
                        }
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
            Task { await clearSystemReminders(serviceID: serviceID) }
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
        await syncSystemReminders(
            serviceID: serviceID,
            plans: plans,
            enabled: preference.systemRemindersEnabled
        )
    }

    /// 把同一批计划写进系统日历与提醒事项。
    ///
    /// 与本地通知共用一份计划，目的却不同：本地通知负责近期、受 64 条预算约束；
    /// 系统条目由系统持有——App 被杀、描述文件过期都照旧到点，且不占通知预算，
    /// 适合生日、纪念日这类远期项。macOS 暂不写入。
    func syncSystemReminders(serviceID: String, plans: [PlannedReminder], enabled: Bool) async {
        #if os(iOS)
        // 默认关闭时绝不碰 EventKit：连 requestFullAccess 都不调用，避免新装设备
        // 在用户没打开开关的情况下被要日历/提醒事项权限。
        guard enabled else { return }
        let anchors = plans.compactMap { SystemAnchor(reminder: $0) }
        guard !anchors.isEmpty else {
            systemReminderCounts[serviceID] = 0
            systemReminderNotes[serviceID] = nil
            return
        }
        let planned = SystemAnchorBudget.apply(to: anchors)
        let outcome = await SystemCalendarWriter.sync(
            serviceID: serviceID,
            anchors: planned
        )
        systemReminderCounts[serviceID] = planned.count
        systemReminderNotes[serviceID] = outcome.message
        #endif
    }

    /// 关闭开关或清凭据时的独立清理入口。
    ///
    /// 不主动申请权限：只有系统已经授予完全访问、且存在「众妙」专用列表时才删除，
    /// 这样默认关闭的用户永远不会看到授权弹窗。macOS 不写入，因此无需清理。
    func clearSystemReminders(serviceID: String) async {
        #if os(iOS)
        let outcome = await SystemCalendarWriter.clear(serviceID: serviceID)
        systemReminderCounts[serviceID] = 0
        systemReminderNotes[serviceID] = (outcome.removed > 0 || outcome.failed > 0)
            ? outcome.summary
            : nil
        #endif
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
