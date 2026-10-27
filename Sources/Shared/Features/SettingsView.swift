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
                Text(model.settings.addressing.mode.hint + " 这里是所有服务共用的部分；单个服务和全局不一致时，到「服务与接入」里覆盖。修改后所有服务地址立即重算。")
            }

            Section {
                NavigationLink {
                    ServiceSettingsListView()
                } label: {
                    LabeledContent {
                        Text("\(configuredCount)/\(ServiceCatalog.all.count) 可访问")
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("服务与接入", systemImage: "square.grid.2x2")
                    }
                }

                Toggle("显示服务能力标签", isOn: $model.settings.showServiceCapabilityTags)
                Toggle("站外链接在应用内打开", isOn: $model.settings.keepExternalLinksInApp)
            } header: {
                Text("服务")
            } footer: {
                Text("点进任一服务即可配置它的地址覆盖、鉴权凭据、通知通道、本地提醒与首页显示——一个服务一页。关掉上面的开关后，应用卡片不再显示「离线可用」这类能力标签，只保留「未配置」等真正需要处理的提示。站外链接默认留在应用内加载，想用 Safari 时点页面里的「在浏览器打开」；`tel:`、`mailto:` 这类始终交给系统。")
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
                Text("通知走三条通道：页面内提醒直接桥接为系统通知；ntfy 主题与各应用的通知流由后台刷新拉取；配置中继后还可接收 APNs 推送并补齐漏收事件。各服务用哪条通道在它自己的配置页里选。")
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
                Text("列出服务器上已有消息的主题，点一下即订阅。ntfy 的服务器地址与访问令牌在「服务与接入 → ntfy」里，不在这里重复填写。")
            }

            Section {
                Toggle("启用演出提醒", isOn: $model.settings.showsEnabled)

                if model.settings.showsEnabled {
                    Stepper(value: $model.settings.showsReminderLeadHours, in: 1...12) {
                        LabeledContent("提前提醒", value: "\(model.settings.showsReminderLeadHours) 小时")
                    }

                    #if os(iOS)
                    Stepper(value: $model.settings.showsIslandLeadHours, in: 1...8) {
                        LabeledContent("灵动岛提前量", value: "\(model.settings.showsIslandLeadHours) 小时")
                    }
                    #endif

                    if model.mujianToken.isEmpty {
                        Text("幕间访问令牌尚未填写：到「服务与接入 → 幕间」配置一次，演出提醒会直接复用该凭据。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Toggle("从幕间拉取", isOn: $model.settings.showsUseMujianAPI)

                    #if os(iOS)
                    Toggle("读取系统日历", isOn: $model.settings.showsUseCalendar)

                    TextField("日历关键词（逗号分隔）", text: $model.settings.showsCalendarKeywords)
                        .zmPlainTextInput()
                    #endif

                    LabeledContent("已缓存") {
                        Text("\(model.shows.count) 场")
                            .foregroundStyle(model.shows.isEmpty ? .secondary : .primary)
                    }

                    if let next = model.shows.first(where: { $0.startsAt > .now }) {
                        LabeledContent("下一场") {
                            Text("《\(next.name)》\(Self.clock(next.startsAt))")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        Task { await model.refreshShows() }
                    } label: {
                        Label("立即刷新", systemImage: "arrow.clockwise")
                    }
                }
            } header: {
                Text("演出提醒")
            } footer: {
                Text(SettingsView.showFooter)
            }
            .onChange(of: showSettingsFingerprint) {
                Task { await model.refreshShows() }
            }

            Section {
                TextField("推送中继地址", text: $model.settings.relayURL)
                    .zmPlainTextInput()
                    #if os(iOS)
                    .keyboardType(.URL)
                    #endif

                SecretField(
                    title: "中继共享密钥",
                    key: .relay,
                    footer: "保存在系统钥匙串，随 X-Zhongmiao-Token 请求头发送。"
                )

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
                Text("中继不属于任何单个应用，所以留在这里。服务见仓库 server/push-relay。不配置也能用：页面内通知与后台拉取不需要它，只是没有「应用被杀死时立即送达」的能力。")
            }

            Section {
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    LabeledContent {
                        Text(model.network.isOnline ? "在线" : "离线")
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("诊断与日志", systemImage: "stethoscope")
                    }
                }
            } header: {
                Text("诊断")
            } footer: {
                Text("批量检测全部服务的连通性、查看原生接入状态与运行日志。单个服务的检测在它自己的配置页里，不必来回跳。")
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
        // CFBundleVersion 只能是短整数（超 32 位会溢出），真正的时间戳放自定义键，
        // 这样「关于」里能直接对上出包时间，不用再靠猜。
        let stamp = Bundle.main.infoDictionary?["ZMBuildStamp"] as? String ?? "—"
        return "\(version) (\(build)) · \(stamp)"
    }

    private var configuredCount: Int {
        ServiceCatalog.all.filter { model.url(for: $0) != nil }.count
    }

    // MARK: 演出提醒

    /// 演出相关的设置指纹。任一字段变动都重刷一次，省去给七个字段各挂一个 onChange。
    private var showSettingsFingerprint: String {
        let settings = model.settings
        return [
            settings.showsEnabled.description,
            String(settings.showsReminderLeadHours),
            String(settings.showsIslandLeadHours),
            String(model.integrations.secrets.revision),
            settings.showsUseMujianAPI.description,
            settings.showsUseCalendar.description,
            settings.showsCalendarKeywords
        ].joined(separator: "|")
    }

    private static func clock(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: date)
        let month = components.month ?? 0
        let day = components.day ?? 0
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return minute == 0
            ? "\(month)月\(day)日 \(hour)点"
            : "\(month)月\(day)日 \(hour)点\(minute)分"
    }

    static var showFooter: String {
        #if os(iOS)
        "演出时间取自幕间，也会读系统日历里「幕间」同步过去的事件。提醒走本地通知，App 被杀也照常到点。灵动岛最多常驻 8 小时，而 iOS 不允许 App 在精确时刻自己启动，所以要建两个快捷指令自动化（每天 10:00、15:00）跑「开启演出盯场」；演出前打开众妙也会自动开岛。幕间访问令牌在「服务与接入 → 幕间」里填写，这里读的就是那一份。"
        #else
        "演出时间取自幕间，也会读系统日历里「幕间」同步过去的事件。提醒走本地通知，即便 App 已退出也照常到点。幕间访问令牌在「服务与接入 → 幕间」里填写，这里读的就是那一份。"
        #endif
    }
}
