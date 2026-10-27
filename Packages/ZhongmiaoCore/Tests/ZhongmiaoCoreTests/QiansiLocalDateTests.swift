import Foundation
import Testing

@testable import ZhongmiaoCore

@Suite("牵丝本地墙钟时间")
struct QiansiLocalDateTests {

    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    private func components(_ date: Date, timeZone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }

    @Test("三种业务时间格式都能解析")
    func parsesBusinessFormats() throws {
        let full = try #require(QiansiLocalDate.parse("2026-11-01T09:30:15", timeZone: shanghai))
        let short = try #require(QiansiLocalDate.parse("2026-11-01T09:30", timeZone: shanghai))
        let day = try #require(QiansiLocalDate.parse("2026-11-01", timeZone: shanghai))

        #expect(components(full, timeZone: shanghai).hour == 9)
        #expect(components(full, timeZone: shanghai).minute == 30)
        #expect(components(short, timeZone: shanghai).second == 0)
        #expect(components(day, timeZone: shanghai).hour == 0)
        #expect(QiansiLocalDate.daysUntil(day, now: full, timeZone: shanghai) == 0)
    }

    @Test("非法与空字符串返回 nil")
    func rejectsInvalid() {
        #expect(QiansiLocalDate.parse("", timeZone: shanghai) == nil)
        #expect(QiansiLocalDate.parse("2026/11/01", timeZone: shanghai) == nil)
        #expect(QiansiLocalDate.parse("not-a-date", timeZone: shanghai) == nil)
    }

    @Test("跨时区解析得到同一墙钟")
    func respectsTimeZone() throws {
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        let shanghaiDate = try #require(QiansiLocalDate.parse("2026-11-01T09:00:00", timeZone: shanghai))
        let laDate = try #require(QiansiLocalDate.parse("2026-11-01T09:00:00", timeZone: losAngeles))
        #expect(shanghaiDate != laDate)
        #expect(components(shanghaiDate, timeZone: shanghai).hour == 9)
        #expect(components(laDate, timeZone: losAngeles).hour == 9)
    }

    @Test("夏令时当天的 09:00 仍是 09:00")
    func daylightSaving() throws {
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        let date = try #require(QiansiLocalDate.parse("2026-03-08T09:00:00", timeZone: losAngeles))
        #expect(components(date, timeZone: losAngeles).hour == 9)
    }

    @Test("daysUntil 按日历日计算")
    func daysUntil() throws {
        let now = try #require(QiansiLocalDate.parse("2026-10-30T23:00:00", timeZone: shanghai))
        let target = try #require(QiansiLocalDate.parse("2026-11-02T00:30:00", timeZone: shanghai))
        #expect(QiansiLocalDate.daysUntil(target, now: now, timeZone: shanghai) == 3)
    }

    @Test("把日期替换成全局提醒时刻")
    func replacesClock() throws {
        let day = try #require(QiansiLocalDate.parse("2026-11-01", timeZone: shanghai))
        let at9 = try #require(QiansiLocalDate.date(on: day, hour: 9, minute: 15, timeZone: shanghai))
        let comps = components(at9, timeZone: shanghai)
        #expect(comps.day == 1)
        #expect(comps.hour == 9)
        #expect(comps.minute == 15)
    }
}
