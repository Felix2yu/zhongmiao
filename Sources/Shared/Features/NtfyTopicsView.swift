import SwiftUI
import ZhongmiaoCore

/// ntfy 主题的浏览与订阅。
///
/// 存在的理由：ntfy 网页版把「订阅 / 新建主题」藏在左侧抽屉里，嵌在众妙中时固定顶栏
/// 会和系统导航栏重叠，菜单点不到。这里直接读服务器目录，点一下就订阅，完全不依赖网页 UI。
struct NtfyTopicsView: View {

    @Environment(AppModel.self) private var model

    @State private var serverTopics: [String] = []
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var draft = ""
    @State private var draftError: String?

    var body: some View {
        #if os(macOS)
        macBody
        #else
        iosBody
        #endif
    }

    // MARK: - iOS

    #if os(iOS)
    private var iosBody: some View {
        Form {
            Section {
                if isLoading && !hasLoaded {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在读取服务器主题…")
                            .foregroundStyle(.secondary)
                    }
                } else if let loadError {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("读取失败", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(loadError)
                            .zmFont(.caption)
                            .foregroundStyle(.secondary)
                        Button("重试") {
                            Task { await load() }
                        }
                        .buttonStyle(.borderless)
                        .zmFont(.caption)
                    }
                } else {
                    if serverTopics.isEmpty {
                        Text("服务器上还没有缓存过任何主题")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(serverTopics, id: \.self) { topic in
                        serverTopicRow(topic)
                    }
                    Button {
                        Task { await load() }
                    } label: {
                        Label("刷新服务器主题", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            } header: {
                Text("服务器上的主题")
            } footer: {
                Text("来自 GET /v1/topics，只列出服务器上已有消息的主题。点一下即订阅，不用再进 ntfy 网页版。\n当前服务器：\(serverAddressText)")
            }

            Section {
                if model.ntfyTopics.isEmpty {
                    Text("还没有订阅任何主题")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.ntfyTopics, id: \.self) { topic in
                        HStack(spacing: 10) {
                            Image(systemName: "bell.badge")
                                .zmFont(.caption)
                                .foregroundStyle(.tint)
                                .frame(width: 20)
                            Text(topic)
                            Spacer(minLength: 8)
                            Button("取消订阅", role: .destructive) {
                                model.unsubscribeNtfyTopic(topic)
                            }
                            .buttonStyle(.borderless)
                            .zmFont(.caption)
                        }
                    }
                }
            } header: {
                Text("已订阅")
            } footer: {
                Text("每个主题独立推进游标、独立去重，收件箱里按主题名显示。取消订阅不会删除已收到的通知。")
            }

            Section {
                TextField("例如 alerts", text: $draft)
                    .zmPlainTextInput()
                    .onSubmit { subscribeDraft() }

                if let draftError {
                    Text(draftError)
                        .zmFont(.caption)
                        .foregroundStyle(.orange)
                }

                Button("订阅这个主题") {
                    subscribeDraft()
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("新建主题")
            } footer: {
                Text("ntfy 的主题按需创建：本地订阅立即生效，第一次往这个主题发布消息时服务器才会缓存它。只能用字母、数字、- 和 _。")
            }

            Section {
                if let ntfyService = ServiceCatalog.service(id: "ntfy") {
                    NavigationLink {
                        ServiceConfigView(service: ntfyService)
                    } label: {
                        LabeledContent {
                            Text(serverAddressText)
                                .zmFont(.caption, design: .monospaced)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } label: {
                            Label("服务器地址与令牌", systemImage: "externaldrive.connected.to.line.below")
                        }
                    }
                }
            } header: {
                Text("服务器")
            } footer: {
                Text("ntfy 本身也是一个服务，地址覆盖与访问令牌统一在它的配置页里填，这里不再重复一处入口。服务端启用访问控制（auth-file）时，读主题和「标记已读」都要带令牌，且令牌需要对该主题有写权限。")
            }
        }
        .navigationTitle("ntfy 主题")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            guard !hasLoaded else { return }
            await load()
        }
        .onChange(of: model.ntfyToken) { _, _ in
            Task { await load() }
        }
        .refreshable {
            await load()
        }
    }
    #endif

    // MARK: - macOS

    #if os(macOS)
    @Environment(\.interfaceScale) private var scale

    private var macBody: some View {
        MacSettingsPage {
            MacSettingsGroup(title: "服务器上的主题", footer: serverTopicsFooter) {
                if isLoading && !hasLoaded {
                    MacSettingsStackRow {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在读取服务器主题…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let loadError {
                    MacSettingsStackRow {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("读取失败", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Text(loadError)
                                .zmFont(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    MacSettingsDivider()

                    MacSettingsButtonRow(title: "重试", systemImage: "arrow.clockwise") {
                        Task { await load() }
                    }
                } else {
                    if serverTopics.isEmpty {
                        MacSettingsStackRow {
                            Text("服务器上还没有缓存过任何主题")
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(serverTopics, id: \.self) { topic in
                        macServerTopicRow(topic)
                        MacSettingsDivider()
                    }

                    MacSettingsButtonRow(title: "刷新服务器主题", systemImage: "arrow.clockwise") {
                        Task { await load() }
                    }
                    .disabled(isLoading)
                }
            }

            MacSettingsGroup(title: "已订阅", footer: subscribedFooter) {
                if model.ntfyTopics.isEmpty {
                    MacSettingsStackRow {
                        Text("还没有订阅任何主题")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(Array(model.ntfyTopics.enumerated()), id: \.element) { index, topic in
                        MacSettingsRow(title: topic) {
                            Button("取消订阅", role: .destructive) {
                                model.unsubscribeNtfyTopic(topic)
                            }
                            .zmPushButton(role: .destructive)
                            .accessibilityLabel("取消订阅 \(topic)")
                        }
                        if index < model.ntfyTopics.count - 1 {
                            MacSettingsDivider()
                        }
                    }
                }
            }

            MacSettingsGroup(title: "新建主题", footer: newTopicFooter) {
                MacSettingsRow(title: "主题名", fillsWidth: true) {
                    TextField("例如 alerts", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { subscribeDraft() }
                        .accessibilityLabel("主题名")
                }

                if let draftError {
                    MacSettingsDivider()

                    MacSettingsStackRow {
                        Text(draftError)
                            .zmFont(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                MacSettingsDivider()

                MacSettingsButtonRow(title: "订阅这个主题", systemImage: "plus.circle") {
                    subscribeDraft()
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            MacSettingsGroup(title: "服务器", footer: serverFooter) {
                if let ntfyService = ServiceCatalog.service(id: "ntfy") {
                    MacSettingsNavigationRow(
                        title: "服务器地址与令牌",
                        systemImage: "externaldrive.connected.to.line.below",
                        detail: serverAddressText
                    ) {
                        ServiceConfigView(service: ntfyService)
                    }
                }
            }
        }
        .navigationTitle("ntfy 主题")
        .task {
            guard !hasLoaded else { return }
            await load()
        }
        .onChange(of: model.ntfyToken) { _, _ in
            Task { await load() }
        }
    }

    private var serverTopicsFooter: String {
        "来自 GET /v1/topics，只列出服务器上已有消息的主题。点一下即订阅，不用再进 ntfy 网页版。当前服务器：\(serverAddressText)"
    }

    private var subscribedFooter: String {
        "每个主题独立推进游标、独立去重，收件箱里按主题名显示。取消订阅不会删除已收到的通知。"
    }

    private var newTopicFooter: String {
        "ntfy 的主题按需创建：本地订阅立即生效，第一次往这个主题发布消息时服务器才会缓存它。只能用字母、数字、- 和 _。"
    }

    private var serverFooter: String {
        "ntfy 本身也是一个服务，地址覆盖与访问令牌统一在它的配置页里填，这里不再重复一处入口。服务端启用访问控制（auth-file）时，读主题和「标记已读」都要带令牌，且令牌需要对该主题有写权限。"
    }

    private func macServerTopicRow(_ topic: String) -> some View {
        let subscribed = model.isNtfyTopicSubscribed(topic)
        return Button {
            guard !subscribed else { return }
            if let error = model.subscribeNtfyTopic(topic) {
                draftError = error
            } else {
                model.toast = "已订阅 \(topic)"
            }
        } label: {
            HStack(spacing: 8.zmScaled(scale)) {
                Image(systemName: subscribed ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(subscribed ? Color.green : Color.accentColor)
                    .frame(width: 20.zmScaled(scale))
                Text(topic)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(subscribed ? "已订阅" : "订阅")
                    .zmFont(.caption)
                    .foregroundStyle(subscribed ? Color.secondary : Color.accentColor)
            }
            .padding(.horizontal, 14.zmScaled(scale))
            .padding(.vertical, 5.zmScaled(scale))
            .frame(minHeight: 32.zmScaled(scale))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(subscribed)
        .accessibilityLabel(Text("\(topic)，\(subscribed ? "已订阅" : "订阅")"))
    }
    #endif

    private var serverAddressText: String {
        model.resolvedNtfyBase()?.absoluteString ?? "未解析，请在下方填写 ntfy 地址"
    }

    @ViewBuilder
    private func serverTopicRow(_ topic: String) -> some View {
        let subscribed = model.isNtfyTopicSubscribed(topic)
        Button {
            guard !subscribed else { return }
            if let error = model.subscribeNtfyTopic(topic) {
                draftError = error
            } else {
                model.toast = "已订阅 \(topic)"
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: subscribed ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(subscribed ? Color.green : Color.accentColor)
                    .frame(width: 20)
                Text(topic)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(subscribed ? "已订阅" : "订阅")
                    .zmFont(.caption)
                    .foregroundStyle(subscribed ? Color.secondary : Color.accentColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(subscribed)
    }

    private func subscribeDraft() {
        let error = model.subscribeNtfyTopic(draft)
        draftError = error
        if error == nil {
            model.toast = "已订阅 \(draft.trimmingCharacters(in: .whitespacesAndNewlines))"
            draft = ""
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        let result = await model.loadServerNtfyTopics()
        switch result {
        case .success(let topics):
            serverTopics = topics
            hasLoaded = true
        case .failure(let error):
            loadError = error.message
        }
        isLoading = false
    }
}
