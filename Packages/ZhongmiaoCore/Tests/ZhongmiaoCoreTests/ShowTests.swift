import Foundation
import Testing

@testable import ZhongmiaoCore

// MARK: - 辅助

private func makeShow(
    startsIn seconds: TimeInterval,
    duration: TimeInterval? = 3 * 3600,
    now: Date = Date()
) -> Show {
    Show(
        id: "rec_1",
        name: "牡丹亭",
        venue: "长安大戏院",
        seat: "1 排 2 座",
        startsAt: now.addingTimeInterval(seconds),
        endsAt: duration.map { now.addingTimeInterval(seconds + $0) },
        source: .mujian
    )
}

// MARK: - 阶段判定

@Test("开演前是未开演，开演后到散场前是演出中，散场后是已结束")
func phaseTransitions() {
    let now = Date()
    #expect(makeShow(startsIn: 3600, now: now).phase(now: now) == .scheduled)
    #expect(makeShow(startsIn: -1800, now: now).phase(now: now) == .ongoing)
    #expect(makeShow(startsIn: -4 * 3600, now: now).phase(now: now) == .ended)
}

@Test("时长未知时按兜底时长收尾，不会永远停在演出中")
func phaseFallbackWhenDurationUnknown() {
    let now = Date()
    let show = makeShow(startsIn: -10 * 3600, duration: nil, now: now)
    #expect(show.phase(now: now) == .ended)
}

// MARK: - 开岛窗口

@Test("窗口上界贴着系统 8 小时限制")
func islandWindowUpperBound() {
    let now = Date()
    let lead = ShowReminder.defaultIslandLead
    // 恰好 8 小时：开。
    #expect(makeShow(startsIn: 8 * 3600, now: now).shouldStartIsland(now: now, lead: lead))
    // 超过上限一秒：不开，否则开了也会被系统提前砍掉。
    #expect(!makeShow(startsIn: 8 * 3600 + 1, now: now).shouldStartIsland(now: now, lead: lead))
}

@Test("提前量被夹到 0..8 小时；负值是「不早于开演」而不是反向推开窗口")
func islandLeadIsClamped() {
    let now = Date()
    #expect(ShowReminder.clampedIslandLead(-1) == 0)
    #expect(ShowReminder.clampedIslandLead(99 * 3600) == ShowReminder.islandMaxLead)

    let show = makeShow(startsIn: 3600, now: now)
    // 负数被夹成 0：开演前一小时不该开岛。
    #expect(!show.shouldStartIsland(now: now, lead: -7200))
    // 但开演之后就开了——窗口是 [开演 - 0, 散场)。
    #expect(show.shouldStartIsland(now: show.startsAt))
}

@Test("已结束的场次不开岛：打开 App 不该给三小时前的演出补一个岛")
func endedShowsDoNotStartIsland() {
    let now = Date()
    let show = makeShow(startsIn: -5 * 3600, now: now)
    #expect(show.phase(now: now) == .ended)
    #expect(!show.shouldStartIsland(now: now))
}

@Test("演出进行中仍可开岛")
func ongoingShowsStartIsland() {
    let now = Date()
    #expect(makeShow(startsIn: -1800, now: now).shouldStartIsland(now: now))
}

// MARK: - 收起时刻

@Test("散场后 30 分钟收起；时长未知时按开演 +3 小时 +30 分钟")
func islandDismissAt() {
    let now = Date()
    let known = makeShow(startsIn: 0, duration: 2 * 3600, now: now)
    #expect(known.islandDismissAt == now.addingTimeInterval(2 * 3600 + 30 * 60))

    let unknown = makeShow(startsIn: 0, duration: nil, now: now)
    #expect(unknown.islandDismissAt == now.addingTimeInterval(3 * 3600 + 30 * 60))
}

// MARK: - 提醒时刻

@Test("提醒落在开演前 lead，且不为已经过去的时刻排提醒")
func reminderDate() {
    let now = Date()
    let future = makeShow(startsIn: 5 * 3600, now: now)
    #expect(future.reminderDate(lead: 3 * 3600, now: now) == now.addingTimeInterval(2 * 3600))

    let imminent = makeShow(startsIn: 600, now: now)
    #expect(imminent.reminderDate(lead: 3 * 3600, now: now) == nil)
}

// MARK: - 幕间 DTO

@Test("字段残缺不能让整份响应解码失败")
func decodesPartialPayload() throws {
    let json = Data(#"{"items":[{"id":"a1","name":"锁麟囊","date":1800000000}]}"#.utf8)
    let response = try JSONDecoder().decode(MujianUpcomingResponse.self, from: json)
    #expect(response.items.count == 1)

    let show = try #require(response.items[0].makeShow())
    #expect(show.id == "a1")
    #expect(show.endsAt == nil)
    #expect(show.venue == nil)
}

@Test("缺 items 时退化为空数组")
func decodesMissingItems() throws {
    let json = Data(#"{"days":14}"#.utf8)
    let response = try JSONDecoder().decode(MujianUpcomingResponse.self, from: json)
    #expect(response.items.isEmpty)
    #expect(response.days == 14)
}

@Test("缺 id / 剧名 / 开演时间的条目被丢弃")
func dropsUnusableRecords() throws {
    let json = Data(
        #"{"items":[{"name":"没有 id"},{"id":"b2","date":1800000000},{"id":"b3","name":"没有时间"}]}"#
            .utf8
    )
    let response = try JSONDecoder().decode(MujianUpcomingResponse.self, from: json)
    #expect(response.items.count == 3)
    #expect(response.items.compactMap { $0.makeShow() }.isEmpty)
}

@Test("duration 为 0 视为未知，不生成散场时间")
func zeroDurationMeansUnknown() throws {
    let json = Data(#"{"items":[{"id":"c1","name":"春草闯堂","date":1800000000,"duration":0}]}"#.utf8)
    let response = try JSONDecoder().decode(MujianUpcomingResponse.self, from: json)
    let show = try #require(response.items[0].makeShow())
    #expect(show.endsAt == nil)
    #expect(show.startsAt == Date(timeIntervalSince1970: 1_800_000_000))
}

@Test("有 baseURL 时拼出详情页深链")
func buildsDetailURL() throws {
    let json = Data(#"{"items":[{"id":"d1","name":"白蛇传","date":1800000000}]}"#.utf8)
    let response = try JSONDecoder().decode(MujianUpcomingResponse.self, from: json)
    let base = URL(string: "https://mujian.example.com")!
    let show = try #require(response.items[0].makeShow(baseURL: base))
    #expect(show.url?.absoluteString == "https://mujian.example.com/records/d1")
}

@Test("artist_names 走下划线键名")
func decodesSnakeCaseArtists() throws {
    let json = Data(#"{"items":[{"id":"e1","name":"四郎探母","date":1800000000,"artist_names":["甲","乙"]}]}"#.utf8)
    let response = try JSONDecoder().decode(MujianUpcomingResponse.self, from: json)
    #expect(response.items[0].artistNames == ["甲", "乙"])
}
