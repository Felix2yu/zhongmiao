import Foundation
import ZhongmiaoCore

/// 一次同步要处理的目标（由主线程根据设置组装，交给 actor 执行）。
struct SyncTarget: Sendable, Hashable {
    var serviceID: String
    var serviceName: String
    var baseURL: URL
    var feedPath: String?
    var ntfyTopic: String?
    var ntfyBaseURL: URL?
    /// ntfy 访问令牌（服务端开了访问控制时必需）。
    var ntfyToken: String
    var relayURL: URL?
    var relaySecret: String
}

struct SyncReport: Sendable {
    var isOnline = true
    var fetched = 0
    var inserted = 0
    var delivered = 0
    /// 服务端广播的「已读」事件落到本地的条数。
    var readSynced = 0
    var failures: [String: String] = [:]
    var skippedForPermission = false
    var finishedAt = Date()

    var failureSummary: String? {
        guard !failures.isEmpty else { return nil }
        return failures.map { "\($0.key)：\($0.value)" }.joined(separator: "；")
    }

    var summaryText: String {
        if !isOnline {
            let pending = inserted > 0 ? "" : "（离线，\(delivered) 条已投递）"
            return "当前离线，恢复网络后自动补发\(pending)"
        }
        if fetched == 0 && inserted == 0 && delivered == 0 && readSynced == 0 && failures.isEmpty {
            return "已同步，没有新通知"
        }
        var parts: [String] = []
        if inserted > 0 { parts.append("新增 \(inserted) 条") }
        if delivered > 0 { parts.append("投递 \(delivered) 条") }
        if readSynced > 0 { parts.append("已读同步 \(readSynced) 条") }
        if let failureSummary { parts.append("失败：\(failureSummary)") }
        if skippedForPermission { parts.append("未授权通知，已暂存") }
        return parts.isEmpty ? "已同步" : parts.joined(separator: " · ")
    }
}

/// 通知引擎：拉取、去重、入库、投递、补发都收敛在这里。
///
/// 所有可变状态都在 actor 内，磁盘写入串行进行，避免并发同步把账本写乱。
actor NotificationEngine {

    private let store: NotificationDiskStore
    private let scheduler: NotificationScheduler
    private let feeds: FeedClients
    private var ledger: NotificationLedger
    private(set) var lastSyncAt: Date?

    init(
        store: NotificationDiskStore = .standard(),
        scheduler: NotificationScheduler,
        feeds: FeedClients = FeedClients(),
        capacity: Int = 500
    ) {
        self.store = store
        self.scheduler = scheduler
        self.feeds = feeds
        var loaded = store.load()
        loaded.capacity = max(50, capacity)
        self.ledger = loaded
        self.lastSyncAt = nil
    }

    // MARK: - 读取

    func snapshot(isSyncing: Bool = false) -> NotificationSnapshot {
        .make(from: ledger, lastSyncAt: lastSyncAt, isSyncing: isSyncing)
    }

    func pendingCount() -> Int {
        ledger.pendingDelivery.count
    }

    func storageDescription() -> String {
        store.sizeDescription
    }

    func setCapacity(_ capacity: Int) {
        ledger.capacity = max(50, capacity)
        store.save(ledger)
    }

    // MARK: - 同步

    func sync(targets: [SyncTarget], isOnline: Bool, lookbackHours: Int) async -> (report: SyncReport, snapshot: NotificationSnapshot) {
        var report = SyncReport()
        report.isOnline = isOnline

        var names: [String: String] = [:]
        for target in targets { names[target.serviceID] = target.serviceName }

        let lookback = TimeInterval(max(1, lookbackHours)) * 3600
        let now = Date()

        if isOnline {
            for target in targets {
                // 1) 应用自带的 JSON 通知流
                if let path = target.feedPath, !path.isEmpty {
                    let key = "\(target.serviceID)|feed"
                    do {
                        let since = ledger.fetchSince(serviceID: key, lookback: lookback)
                        let items = try await feeds.fetchFeed(
                            base: target.baseURL,
                            path: path,
                            serviceID: target.serviceID,
                            since: since
                        )
                        report.fetched += items.count
                        report.inserted += ledger.merge(items).inserted.count
                        advanceCursor(key: key, newestAt: items.map(\.createdAt).max(), since: since, now: now)
                    } catch {
                        report.failures["\(target.serviceName) 通知流"] = Self.describe(error)
                    }
                }

                // 2) ntfy 主题（poll 模式，天然支持断线补发）
                if let topic = target.ntfyTopic?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !topic.isEmpty,
                   let ntfyBase = target.ntfyBaseURL {
                    let key = "\(target.serviceID)|ntfy"
                    do {
                        let since = ledger.fetchSince(serviceID: key, lookback: lookback)
                        let result = try await feeds.fetchNtfy(
                            base: ntfyBase,
                            topic: topic,
                            serviceID: target.serviceID,
                            since: since,
                            token: target.ntfyToken
                        )
                        report.fetched += result.items.count
                        report.inserted += ledger.merge(result.items).inserted.count
                        // 服务端广播的「已读」：别处读过的消息，这里也标成已读。
                        report.readSynced += ledger.markRead(
                            ntfyTargets: result.clearedTargets,
                            serviceID: target.serviceID
                        )
                        advanceCursor(key: key, newestAt: result.newestAt, since: since, now: now)
                    } catch {
                        report.failures["\(target.serviceName) ntfy"] = Self.describe(error)
                    }
                }

                // 3) 推送中继历史（APNs 漏收的兜底）
                if let relay = target.relayURL {
                    let key = "\(target.serviceID)|relay"
                    do {
                        let since = ledger.fetchSince(serviceID: key, lookback: lookback)
                        let items = try await feeds.fetchRelayEvents(
                            relay: relay,
                            secret: target.relaySecret,
                            serviceID: target.serviceID,
                            since: since
                        )
                        report.fetched += items.count
                        report.inserted += ledger.merge(items).inserted.count
                        advanceCursor(key: key, newestAt: items.map(\.createdAt).max(), since: since, now: now)
                    } catch {
                        report.failures["\(target.serviceName) 中继"] = Self.describe(error)
                    }
                }
            }
        }

        let outcome = await deliverPendingInternal(serviceNames: names)
        report.delivered = outcome.delivered
        report.skippedForPermission = outcome.skippedForPermission
        if let failure = outcome.failureMessage {
            report.failures["本地通知"] = failure
        }

        lastSyncAt = Date()
        report.finishedAt = lastSyncAt ?? Date()
        store.save(ledger)
        await scheduler.setBadge(ledger.unreadCount)
        return (report, snapshot())
    }

    /// 只补发积压（不发起网络请求）。用于恢复前台、重连等场景。
    func flushPending(serviceNames: [String: String]) async -> Int {
        let outcome = await deliverPendingInternal(serviceNames: serviceNames)
        store.save(ledger)
        return outcome.delivered
    }

    private struct DeliveryOutcome {
        var delivered = 0
        var skippedForPermission = false
        var failureMessage: String?
    }

    private func deliverPendingInternal(serviceNames: [String: String]) async -> DeliveryOutcome {
        var outcome = DeliveryOutcome()
        let pending = ledger.pendingDelivery
        guard !pending.isEmpty else { return outcome }

        guard await scheduler.isDeliveryAllowed() else {
            // 没授权就保留在账本里，等用户开启后一次性补发，绝不丢。
            outcome.skippedForPermission = true
            return outcome
        }

        let result = await scheduler.deliver(pending, serviceNames: serviceNames)
        for id in result.deliveredIDs {
            ledger.markDelivered(id: id)
        }
        outcome.delivered = result.deliveredIDs.count
        if result.failed > 0 {
            outcome.failureMessage = "\(result.failed) 条投递失败"
        }
        return outcome
    }

    // MARK: - 页面内通知

    /// WebView 内 `new Notification()` / `showNotification()` 被桥接后进入这里。
    /// 与远端事件共用同一套去重键，重复点击不会重复弹窗。
    func ingest(_ item: NotificationItem, serviceName: String) async -> NotificationSnapshot {
        let result = ledger.merge([item])
        guard !result.inserted.isEmpty else { return snapshot() }

        if await scheduler.isDeliveryAllowed() {
            let outcome = await scheduler.deliver(result.inserted, serviceNames: [item.serviceID: serviceName])
            for id in outcome.deliveredIDs { ledger.markDelivered(id: id) }
        }
        store.save(ledger)
        await scheduler.setBadge(ledger.unreadCount)
        return snapshot()
    }

    // MARK: - 变更

    func markRead(id: String) async -> NotificationSnapshot {
        ledger.markRead(id: id)
        store.save(ledger)
        await scheduler.setBadge(ledger.unreadCount)
        return snapshot()
    }

    func markAllRead(serviceID: String?) async -> NotificationSnapshot {
        ledger.markAllRead(serviceID: serviceID)
        store.save(ledger)
        await scheduler.setBadge(0)
        return snapshot()
    }

    func remove(id: String) async -> NotificationSnapshot {
        ledger.remove(id: id)
        store.save(ledger)
        await scheduler.setBadge(ledger.unreadCount)
        return snapshot()
    }

    func clearInbox() async -> NotificationSnapshot {
        ledger.remove()
        store.save(ledger)
        await scheduler.clearDelivered()
        await scheduler.setBadge(0)
        return snapshot()
    }

    // MARK: - 内部

    /// 游标推进：取本批最新事件时间与请求起点中较大者，绝不超过当前时间。
    ///
    /// ntfy 通道传的是「本批消息（含动作事件）的最新时间」——只收到一条已读广播时，
    /// 游标同样要往前走，否则每次同步都会把同一条广播重复拉回来。
    private func advanceCursor(key: String, newestAt: Date?, since: Date, now: Date) {
        let candidate = min(max(newestAt ?? now, since.addingTimeInterval(1)), now)
        ledger.advanceCursor(serviceID: key, to: candidate)
    }

    private static func describe(_ error: any Error) -> String {
        if let failure = error as? FeedClients.HTTPFailure {
            return failure.description
        }
        if let urlError = error as? URLError {
            return HealthClassifier.classify(
                errorCode: urlError.errorCode,
                description: urlError.localizedDescription
            ).title
        }
        return error.localizedDescription
    }
}
