import Foundation
import ZhongmiaoCore

/// 刷新结果。
struct ShowRefreshOutcome: Sendable {
    var library: ShowLibrary
    /// 幕间 API 的失败原因，成功时为 nil。
    var apiError: String?
    /// 系统日历的失败原因，成功时为 nil。
    var calendarError: String?
}

/// 演出缓存的持有者：落盘、合并、刷新。
///
/// 为什么缓存必须落盘而不是每次联网：开岛的触发点是快捷指令在后台拉起 App 进程，
/// 那一刻既不该等网络、也不该要求用户重新登录；只能读本地快照。
/// 刷新一律发生在前台（启动、下拉、设置改动）。
actor ShowStore {

    let fileURL: URL
    private var library: ShowLibrary

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.library = Self.decoded(at: fileURL) ?? .empty
    }

    static func standard() -> ShowStore {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        let directory = base.appendingPathComponent("Zhongmiao", isDirectory: true)
        if !manager.fileExists(atPath: directory.path) {
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return ShowStore(fileURL: directory.appendingPathComponent("shows.json"))
    }

    // MARK: - 读写

    func snapshot() -> ShowLibrary { library }

    func replace(_ library: ShowLibrary) {
        self.library = library
        persist(library)
    }

    /// 刷新缓存。
    ///
    /// 两个数据源彼此独立：幕间挂了不影响日历，反之亦然。任一失败都保留旧缓存——
    /// 一次网络抖动不该清空用户已经排好的提醒。
    @discardableResult
    func refresh(settings: AppSettings) async -> ShowRefreshOutcome {
        guard settings.showsEnabled else {
            return ShowRefreshOutcome(library: library)
        }

        var working = library
        working.prune()

        var outcome = ShowRefreshOutcome(library: working)

        if settings.showsUseMujianAPI {
            do {
                let shows = try await fetchFromMujian(settings: settings)
                working.merge(shows)
                working.markFetched(.mujian)
            } catch {
                outcome.apiError = error.localizedDescription
            }
        }

        #if os(iOS)
        if settings.showsUseCalendar {
            do {
                let shows = try await CalendarShowSource.fetchUpcoming(
                    days: Self.lookaheadDays,
                    keywords: settings.showsCalendarKeywordList
                )
                working.merge(shows)
                working.markFetched(.calendar)
            } catch {
                outcome.calendarError = error.localizedDescription
            }
        }
        #endif

        library = working
        persist(working)
        outcome.library = working
        return outcome
    }

    // MARK: - 幕间

    /// 向前看多少天。与缓存保留期无关，只影响一次拉多少数据。
    static let lookaheadDays = 14

    private func fetchFromMujian(settings: AppSettings) async throws -> [Show] {
        guard let service = ServiceCatalog.service(id: "mujian") else {
            throw ShowClient.Failure(status: 0)
        }
        let preference = settings.preference(for: service)
        guard let baseURL = ServiceURLResolver.url(
            for: service,
            settings: settings.addressing,
            override: preference.urlOverride
        ) else {
            throw URLError(.badURL)
        }
        let client = ShowClient(days: Self.lookaheadDays)
        return try await client.fetchUpcoming(baseURL: baseURL, token: settings.mujianToken)
    }

    // MARK: - 落盘

    private static func decoded(at url: URL) -> ShowLibrary? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(ShowLibrary.self, from: data)
        } catch {
            // 损坏时保留现场：直接覆盖会让用户失去排查线索。
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("shows.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            return nil
        }
    }

    private func persist(_ library: ShowLibrary) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(library) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
