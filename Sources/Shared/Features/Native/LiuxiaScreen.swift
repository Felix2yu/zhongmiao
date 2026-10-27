import SwiftUI
import ZhongmiaoCore

struct LiuxiaScreen: View {

    @Environment(AppModel.self) private var model

    let service: ServiceDefinition
    let baseURL: URL
    let definition: IntegrationDefinition

    @State private var store: IntegrationSnapshotModel<LiuxiaSnapshot>
    @State private var selectedCity: String?
    @State private var showCredential = false

    init(
        service: ServiceDefinition,
        baseURL: URL,
        definition: IntegrationDefinition,
        center: IntegrationCenter
    ) {
        self.service = service
        self.baseURL = baseURL
        self.definition = definition
        _store = State(initialValue: IntegrationSnapshotModel(
            serviceID: "liuxia",
            baseURL: baseURL,
            center: center,
            loader: {
                let client = LiuxiaClient(baseURL: baseURL)
                let start = QiansiLocalDate.dayString(.now)
                let end = QiansiLocalDate.dayString(
                    Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
                )
                async let today = client.today()
                async let cities = client.cities()
                async let rankings = client.rankings(start: start, end: end)
                return LiuxiaSnapshot(
                    today: try await today,
                    cities: try await cities,
                    rankings: try? await rankings
                )
            }
        ))
    }

    var body: some View {
        List {
            Section {
                nextUpcomingCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
            }

            if let error = store.error {
                Section {
                    IntegrationStatusBanner(
                        state: store.center.state(for: "liuxia"),
                        error: error,
                        onConfigure: { showCredential = true },
                        onRetry: { Task { await store.refresh() } }
                    )
                    .listRowInsets(EdgeInsets())
                }
            }

            Section {
                cityChips
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }

            daysSection

            if !premiumUpcoming.isEmpty {
                Section {
                    ForEach(premiumUpcoming) { event in
                        premiumRow(event)
                    }
                } header: {
                    Text("未来一周的优质场次")
                } footer: {
                    Text("按「优质大烧」及以上（质量 ≥ 1.5）筛出，按时间先后排。")
                }
            }

            Section {
                NavigationLink {
                    ServiceScreen(service: service, initialURL: baseURL)
                } label: {
                    Label("历史归档与导出", systemImage: "safari")
                }
            } footer: {
                Text("朝霞看日出前 20–30 分钟，晚霞看日落后 15–30 分钟。质量数值与分档由流霞服务端给出。")
            }
        }
        .navigationTitle(service.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                IntegrationScreenMenu(service: service, definition: definition) {
                    Task { await store.refresh() }
                }
            }
        }
        .refreshable {
            await store.refresh()
        }
        .task {
            await store.loadCache()
            // 缓存跨天会把「今天」标错，直接重取。
            if let cached = store.snapshot?.cachedDay, cached != QiansiLocalDate.dayString(.now) {
                await store.refresh()
            } else {
                await store.refreshIfNeeded()
            }
        }
        .refreshWhenIntegrationReady(center: store.center, serviceID: "liuxia") {
            Task { await store.refresh() }
        }
        .onChange(of: model.network.isOnline) { _, online in
            if online { Task { await store.refresh() } }
        }
        .sheet(isPresented: $showCredential) {
            CredentialSheet(definition: definition, service: service)
        }
    }

    // MARK: - 顶部：下一场

    private var nextUpcomingCard: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let upcoming = upcomingEvents(now: context.date)
            // 「下一场」按时间取最近的；另外单独标出 48 小时里质量最高的一场。
            let nearest = upcoming.first
            let best = upcoming.max { lhs, rhs in
                (lhs.quality ?? 0) < (rhs.quality ?? 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(upcoming.isEmpty ? "未来 48 小时" : "下一场")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let city = selectedCity {
                        Text(city).font(.caption2).foregroundStyle(.secondary)
                    }
                }

                if let hero = nearest, let at = hero.occursAt() {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: hero.kind.symbol)
                            .font(.title3)
                            .foregroundStyle(qualityColor(hero.quality))
                        Text(hero.kind.title)
                            .font(.title3.weight(.semibold))
                        Text(at.formatted(.dateTime.month().day().hour().minute()))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(LiuxiaForecast.countdown(from: context.date, to: at))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(qualityColor(hero.quality))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(qualityColor(hero.quality).opacity(0.12), in: Capsule())
                    }

                    HStack(spacing: 8) {
                        CapsuleTag(text: hero.qualityLabel, tint: qualityColor(hero.quality))
                        if let quality = hero.quality {
                            Text(String(format: "%.2f", quality))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(hero.kind.viewingHint)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if let quality = hero.quality {
                        qualityBar(quality)
                    }

                    // 48 小时内还有更值得看的一场（质量更高且真的算优质）时，单独点出来。
                    if let best, best.id != hero.id, best.isPremium, let bestAt = best.occursAt() {
                        Divider()
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .foregroundStyle(qualityColor(best.quality))
                            Text("更值得看：\(dayLabel(best.date)) \(best.time ?? "") \(best.kind.title) · \(best.qualityLabel)")
                                .font(.caption)
                            Spacer()
                            Text(LiuxiaForecast.countdown(from: context.date, to: bestAt))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("未来 48 小时还没有新预报")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.zmCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - 今天 / 明天

    @ViewBuilder
    private var daysSection: some View {
        if let today = store.snapshot?.today {
            Section {
                dayBlock(day: today.today, label: "今天")
                dayBlock(day: today.tomorrow, label: "明天")
            } header: {
                Text("今明两天的朝霞与晚霞")
            }
        } else {
            Section {
                EmptyStateView(
                    symbol: "sunrise",
                    title: "正在读取预报",
                    message: "首次进入需要联网取一次今明数据。"
                )
                .listRowBackground(Color.clear)
            }
        }
    }

    private func dayBlock(day: String, label: String) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                    Text(shortDay(day))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                HStack(spacing: 8) {
                    slotCard(day: day, kind: .morning, now: context.date)
                    slotCard(day: day, kind: .evening, now: context.date)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func slotCard(day: String, kind: LiuxiaEvent.Kind, now: Date) -> some View {
        let event = bestEvent(day: day, kind: kind)
        let at = event?.occursAt()
        let passed = at.map { $0 <= now } ?? false

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: kind.symbol)
                    .font(.caption)
                    .foregroundStyle(event.map { qualityColor($0.quality) } ?? .secondary)
                Text(kind.title)
                    .font(.caption.weight(.medium))
                Spacer()
                if passed {
                    Text("已过")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if let event, let time = event.time {
                Text(time)
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text(event.qualityLabel)
                    .font(.caption2)
                    .foregroundStyle(qualityColor(event.quality))
            } else {
                Text("—")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Text("无预报")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            (event.map { qualityColor($0.quality) } ?? Color.secondary).opacity(passed ? 0.05 : 0.1),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .opacity(passed ? 0.55 : 1)
    }

    // MARK: - 优质场次

    private func premiumRow(_ event: LiuxiaEvent) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: event.kind.symbol)
                    .font(.caption)
                    .foregroundStyle(qualityColor(event.quality))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(dayLabel(event.date)) \(event.time ?? "") · \(event.kind.title)")
                        .font(.subheadline.monospacedDigit())
                    Text(event.city)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    CapsuleTag(text: event.qualityLabel, tint: qualityColor(event.quality))
                    if let at = event.occursAt() {
                        Text(LiuxiaForecast.countdown(from: context.date, to: at))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    // MARK: - 城市

    private var cityChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("全部", selected: selectedCity == nil) { selectedCity = nil }
                ForEach(store.snapshot?.cities ?? [], id: \.self) { city in
                    chip(city, selected: selectedCity == city) {
                        selectedCity = selectedCity == city ? nil : city
                    }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .background(selected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 数据

    /// 今明两天的场次，同一天同一类型多模型时取质量最高的一条。
    private var bestTodayEvents: [LiuxiaEvent] {
        let records = store.snapshot?.today?.data ?? []
        let scoped = records.filter { selectedCity == nil || $0.city == selectedCity }
        return LiuxiaForecast.bestPerSlot(scoped.map(\.asEvent))
    }

    private func bestEvent(day: String, kind: LiuxiaEvent.Kind) -> LiuxiaEvent? {
        bestTodayEvents.first { $0.date == day && $0.kind == kind }
    }

    private func upcomingEvents(now: Date) -> [LiuxiaEvent] {
        LiuxiaForecast.upcoming(bestTodayEvents, now: now, horizonHours: 48)
    }

    /// 未来一周、优质大烧及以上，按发生时间升序。
    private var premiumUpcoming: [LiuxiaEvent] {
        let fromRankings = (store.snapshot?.rankings?.bestDates ?? [])
            .filter { selectedCity == nil || $0.city == selectedCity }
            .map(\.asEvent)
        let merged = LiuxiaForecast.bestPerSlot(bestTodayEvents + fromRankings)
        let premium = LiuxiaForecast.premium(in: merged)
        let now = Date.now
        return premium
            .filter { ($0.occursAt() ?? .distantPast) > now }
            .sorted { ($0.occursAt() ?? .distantFuture) < ($1.occursAt() ?? .distantFuture) }
            .prefix(8)
            .map { $0 }
    }

    private func dayLabel(_ day: String) -> String {
        let today = QiansiLocalDate.dayString(.now)
        let tomorrow = QiansiLocalDate.dayString(Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
        if day == today { return "今天" }
        if day == tomorrow { return "明天" }
        return shortDay(day)
    }

    private func shortDay(_ day: String) -> String {
        // yyyy-MM-dd → MM-dd
        day.count >= 10 ? String(day.dropFirst(5)) : day
    }

    private func qualityColor(_ quality: Double?) -> Color {
        switch LiuxiaQualityScale.tier(quality) {
        case 0: return .secondary
        case 1: return .secondary
        case 2: return .blue
        case 3: return .orange
        default: return .pink
        }
    }

    private func qualityBar(_ quality: Double) -> some View {
        // 质量刻度到 2.5 就够用（再高都是「超级大烧」）。
        let ratio = min(max(quality / 2.5, 0.02), 1)
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.12))
                Capsule()
                    .fill(qualityColor(quality))
                    .frame(width: proxy.size.width * ratio)
            }
        }
        .frame(height: 5)
    }
}
