import SwiftUI
import ZhongmiaoCore

struct NtfyScreen: View {

    @Environment(AppModel.self) private var model

    let service: ServiceDefinition
    let baseURL: URL
    let definition: IntegrationDefinition

    @State private var store: NtfyModel
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
        _store = State(initialValue: NtfyModel(service: service, baseURL: baseURL, center: center))
    }

    var body: some View {
        @Bindable var store = store

        List {
            if let state = bannerState {
                Section {
                    IntegrationStatusBanner(
                        state: state,
                        error: store.error ?? store.center.lastErrors["ntfy"],
                        onConfigure: { showCredential = true },
                        onRetry: { Task { await store.refresh() } }
                    )
                    .listRowInsets(EdgeInsets())
                }
            }

            Section {
                topicChips
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }

            if store.visibleMessages.isEmpty {
                Section {
                    EmptyStateView(
                        symbol: "tray",
                        title: store.query.isEmpty ? "这个主题还没有消息" : "没有搜索结果",
                        message: store.query.isEmpty ? "ntfy 缓存里没有可显示的消息。" : "换个关键词试试。"
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(store.visibleMessages, id: \.id) { message in
                        messageRow(message)
                    }
                } header: {
                    HStack {
                        Text(store.query.isEmpty ? (store.selectedTopic ?? "消息") : "搜索结果")
                        Spacer()
                        if store.query.isEmpty, !store.messages.isEmpty {
                            Button("全部标记已读") {
                                Task { await store.markAllRead() }
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section {
                NavigationLink {
                    ServiceScreen(service: service, initialURL: baseURL)
                } label: {
                    Label("发布消息与账户设置", systemImage: "safari")
                }
            } footer: {
                Text("原生只读浏览、搜索、标记已读与删除；发布消息仍在网页版。")
            }
        }
        .navigationTitle(service.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $store.query, prompt: "搜索 ntfy 消息")
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
        .task(id: store.query) {
            await store.search()
        }
        .refreshWhenIntegrationReady(center: store.center, serviceID: "ntfy") {
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
        let state = store.center.state(for: "ntfy")
        if state.isUsable && store.error == nil { return nil }
        return state
    }

    private var topicChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.topics, id: \.self) { topic in
                    Button {
                        Task { await store.selectTopic(topic) }
                    } label: {
                        Text(topic)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .foregroundStyle(store.selectedTopic == topic ? Color.white : Color.secondary)
                            .background(
                                store.selectedTopic == topic ? Color.accentColor : Color.secondary.opacity(0.12),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func messageRow(_ message: NtfyMessage) -> some View {
        let expanded = store.expandedID == message.id
        return VStack(alignment: .leading, spacing: 7) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    store.expandedID = expanded ? nil : message.id
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(message.title?.isEmpty == false ? message.title! : (message.topic ?? "消息"))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let time = message.time {
                            Text(Date(timeIntervalSince1970: TimeInterval(time)), style: .time)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(message.message ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(expanded ? nil : 3)
                    if let tags = message.tags, !tags.isEmpty {
                        Text(tags.map { "#\($0)" }.joined(separator: " "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                HStack(spacing: 10) {
                    if let priority = message.priority, priority >= 4 {
                        CapsuleTag(text: "高优先级", systemImage: "exclamationmark", tint: .orange)
                    }
                    if let click = message.click, let url = URL(string: click) {
                        Link("打开链接", destination: url)
                            .font(.caption)
                    }
                    Spacer()
                    Button("删除", role: .destructive) {
                        Task { await store.delete(message) }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
