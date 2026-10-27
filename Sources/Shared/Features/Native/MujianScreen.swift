import SwiftUI
import ZhongmiaoCore

struct MujianScreen: View {

    @Environment(AppModel.self) private var model

    let service: ServiceDefinition
    let baseURL: URL
    let definition: IntegrationDefinition

    @State private var store: IntegrationSnapshotModel<MujianSnapshot>
    @State private var showCredential = false
    @State private var expandedID: String?

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
            serviceID: "mujian",
            baseURL: baseURL,
            center: center,
            loader: {
                let token = center.credential(for: "mujian")?.bearer ?? ""
                let client = MujianClient(baseURL: baseURL, token: token)
                async let dashboard = client.dashboard()
                async let upcoming = ShowClient(days: 14).fetchUpcoming(baseURL: baseURL, token: token)
                return MujianSnapshot(
                    dashboard: try? await dashboard,
                    upcoming: try await upcoming
                )
            }
        ))
    }

    var body: some View {
        List {
            Section {
                metrics
                    .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
            }

            if let state = bannerState {
                Section {
                    IntegrationStatusBanner(
                        state: state,
                        error: store.error ?? store.center.lastErrors["mujian"],
                        onConfigure: { showCredential = true },
                        onRetry: { Task { await store.refresh() } }
                    )
                    .listRowInsets(EdgeInsets())
                }
            }

            if let upcoming = store.snapshot?.upcoming, !upcoming.isEmpty {
                Section {
                    ForEach(upcoming) { show in
                        showRow(show)
                    }
                } header: {
                    Text("未来演出")
                }
            } else {
                Section {
                    EmptyStateView(
                        symbol: "theatermasks",
                        title: "近期没有演出",
                        message: "幕间里未来 14 天没有待看记录。"
                    )
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                NavigationLink {
                    ServiceScreen(service: service, initialURL: baseURL)
                } label: {
                    Label("录入/编辑演出", systemImage: "safari")
                }
            } footer: {
                Text("演出提醒仍由既有本地通知排程；这里只做原生浏览与统计。")
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
        .refreshWhenIntegrationReady(center: store.center, serviceID: "mujian") {
            Task { await store.refresh() }
        }
        .onChange(of: model.network.isOnline) { _, online in
            if online { Task { await store.refresh() } }
        }
        .sheet(isPresented: $showCredential) {
            CredentialSheet(definition: definition, service: service)
        }
    }

    private var bannerState: IntegrationCenter.CredentialState? {
        let state = store.center.state(for: "mujian")
        if state.isUsable && store.error == nil { return nil }
        return state
    }

    private var metrics: some View {
        let dashboard = store.snapshot?.dashboard
        return HStack(spacing: 10) {
            metric("记录", value: dashboard?.totalRecords.map(String.init) ?? "—", tint: .accentColor)
            metric("城市", value: dashboard?.totalCities.map(String.init) ?? "—", tint: .blue)
            metric("评分", value: dashboard?.avgRating.map { String(format: "%.1f", $0) } ?? "—", tint: .orange)
        }
    }

    private func metric(_ title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func showRow(_ show: Show) -> some View {
        let expanded = expandedID == show.id
        return VStack(alignment: .leading, spacing: 7) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedID = expanded ? nil : show.id
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(show.startsAt.formatted(.dateTime.month().day().weekday(.abbreviated)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("《\(show.name)》")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text([show.venue, show.seat].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text(show.startsAt.formatted(.dateTime.hour().minute()))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 5) {
                    Label(show.startsAt.formatted(.dateTime.year().month().day().hour().minute()), systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let endsAt = show.endsAt {
                        Label("预计 \(endsAt.formatted(.dateTime.hour().minute())) 结束", systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let url = show.url {
                        Link("打开演出详情", destination: url)
                            .font(.caption)
                    }
                }
                .padding(.leading, 2)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
    }
}
