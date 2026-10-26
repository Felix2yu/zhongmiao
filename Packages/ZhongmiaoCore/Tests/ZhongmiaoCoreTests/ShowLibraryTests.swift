import Foundation
import Testing

@testable import ZhongmiaoCore

@Suite("演出缓存")
struct ShowLibraryTests {

    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func make(
        id: String,
        name: String = "悲惨世界",
        startsIn: TimeInterval,
        duration: TimeInterval? = 180 * 60,
        seat: String? = nil,
        source: Show.Source = .mujian
    ) -> Show {
        Show(
            id: id,
            name: name,
            venue: "上海大剧院",
            seat: seat,
            startsAt: now.addingTimeInterval(startsIn),
            endsAt: duration.map { now.addingTimeInterval(startsIn + $0) },
            source: source
        )
    }

    // MARK: - 身份归一

    @Test("幕间记录 id 与它同步进日历的 UID 归一到同一个键")
    func identityBridgesSources() {
        let fromAPI = make(id: "rec-1", startsIn: 3600, source: .mujian)
        let fromCalendar = make(id: "rec-1@mujian", startsIn: 3600, source: .calendar)
        #expect(fromAPI.identity == fromCalendar.identity)
        #expect(fromAPI.identity == "mujian:rec-1")
    }

    @Test("用户在日历里自建的事件不会被误并到幕间记录上")
    func foreignCalendarEventKeepsOwnNamespace() {
        let event = make(id: "abc-123", startsIn: 3600, source: .calendar)
        #expect(event.identity == "calendar:abc-123")
    }

    @Test("同名且开演时间相近视为同一场——EKEvent 拿不到 ICS 的 UID，只能模糊兜底")
    func fuzzyMatchMergesSameShow() {
        let api = make(id: "rec-9", startsIn: 3600, source: .mujian)
        let calendar = make(id: "cal-xyz", startsIn: 3660, source: .calendar)
        #expect(api.isSameShow(as: calendar))
    }

    @Test("同名但差 40 分钟是两场")
    func fuzzyMatchRespectsTimeWindow() {
        let first = make(id: "rec-9", startsIn: 3600)
        let second = make(id: "rec-10", startsIn: 6000)
        #expect(!first.isSameShow(as: second))
    }

    // MARK: - 合并

    @Test("两个数据源描述同一场演出时只留一条")
    func mergeDeduplicatesAcrossSources() {
        var library = ShowLibrary(items: [make(id: "rec-1", startsIn: 3600, source: .mujian)])
        let added = library.merge([make(id: "rec-1@mujian", startsIn: 3600, source: .calendar)])
        #expect(added == 0)
        #expect(library.items.count == 1)
    }

    @Test("合并时以幕间 API 为准，但不会用 nil 覆盖对方已有的字段")
    func mergePrefersAPIData() {
        let fromCalendar = make(id: "rec-1@mujian", startsIn: 3600, source: .calendar)
        let fromAPI = make(id: "rec-1", startsIn: 3600, seat: "3排12座", source: .mujian)

        var library = ShowLibrary(items: [fromCalendar])
        library.merge([fromAPI])

        let merged = library.items[0]
        #expect(merged.source == .mujian)
        #expect(merged.seat == "3排12座")
        #expect(merged.venue == "上海大剧院")
    }

    @Test("合并后按开演时间升序")
    func mergeSortsByStart() {
        var library = ShowLibrary()
        library.merge([
            make(id: "b", name: "夜场", startsIn: 9 * 3600),
            make(id: "a", name: "午场", startsIn: 3 * 3600)
        ])
        #expect(library.items.map(\.name) == ["午场", "夜场"])
    }

    // MARK: - 查询

    @Test("窗口里同时有午场与夜场时，选最近开演的那一场")
    func islandPicksNearestShow() {
        var library = ShowLibrary()
        library.merge([
            make(id: "matinee", name: "午场", startsIn: 3 * 3600),
            make(id: "evening", name: "夜场", startsIn: 7 * 3600)
        ])

        // 两场都落在 8 小时窗口内，必须挑 3 小时后那场，否则岛会挂着错的剧名。
        let picked = library.showForIsland(now: now)
        #expect(picked?.name == "午场")
    }

    @Test("已散场的演出不会被选中开岛")
    func endedShowIsNeverPicked() {
        let past = Show(
            id: "old",
            name: "昨夜场",
            startsAt: now.addingTimeInterval(-6 * 3600),
            endsAt: now.addingTimeInterval(-3 * 3600),
            source: .mujian
        )
        let library = ShowLibrary(items: [past])
        #expect(library.showForIsland(now: now) == nil)
        #expect(library.next(now: now) == nil)
    }

    @Test("recently 开演的场次仍然留在库里，但不再是 next")
    func ongoingShowIsUpcomingButNotNext() {
        let ongoing = Show(
            id: "live",
            name: "进行中",
            startsAt: now.addingTimeInterval(-3600),
            endsAt: now.addingTimeInterval(3600),
            source: .mujian
        )
        let library = ShowLibrary(items: [ongoing])
        #expect(library.upcoming(now: now).count == 1)
        #expect(library.next(now: now) == nil)
        #expect(library.showForIsland(now: now)?.id == "live")
    }

    // MARK: - 清理与兼容

    @Test("散场超过保留期的场次被清掉")
    func pruneRemovesStaleShows() {
        let stale = Show(
            id: "stale",
            name: "上月场",
            startsAt: now.addingTimeInterval(-10 * 86_400),
            endsAt: now.addingTimeInterval(-10 * 86_400 + 7200),
            source: .mujian
        )
        var library = ShowLibrary(items: [stale, make(id: "soon", startsIn: 3600)])
        library.prune(now: now)
        #expect(library.items.map(\.id) == ["soon"])
    }

    @Test("缺少新增字段的旧缓存仍能解出来")
    func legacyCacheDecodes() throws {
        let data = try #require("{\"items\":[]}".data(using: .utf8))
        let library = try JSONDecoder().decode(ShowLibrary.self, from: data)
        #expect(library.items.isEmpty)
        #expect(library.lastAPIFetchAt == nil)
        #expect(library.lastCalendarFetchAt == nil)
    }
}
