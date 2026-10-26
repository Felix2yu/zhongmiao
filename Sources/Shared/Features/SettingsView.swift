import SwiftUI
import ZhongmiaoCore

struct SettingsView: View {

    @Environment(AppModel.self) private var model
    @State private var showClearDataConfirm = false

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
                Picker("接入方式", selection: $model.settings.addressing.mode) {
                    ForEach(AddressMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch model.settings.addressing.mode {
                case .subdomain, .path:
                    TextField("基础域名", text: $model.settings.addressing.baseDomain)
                        .zmPlainTextInput()
                case .port:
                    TextField("内网主机", text: $model.settings.addressing.lanHost)
                        .zmPlainTextInput()
                }
            } header: {
                Text("接入方式")
            } footer: {
                Text(model.settings.addressing.mode.hint + " 修改后所有服务地址立即重算，可到「体检」页一键验证；个别服务也可在「逐服务配置」里单独覆盖。")
            }

            Section {
                LabeledContent("授权状态", value: model.notificationStatusText)

                if model.authorization == .notDetermined {
                    Button {
                        Task { await model.requestNotificationPermission() }
                    } label: {
                        Label("开启通知", systemImage: "bell.badge")
                    }
                }

                Toggle("后台刷新", isOn: $model.settings.backgroundRefreshEnabled)

                LabeledContent("待补发") {
                    Text("\(model.snapshot.pendingCount) 条")
                        .foregroundStyle(model.snapshot.pendingCount > 0 ? .orange : .secondary)
                }

                Button {
                    model.syncNow(reason: "手动")
                } label: {
                    Label(model.isSyncing ? "同步中…" : "立即同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(model.isSyncing)
            } header: {
                Text("通知")
            } footer: {
                Text("通知走三条通道：页面内提醒直接桥接为系统通知；ntfy 主题与各应用的通知流由后台刷新拉取；配置中继后还可接收 APNs 推送并补齐漏收事件。")
            }

            Section {
                NavigationLink {
                    NtfyTopicsView()
                } label: {
                    LabeledContent {
                        Text(model.ntfyTopics.isEmpty ? "未订阅" : "\(model.ntfyTopics.count) 个主题")
                    } label: {
                        Label("ntfy 主题", systemImage: "bell.badge")
                    }
                }
            } header: {
                Text("ntfy 订阅")
            } footer: {
                Text("列出服务器上已有消息的主题，点一下即订阅。不依赖 ntfy 网页版——它在嵌入众妙时固定顶栏可能被系统导航栏压住。")
            }

            Section {
                TextField("推送中继地址", text: $model.settings.relayURL)
                    .zmPlainTextInput()
                    #if os(iOS)
                    .keyboardType(.URL)
                    #endif

                TextField("中继共享密钥", text: $model.settings.relaySecret)
                    .zmPlainTextInput()

                LabeledContent("设备令牌") {
                    Text(model.pushToken.map { String($0.prefix(10)) + "…" } ?? "未注册")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                if let pushError = model.pushError {
                    Text(pushError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button {
                    model.registerForRemoteNotifications()
                    model.uploadPushToken()
                } label: {
                    Label("重新注册推送", systemImage: "arrow.clockwise")
                }
            } header: {
                Text("推送中继（可选）")
            } footer: {
                Text("中继服务见仓库 server/push-relay。不配置也能用：页面内通知与后台拉取不需要它，只是没有「应用被杀死时立即送达」的能力。")
            }

            Section {
                NavigationLink {
                    ServiceSettingsListView()
                } label: {
                    Label("逐服务配置", systemImage: "slider.horizontal.3")
                }
                LabeledContent("服务数量", value: "\(ServiceCatalog.all.count) 个")

                Toggle("显示服务能力标签", isOn: $model.settings.showServiceCapabilityTags)
            } header: {
                Text("服务")
            } footer: {
                Text("关掉后，应用卡片不再显示「离线可用」这类能力标签，只保留「未配置」等真正需要处理的提示。")
            }

            Section {
                Stepper(value: $model.settings.inboxCapacity, in: 100...2000, step: 100) {
                    LabeledContent("收件箱容量", value: "\(model.settings.inboxCapacity) 条")
                }

                Stepper(value: $model.settings.lookbackHours, in: 1...168) {
                    LabeledContent("冷启动回看", value: "\(model.settings.lookbackHours) 小时")
                }

                Button(role: .destructive) {
                    model.clearInbox()
                } label: {
                    Label("清空收件箱", systemImage: "trash")
                }
                .disabled(model.snapshot.items.isEmpty)

                Button(role: .destructive) {
                    showClearDataConfirm = true
                } label: {
                    Label("清除网页缓存与登录状态", systemImage: "externaldrive.badge.xmark")
                }
            } header: {
                Text("数据")
            } footer: {
                Text("清除网页数据会删掉各应用的 Service Worker 缓存与 Cookie，之后需要重新登录、联网重新缓存。")
            }

            Section {
                LabeledContent("版本", value: appVersion)
                LabeledContent("平台", value: Platform.platformName)
                Text("众妙是自托管应用的聚合入口：一个壳、一套通知、一份地址配置。后端仍是各自的 Go 服务，数据不出内网。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("关于")
            }
        }
        .navigationTitle("设置")
        .onChange(of: model.settings) { _, _ in
            model.persistSettings()
        }
        .confirmationDialog(
            "清除网页缓存与登录状态？",
            isPresented: $showClearDataConfirm,
            titleVisibility: .visible
        ) {
            Button("清除", role: .destructive) {
                model.clearWebsiteData()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有应用的离线缓存和登录状态都会被删除。")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

struct ServiceSettingsListView: View {

    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(ServiceCatalog.grouped, id: \.category) { group in
                Section(group.category.title) {
                    ForEach(group.services) { service in
                        NavigationLink {
                            ServiceEditorView(service: service)
                        } label: {
                            HStack(spacing: 10) {
                                ServiceGlyph(service: service, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(service.name)
                                        .font(.subheadline)
                                    Text(model.url(for: service)?.absoluteString ?? "未配置地址")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                if model.settings.preference(for: service).notificationsEnabled {
                                    Image(systemName: "bell.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("服务")
    }
}
