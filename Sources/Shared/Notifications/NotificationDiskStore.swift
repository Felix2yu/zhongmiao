import Foundation
import ZhongmiaoCore

/// 收件箱快照（跨 actor 传递用的值类型）。
struct NotificationSnapshot: Sendable, Equatable {
    var items: [NotificationItem] = []
    var unreadCount: Int = 0
    var pendingCount: Int = 0
    var lastSyncAt: Date?
    var isSyncing = false

    static let empty = NotificationSnapshot()

    static func make(from ledger: NotificationLedger, lastSyncAt: Date?, isSyncing: Bool = false) -> NotificationSnapshot {
        NotificationSnapshot(
            items: ledger.items,
            unreadCount: ledger.unreadCount,
            pendingCount: ledger.pendingDelivery.count,
            lastSyncAt: lastSyncAt,
            isSyncing: isSyncing
        )
    }
}

/// 账本落盘。
///
/// 选 JSON 而不是数据库：数据量上限 500 条、结构简单，透明可审计，
/// 出现问题时可以直接用文本编辑器查看/修复。
struct NotificationDiskStore: Sendable {
    let fileURL: URL

    static func standard() -> NotificationDiskStore {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        let directory = base.appendingPathComponent("Zhongmiao", isDirectory: true)
        if !manager.fileExists(atPath: directory.path) {
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return NotificationDiskStore(fileURL: directory.appendingPathComponent("ledger.json"))
    }

    func load() -> NotificationLedger {
        guard let data = try? Data(contentsOf: fileURL) else { return NotificationLedger() }
        do {
            return try JSONDecoder().decode(NotificationLedger.self, from: data)
        } catch {
            // 损坏时保留现场，避免用户数据被静默覆盖。
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("ledger.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return NotificationLedger()
        }
    }

    func save(_ ledger: NotificationLedger) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(ledger) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    var sizeDescription: String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let bytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
