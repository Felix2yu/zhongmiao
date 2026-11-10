import SwiftUI
import ZhongmiaoCore

/// 首页「今日概览」里的一条：某个应用里今天或近期需要注意的事。
struct HomeDigestItem: Identifiable, Hashable {

    var id: String
    var serviceID: String
    var title: String
    var subtitle: String
    var symbol: String
    var date: Date
    /// 点进来时直达原生页里的这一条；页面不支持定位时为 nil。
    var target: NativeTarget?
}

/// 跨应用搜索命中：优先带目标，落到那一条；否则落在应用首页。
struct HomeSearchHit: Identifiable, Hashable {

    var id: String
    var serviceID: String
    var title: String
    var subtitle: String
    var target: NativeTarget?
}

/// 首页聚合的数据来源。
///
/// 只读各应用的本地快照，不发网络请求：首页是入口，不该因为某个服务不可达
/// 就整屏转圈。缓存越新，这里越准；页面内的刷新仍由各应用自己负责。
@MainActor
enum HomeAggregator {

    /// 今日概览。范围是逾期、今天与明天，按时间升序，最多 8 条。
    static func digest(
        center: IntegrationCenter,
        now: Date = .now,
        limit: Int = 8
    ) async -> [HomeDigestItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let horizon = calendar.date(byAdding: .day, value: 2, to: today) else { return [] }
        var items: [HomeDigestItem] = []

        if let cached = await center.cache.load(QingyeSnapshot.self, serviceID: "qingye") {
            for task in cached.payload.tasks where task.active {
                guard task.nextDue < horizon else { continue }
                let plant = task.plant?.name ?? "植物"
                items.append(
                    HomeDigestItem(
                        id: "qingye.task.\(task.id)",
                        serviceID: "qingye",
                        title: task.title,
                        subtitle: "\(plant) · \(dayLabel(task.nextDue, today: today))",
                        symbol: "leaf.fill",
                        date: task.nextDue,
                        target: NativeTarget(
                            kind: "care",
                            identifier: QiansiLocalDate.dayString(task.nextDue)
                        )
                    )
                )
            }
        }

        if let cached = await center.cache.load(QiansiSnapshot.self, serviceID: "qiansi") {
            let snapshot = cached.payload
            for anniversary in snapshot.anniversaries {
                let raw = anniversary.nextDate ?? anniversary.date
                guard let date = QiansiLocalDate.parse(raw) else { continue }
                let days = anniversary.daysUntil ?? QiansiLocalDate.daysUntil(date)
                guard days <= 1 else { continue }
                items.append(
                    HomeDigestItem(
                        id: "qiansi.anniversary.\(anniversary.id)",
                        serviceID: "qiansi",
                        title: anniversary.title,
                        subtitle: "生日/纪念日 · \(dayLabel(date, today: today))",
                        symbol: "birthday.cake.fill",
                        date: date,
                        target: NativeTarget(kind: "anniversary", identifier: anniversary.id)
                    )
                )
            }
            for event in snapshot.events {
                guard let date = QiansiLocalDate.parse(event.eventDate),
                      date >= today, date < horizon else { continue }
                let place = (event.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                items.append(
                    HomeDigestItem(
                        id: "qiansi.event.\(event.id)",
                        serviceID: "qiansi",
                        title: event.title,
                        subtitle: place.isEmpty ? "约会 · \(dayLabel(date, today: today))" : "约会 · \(place)",
                        symbol: "calendar",
                        date: date,
                        target: NativeTarget(kind: "event", identifier: event.id)
                    )
                )
            }
            for reminder in snapshot.reminders where reminder.status != "done" {
                // 生日/纪念日的派生提醒由纪念日本身表达，避免首页出现两条。
                if reminder.refType == "anniversary" || reminder.refType == "birthday" { continue }
                guard let date = QiansiLocalDate.parse(reminder.dueAt), date < horizon else { continue }
                items.append(
                    HomeDigestItem(
                        id: "qiansi.reminder.\(reminder.id)",
                        serviceID: "qiansi",
                        title: reminder.title,
                        subtitle: "提醒 · \(dayLabel(date, today: today))",
                        symbol: "bell.fill",
                        date: date,
                        target: NativeTarget(kind: "reminder", identifier: reminder.id)
                    )
                )
            }
        }

        if let cached = await center.cache.load(ShenshiSnapshot.self, serviceID: "shenshi") {
            let snapshot = cached.payload
            for task in snapshot.overdue {
                let date = ShenshiDate.parse(task.dueDate)
                    ?? QiansiLocalDate.parse(task.dueDate ?? "")
                    ?? today
                items.append(
                    HomeDigestItem(
                        id: "shenshi.task.\(task.id)",
                        serviceID: "shenshi",
                        title: task.title,
                        subtitle: "慎始 · 已逾期",
                        symbol: "checklist",
                        date: date,
                        target: NativeTarget(kind: "task", identifier: "\(task.id)")
                    )
                )
            }
            for task in snapshot.today where !task.isDone {
                let date = ShenshiDate.parse(task.dueDate)
                    ?? QiansiLocalDate.parse(task.dueDate ?? "")
                    ?? today
                items.append(
                    HomeDigestItem(
                        id: "shenshi.task.\(task.id)",
                        serviceID: "shenshi",
                        title: task.title,
                        subtitle: "慎始 · 今天到期",
                        symbol: "checklist",
                        date: date,
                        target: NativeTarget(kind: "task", identifier: "\(task.id)")
                    )
                )
            }
        }

        if let cached = await center.cache.load(YuexiSnapshot.self, serviceID: "yuexi"),
           let status = cached.payload.status {
            for item in status.upcoming where item.daysLeft <= 3 {
                guard let date = QiansiLocalDate.parse(item.nextPeriod) else { continue }
                items.append(
                    HomeDigestItem(
                        id: "yuexi.\(item.nextPeriod).\(item.name ?? "")",
                        serviceID: "yuexi",
                        title: item.name.map { "\($0)的周期" } ?? "经期预测",
                        subtitle: "月汐 · \(item.daysLeft <= 0 ? "已到期" : "\(item.daysLeft) 天后")",
                        symbol: "drop.fill",
                        date: date,
                        target: nil
                    )
                )
            }
        }

        if let cached = await center.cache.load(MujianSnapshot.self, serviceID: "mujian") {
            let weekLater = calendar.date(byAdding: .day, value: 7, to: today) ?? horizon
            for show in cached.payload.upcoming where show.startsAt < weekLater {
                let when = show.startsAt.formatted(.dateTime.month().day().hour().minute())
                let venue = (show.venue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                items.append(
                    HomeDigestItem(
                        id: "mujian.\(show.id)",
                        serviceID: "mujian",
                        title: show.name,
                        subtitle: venue.isEmpty ? "幕间 · \(when)" : "幕间 · \(when) · \(venue)",
                        symbol: "theatermasks.fill",
                        date: show.startsAt,
                        target: nil
                    )
                )
            }
        }

        var seen: Set<String> = []
        return items
            .filter { seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                if lhs.date == rhs.date { return lhs.title < rhs.title }
                return lhs.date < rhs.date
            }
            .prefix(limit)
            .map { $0 }
    }

    /// 在本地快照里搜条目。应用名的搜索仍由首页自己处理。
    static func search(
        _ raw: String,
        center: IntegrationCenter,
        perServiceLimit: Int = 4
    ) async -> [HomeSearchHit] {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var hits: [HomeSearchHit] = []

        if let cached = await center.cache.load(QingyeSnapshot.self, serviceID: "qingye") {
            for plant in cached.payload.plants where matches(query, [plant.name, plant.species]) {
                hits.append(
                    HomeSearchHit(
                        id: "qingye.plant.\(plant.id)",
                        serviceID: "qingye",
                        title: plant.name,
                        subtitle: plant.species?.isEmpty == false ? plant.species! : "植物",
                        target: nil
                    )
                )
            }
        }

        if let cached = await center.cache.load(QiansiSnapshot.self, serviceID: "qiansi") {
            let snapshot = cached.payload
            for person in snapshot.people where matches(query, [person.name, person.nickname, person.notes]) {
                hits.append(
                    HomeSearchHit(
                        id: "qiansi.person.\(person.id)",
                        serviceID: "qiansi",
                        title: person.name,
                        subtitle: "联系人",
                        target: nil
                    )
                )
            }
            for anniversary in snapshot.anniversaries where matches(query, [anniversary.title, anniversary.personName]) {
                hits.append(
                    HomeSearchHit(
                        id: "qiansi.anniversary.\(anniversary.id)",
                        serviceID: "qiansi",
                        title: anniversary.title,
                        subtitle: "生日/纪念日 · \(anniversary.nextDate ?? anniversary.date)",
                        target: NativeTarget(kind: "anniversary", identifier: anniversary.id)
                    )
                )
            }
            for event in snapshot.events where matches(query, [event.title, event.location]) {
                hits.append(
                    HomeSearchHit(
                        id: "qiansi.event.\(event.id)",
                        serviceID: "qiansi",
                        title: event.title,
                        subtitle: event.location?.isEmpty == false ? event.location! : "约会",
                        target: NativeTarget(kind: "event", identifier: event.id)
                    )
                )
            }
        }

        if let cached = await center.cache.load(ShenshiSnapshot.self, serviceID: "shenshi") {
            let snapshot = cached.payload
            for task in snapshot.today + snapshot.overdue where matches(query, [task.title, task.notes]) {
                hits.append(
                    HomeSearchHit(
                        id: "shenshi.task.\(task.id)",
                        serviceID: "shenshi",
                        title: task.title,
                        subtitle: task.isDone ? "任务 · 已完成" : "任务",
                        target: NativeTarget(kind: "task", identifier: "\(task.id)")
                    )
                )
            }
            for habit in snapshot.habits where matches(query, [habit.name]) {
                hits.append(
                    HomeSearchHit(
                        id: "shenshi.habit.\(habit.id)",
                        serviceID: "shenshi",
                        title: habit.name,
                        subtitle: "习惯",
                        target: nil
                    )
                )
            }
        }

        if let cached = await center.cache.load(YuexiSnapshot.self, serviceID: "yuexi"),
           let persons = cached.payload.records?.persons {
            for person in persons where matches(query, [person.name]) {
                hits.append(
                    HomeSearchHit(
                        id: "yuexi.person.\(person.id)",
                        serviceID: "yuexi",
                        title: person.name,
                        subtitle: "记录人",
                        target: nil
                    )
                )
            }
        }

        if let cached = await center.cache.load(MujianSnapshot.self, serviceID: "mujian") {
            for show in cached.payload.upcoming where matches(query, [show.name, show.venue]) {
                hits.append(
                    HomeSearchHit(
                        id: "mujian.\(show.id)",
                        serviceID: "mujian",
                        title: show.name,
                        subtitle: [show.venue, show.startsAt.formatted(.dateTime.month().day())]
                            .compactMap { $0 }
                            .joined(separator: " · "),
                        target: nil
                    )
                )
            }
        }

        if let cached = await center.cache.load(ChaxinSnapshot.self, serviceID: "chaxin") {
            for repo in cached.payload.repos where matches(query, [repo.fullName, repo.description]) {
                hits.append(
                    HomeSearchHit(
                        id: "chaxin.repo.\(repo.id)",
                        serviceID: "chaxin",
                        title: repo.fullName,
                        subtitle: repo.description?.isEmpty == false ? repo.description! : "监控仓库",
                        target: nil
                    )
                )
            }
        }

        if let cached = await center.cache.load(HuozhiSnapshot.self, serviceID: "huozhi") {
            let snapshot = cached.payload
            for book in snapshot.books where matches(query, [book.name]) {
                hits.append(
                    HomeSearchHit(
                        id: "huozhi.book.\(book.id)",
                        serviceID: "huozhi",
                        title: book.name,
                        subtitle: "账本",
                        target: nil
                    )
                )
            }
            for account in snapshot.accounts where matches(query, [account.name, account.bankName, account.cardNo4]) {
                hits.append(
                    HomeSearchHit(
                        id: "huozhi.account.\(account.id)",
                        serviceID: "huozhi",
                        title: account.name,
                        subtitle: [account.bankName, account.cardNo4.map { "尾号 \($0)" }]
                            .compactMap { $0 }
                            .joined(separator: " · "),
                        target: nil
                    )
                )
            }
        }

        // 每个应用最多几条，避免一个应用把整屏占满。
        var counts: [String: Int] = [:]
        var result: [HomeSearchHit] = []
        for hit in hits {
            let used = counts[hit.serviceID, default: 0]
            guard used < perServiceLimit else { continue }
            counts[hit.serviceID] = used + 1
            result.append(hit)
        }
        return result
    }

    // MARK: - 工具

    private static func matches(_ query: String, _ fields: [String?]) -> Bool {
        fields.contains { field in
            guard let field, !field.isEmpty else { return false }
            return field.localizedStandardContains(query)
        }
    }

    private static func dayLabel(_ date: Date, today: Date) -> String {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let diff = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch diff {
        case ..<0: return "逾期 \(-diff) 天"
        case 0: return "今天"
        case 1: return "明天"
        default: return "\(diff) 天后"
        }
    }
}

// MARK: - 首页卡片

/// 今日概览。条目直接带路由，点击落到对应应用或应用内那一条。
struct HomeDigestCard: View {

    let items: [HomeDigestItem]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let visibleLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("今天", systemImage: "sun.max.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Text("\(items.count) 件")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                let visible = Array(items.prefix(Self.visibleLimit))
                ForEach(visible) { item in
                    NavigationLink(value: AppModel.Route(serviceID: item.serviceID, target: item.target)) {
                        row(item)
                    }
                    .buttonStyle(.plain)

                    if item.id != visible.last?.id {
                        Divider().padding(.leading, 34)
                    }
                }
            }

            if items.count > Self.visibleLimit {
                Text("另有 \(items.count - Self.visibleLimit) 件，进入对应应用查看")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.zmCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator.opacity(0.35))
        }
    }

    private func row(_ item: HomeDigestItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 24, height: 24)
                .background(
                    Color.accentColor.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                Text(item.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }

            Spacer(minLength: 6)

            Text(ServiceDisplay.name(for: item.serviceID))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// 搜索结果里的「条目」区。按应用分组，避免把不同应用的结果混在一起。
struct HomeSearchHitsCard: View {

    let hits: [HomeSearchHit]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("匹配的条目 · \(hits.count)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ServiceDisplay.name(for: group.id))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ForEach(group.hits) { hit in
                            NavigationLink(value: AppModel.Route(serviceID: hit.serviceID, target: hit.target)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(hit.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(14)
            .background(Color.zmCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.separator.opacity(0.35))
            }
        }
    }

    private struct SearchGroup: Identifiable {
        let id: String
        let hits: [HomeSearchHit]
    }

    private var groups: [SearchGroup] {
        var order: [String] = []
        var grouped: [String: [HomeSearchHit]] = [:]
        for hit in hits {
            if grouped[hit.serviceID] == nil { order.append(hit.serviceID) }
            grouped[hit.serviceID, default: []].append(hit)
        }
        return order.map { SearchGroup(id: $0, hits: grouped[$0] ?? []) }
    }
}
