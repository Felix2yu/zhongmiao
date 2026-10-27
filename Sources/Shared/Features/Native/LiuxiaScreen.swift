import SwiftUI
import ZhongmiaoCore

struct LiuxiaScreen: View {

    @Environment(AppModel.self) private var model

    let service: ServiceDefinition
    let baseURL: URL
    let definition: IntegrationDefinition

    @State private var store: IntegrationSnapshotModel<LiuxiaSnapshot>
    @State private var selectedCity: String?

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
                async let today = client.today()
                async let cities = client.cities()
                async let rankings = client.rankings()
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
                dateHeader
                    .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
            }

            if let error = store.error {
                Section {
                    IntegrationStatusBanner(
                        state: store.center.state(for: "liuxia"),
                        error: error,
                        onConfigure: {},
                        onRetry: { Task { await store.refresh() } }
                    )
                    .listRowInsets(EdgeInsets())
                }
            }

            Section {
                cityChips
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }

            ForEach(["morning", "evening"], id: \.self) { eventType in
                let records = filteredRecords(eventType: eventType)
                if !records.isEmpty {
                    Section {
                        ForEach(records) { record in
                            recordRow(record)
                        }
                    } header: {
                        Text(eventType == "morning" ? "朝霞" : "晚霞")
                    }
                }
            }

            if let best = store.snapshot?.rankings?.bestDates, !best.isEmpty {
                Section {
                    ForEach(best) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.city)
                                    .font(.subheadline)
                                Text("\(item.date) \(item.time ?? "") · \(item.eventType == "morning" ? "朝霞" : "晚霞")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            qualityBadge(item.quality)
                        }
                    }
                } header: {
                    Text("近期最佳")
                }
            }

            Section {
                NavigationLink {
                    ServiceScreen(service: service, initialURL: baseURL)
                } label: {
                    Label("历史归档与导出", systemImage: "safari")
                }
            } footer: {
                Text("预报日期以服务端为准；质量与气溶胶为可空值。")
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
            await store.refreshIfNeeded()
        }
        .onChange(of: model.network.isOnline) { _, online in
            if online { Task { await store.refresh() } }
        }
    }

    private var dateHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("今日与明日")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let today = store.snapshot?.today {
                Text("\(today.today) · 明日 \(today.tomorrow)")
                    .font(.headline.monospacedDigit())
            } else {
                Text("正在读取预报…")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.zmCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

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

    private func filteredRecords(eventType: String) -> [LiuxiaRecord] {
        (store.snapshot?.today?.data ?? []).filter { record in
            record.eventType == eventType && (selectedCity == nil || record.city == selectedCity)
        }
    }

    private func recordRow(_ record: LiuxiaRecord) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(record.city) · \(record.model)")
                    .font(.subheadline)
                Text("\(record.date) \(record.time ?? "")")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            qualityBadge(record.quality)
        }
        .padding(.vertical, 1)
    }

    private func qualityBadge(_ quality: Double?) -> some View {
        let value = quality.map { String(format: "%.2f", $0) } ?? "—"
        let tint: Color = {
            guard let quality else { return .secondary }
            if quality >= 0.6 { return .green }
            if quality >= 0.3 { return .orange }
            return .red
        }()
        return CapsuleTag(text: "质量 \(value)", tint: tint)
    }
}
