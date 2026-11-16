import SwiftUI
import ZhongmiaoCore

struct SettingsView: View {

    @Environment(AppModel.self) private var model
    @State private var showClearDataConfirm = false
    #if os(macOS)
    /// macOS 上这些二级页用整行按钮跳转，目的地集中注册一次。
    @State private var route: SettingsRoute?
    /// 界面缩放倍数：自绘行的定宽控件要跟着放大，否则字大了输入框还是原尺寸。
    @Environment(\.interfaceScale) private var scale
    #endif

    var body: some View {
        content
            // macOS 的 `navigationTitle` 会改写窗口标题：主窗口切到设置页就变成「设置」，
            // 而这里三页同属一个窗口，标题该保持应用名。iOS 上它才是页面大标题。
            #if os(iOS)
            .navigationTitle("设置")
            #endif
            .onChange(of: model.settings) { _, _ in
                model.persistSettings()
            }
            .onChange(of: showSettingsFingerprint) {
                Task { await model.refreshShows() }
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

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        macForm
        #else
        iosForm
        #endif
    }

    // MARK: - macOS

    #if os(macOS)
    /// macOS 一栏分组卡片。行、卡片、留白都由 `MacSettingsCards` 绘制，
    /// 页面底色与卡片色取设计系统里那一对（246/30 与 255/40）。
    private var macForm: some View {
        @Bindable var model = model

        return MacSettingsPage {
            MacSettingsGroup(
                title: "外观",
                footer: "只放大原生界面：分类栏、行条目、设置与列表里的文字和图标。窗口够宽时栏数会自动减少，免得摘要被挤没。网页内容由各服务自己排版，不跟随这里。"
            ) {
                MacSettingsRow(title: "界面缩放") {
                    Picker("界面缩放", selection: $model.settings.interfaceScale) {
                        ForEach(Self.interfaceScaleOptions, id: \.self) { value in
                            Text(Self.interfaceScaleTitle(value)).tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240.zmScaled(scale))
                    .accessibilityLabel("界面缩放")
                }
            }

            MacSettingsGroup(
                title: "接入方式",
                footer: model.settings.addressing.mode.hint + " 这里是所有服务共用的部分；单个服务和全局不一致时，到「服务与接入」里覆盖。修改后所有服务地址立即重算。"
            ) {
                MacSettingsRow(title: "地址形式") {
                    Picker("地址形式", selection: $model.settings.addressing.mode) {
                        ForEach(AddressMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 200.zmScaled(scale))
                    .accessibilityLabel("地址形式")
                }

                MacSettingsDivider()

                switch model.settings.addressing.mode {
                case .subdomain, .path:
                    MacSettingsRow(title: "基础域名") {
                        TextField("qfpqhyl.top", text: $model.settings.addressing.baseDomain)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 220.zmScaled(scale))
                            .accessibilityLabel("基础域名")
                    }
                case .port:
                    MacSettingsRow(title: "内网主机") {
                        TextField("192.168.1.10", text: $model.settings.addressing.lanHost)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 220.zmScaled(scale))
                            .accessibilityLabel("内网主机")
                    }
                }
            }

            MacSettingsGroup(
                title: "服务",
                footer: "点进任一服务即可配置它的地址覆盖、鉴权凭据、通知通道、本地提醒与首页显示——一个服务一页。关掉上面的开关后，服务行不再显示「离线可用」这类能力标签，只保留「未配置」等真正需要处理的提示。站外链接默认留在应用内加载，想用 Safari 时点页面里的「在浏览器打开」。"
            ) {
                MacSettingsLinkRow(
                    title: "服务与接入",
                    systemImage: "square.grid.2x2",
                    detail: "\(configuredCount)/\(ServiceCatalog.all.count) 可访问"
                ) {
                    route = .services
                }

                MacSettingsDivider()

                MacSettingsRow(title: "显示服务能力标签") {
                    Toggle("显示服务能力标签", isOn: $model.settings.showServiceCapabilityTags)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.zmRow(scale))
                        .accessibilityLabel("显示服务能力标签")
                }

                MacSettingsDivider()

                MacSettingsRow(title: "站外链接在应用内打开") {
                    Toggle("站外链接在应用内打开", isOn: $model.settings.keepExternalLinksInApp)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.zmRow(scale))
                        .accessibilityLabel("站外链接在应用内打开")
                }
            }

            MacSettingsGroup(
                title: "通知",
                footer: "通知走三条通道：页面内提醒直接桥接为系统通知；ntfy 主题与各应用的通知流由后台刷新拉取；配置中继后还可接收 APNs 推送并补齐漏收事件。各服务用哪条通道在它自己的配置页里选。"
            ) {
                MacSettingsRow(title: "授权状态") {
                    Text(model.notificationStatusText)
                        .foregroundStyle(.secondary)
                }

                if model.authorization == .notDetermined {
                    MacSettingsDivider()

                    MacSettingsButtonRow(title: "开启通知", systemImage: "bell.badge") {
                        Task { await model.requestNotificationPermission() }
                    }
                }

                MacSettingsDivider()

                MacSettingsRow(title: "后台刷新") {
                    Toggle("后台刷新", isOn: $model.settings.backgroundRefreshEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.zmRow(scale))
                        .accessibilityLabel("后台刷新")
                }

                MacSettingsDivider()

                MacSettingsRow(title: "待补发") {
                    Text("\(model.snapshot.pendingCount) 条")
                        .foregroundStyle(model.snapshot.pendingCount > 0 ? .orange : .secondary)
                }

                MacSettingsDivider()

                MacSettingsButtonRow(title: model.isSyncing ? "同步中…" : "立即同步", systemImage: "arrow.triangle.2.circlepath") {
                    model.syncNow(reason: "手动")
                }
                .disabled(model.isSyncing)
            }

            MacSettingsGroup(
                title: "ntfy 订阅",
                footer: "列出服务器上已有消息的主题，点一下即订阅。ntfy 的服务器地址与访问令牌在「服务与接入 → ntfy」里，不在这里重复填写。"
            ) {
                MacSettingsLinkRow(
                    title: "ntfy 主题",
                    systemImage: "bell.badge",
                    detail: model.ntfyTopics.isEmpty ? "未订阅" : "\(model.ntfyTopics.count) 个主题"
                ) {
                    route = .ntfy
                }
            }

            MacSettingsGroup(title: "演出提醒", footer: SettingsView.showFooter) {
                MacSettingsRow(title: "启用演出提醒") {
                    Toggle("启用演出提醒", isOn: $model.settings.showsEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.zmRow(scale))
                        .accessibilityLabel("启用演出提醒")
                }

                if model.settings.showsEnabled {
                    MacSettingsDivider()

                    MacSettingsRow(title: "提前提醒") {
                        HStack(spacing: 8) {
                            Text("\(model.settings.showsReminderLeadHours) 小时")
                                .foregroundStyle(.secondary)
                            Stepper(
                                "提前提醒",
                                value: $model.settings.showsReminderLeadHours,
                                in: 1...12
                            )
                            .labelsHidden()
                            .accessibilityLabel("提前提醒")
                        }
                    }

                    if model.mujianToken.isEmpty {
                        MacSettingsHint(text: "幕间访问令牌尚未填写：到「服务与接入 → 幕间」配置一次，演出提醒会直接复用该凭据。")
                    }

                    MacSettingsDivider()

                    MacSettingsRow(title: "从幕间拉取") {
                        Toggle("从幕间拉取", isOn: $model.settings.showsUseMujianAPI)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.zmRow(scale))
                            .accessibilityLabel("从幕间拉取")
                    }

                    MacSettingsDivider()

                    MacSettingsRow(title: "已缓存") {
                        Text("\(model.shows.count) 场")
                            .foregroundStyle(model.shows.isEmpty ? .secondary : .primary)
                    }

                    if let next = model.shows.first(where: { $0.startsAt > .now }) {
                        MacSettingsDivider()

                        MacSettingsRow(title: "下一场") {
                            Text("《\(next.name)》\(Self.clock(next.startsAt))")
                                .foregroundStyle(.secondary)
                        }
                    }

                    MacSettingsDivider()

                    MacSettingsButtonRow(title: "立即刷新", systemImage: "arrow.clockwise") {
                        Task { await model.refreshShows() }
                    }
                }
            }

            MacSettingsGroup(
                title: "推送中继（可选）",
                footer: "中继不属于任何单个应用，所以留在这里。服务见仓库 server/push-relay。不配置也能用：页面内通知与后台拉取不需要它，只是没有「应用被杀死时立即送达」的能力。"
            ) {
                MacSettingsRow(title: "推送中继地址") {
                    TextField("https://push.example.com", text: $model.settings.relayURL)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 240.zmScaled(scale))
                        .accessibilityLabel("推送中继地址")
                }

                MacSettingsDivider()

                MacSettingsStackRow {
                    SecretField(
                        title: "中继共享密钥",
                        key: .relay,
                        footer: "保存在系统钥匙串，随 X-Zhongmiao-Token 请求头发送。"
                    )
                }

                MacSettingsDivider()

                MacSettingsRow(title: "设备令牌") {
                    Text(model.pushToken.map { String($0.prefix(10)) + "…" } ?? "未注册")
                        .zmFont(.caption, design: .monospaced)
                        .foregroundStyle(.secondary)
                }

                if let pushError = model.pushError {
                    MacSettingsHint(text: pushError)
                }

                MacSettingsDivider()

                MacSettingsButtonRow(title: "重新注册推送", systemImage: "arrow.clockwise") {
                    model.registerForRemoteNotifications()
                    model.uploadPushToken()
                }
            }

            MacSettingsGroup(
                title: "诊断",
                footer: "批量检测全部服务的连通性、查看原生接入状态与运行日志。单个服务的检测在它自己的配置页里，不必来回跳。"
            ) {
                MacSettingsLinkRow(
                    title: "诊断与日志",
                    systemImage: "stethoscope",
                    detail: model.network.isOnline ? "在线" : "离线"
                ) {
                    route = .diagnostics
                }
            }

            MacSettingsGroup(
                title: "数据",
                footer: "清除网页数据会删掉各应用的 Service Worker 缓存与 Cookie，之后需要重新登录、联网重新缓存。"
            ) {
                MacSettingsRow(title: "收件箱容量") {
                    HStack(spacing: 8) {
                        Text("\(model.settings.inboxCapacity) 条")
                            .foregroundStyle(.secondary)
                        Stepper("收件箱容量", value: $model.settings.inboxCapacity, in: 100...2000, step: 100)
                            .labelsHidden()
                            .accessibilityLabel("收件箱容量")
                    }
                }

                MacSettingsDivider()

                MacSettingsRow(title: "冷启动回看") {
                    HStack(spacing: 8) {
                        Text("\(model.settings.lookbackHours) 小时")
                            .foregroundStyle(.secondary)
                        Stepper("冷启动回看", value: $model.settings.lookbackHours, in: 1...168)
                            .labelsHidden()
                            .accessibilityLabel("冷启动回看")
                    }
                }

                MacSettingsDivider()

                MacSettingsButtonRow(title: "清空收件箱", systemImage: "trash", role: .destructive) {
                    model.clearInbox()
                }
                .disabled(model.snapshot.items.isEmpty)

                MacSettingsDivider()

                MacSettingsButtonRow(title: "清除网页缓存与登录状态", systemImage: "externaldrive.badge.xmark", role: .destructive) {
                    showClearDataConfirm = true
                }
            }

            MacSettingsGroup(title: "关于") {
                MacSettingsRow(title: "版本") {
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }

                MacSettingsDivider()

                MacSettingsRow(title: "平台") {
                    Text(Platform.platformName)
                        .foregroundStyle(.secondary)
                }

                MacSettingsDivider()

                Text("众妙是自托管应用的聚合入口：一个壳、一套通知、一份地址配置。后端仍是各自的 Go 服务，数据不出内网。")
                    .zmFont(size: 11)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
        }
        .sheet(item: $route) { route in
            NavigationStack {
                destination(for: route)
            }
            // 工具栏挂在栈上而不是目的地：挂到目的地时，从列表 push 进单服务页会把
            // 「完成」一起带走，只剩下返回箭头，用户得先退一层才能关掉整个 sheet。
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { self.route = nil }
                }
            }
            .frame(minWidth: 760, minHeight: 560)
        }
    }

    @ViewBuilder
    private func destination(for route: SettingsRoute) -> some View {
        switch route {
        case .services:
            ServiceSettingsListView()
        case .ntfy:
            NtfyTopicsView()
        case .diagnostics:
            DiagnosticsView()
        }
    }
    #endif

    // MARK: - iOS

    #if os(iOS)
    private var iosForm: some View {
        @Bindable var model = model

        return Form {
            Section {
                Picker("地址形式", selection: $model.settings.addressing.mode) {
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
                footnote(model.settings.addressing.mode.hint + " 这里是所有服务共用的部分；单个服务和全局不一致时，到「服务与接入」里覆盖。修改后所有服务地址立即重算。")
            }

            Section {
                settingsLink(
                    "服务与接入",
                    systemImage: "square.grid.2x2",
                    detail: "\(configuredCount)/\(ServiceCatalog.all.count) 可访问"
                ) {
                    ServiceSettingsListView()
                }

                Toggle("显示服务能力标签", isOn: $model.settings.showServiceCapabilityTags)
                Toggle("站外链接在应用内打开", isOn: $model.settings.keepExternalLinksInApp)
            } header: {
                Text("服务")
            } footer: {
                footnote("点进任一服务即可配置它的地址覆盖、鉴权凭据、通知通道、本地提醒与首页显示——一个服务一页。关掉上面的开关后，应用卡片不再显示「离线可用」这类能力标签，只保留「未配置」等真正需要处理的提示。站外链接默认留在应用内加载，想用 Safari 时点页面里的「在浏览器打开」；`tel:`、`mailto:` 这类始终交给系统。")
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
                footnote("通知走三条通道：页面内提醒直接桥接为系统通知；ntfy 主题与各应用的通知流由后台刷新拉取；配置中继后还可接收 APNs 推送并补齐漏收事件。各服务用哪条通道在它自己的配置页里选。")
            }

            Section {
                settingsLink(
                    "ntfy 主题",
                    systemImage: "bell.badge",
                    detail: model.ntfyTopics.isEmpty ? "未订阅" : "\(model.ntfyTopics.count) 个主题"
                ) {
                    NtfyTopicsView()
                }
            } header: {
                Text("ntfy 订阅")
            } footer: {
                footnote("列出服务器上已有消息的主题，点一下即订阅。ntfy 的服务器地址与访问令牌在「服务与接入 → ntfy」里，不在这里重复填写。")
            }

            Section {
                Toggle("启用演出提醒", isOn: $model.settings.showsEnabled)

                if model.settings.showsEnabled {
                    Stepper(value: $model.settings.showsReminderLeadHours, in: 1...12) {
                        Text("提前提醒：\(model.settings.showsReminderLeadHours) 小时")
                    }

                    Stepper(value: $model.settings.showsIslandLeadHours, in: 1...8) {
                        Text("灵动岛提前量：\(model.settings.showsIslandLeadHours) 小时")
                    }

                    if model.mujianToken.isEmpty {
                        footnote("幕间访问令牌尚未填写：到「服务与接入 → 幕间」配置一次，演出提醒会直接复用该凭据。")
                            .foregroundStyle(.orange)
                    }

                    Toggle("从幕间拉取", isOn: $model.settings.showsUseMujianAPI)

                    Toggle("读取系统日历", isOn: calendarAccessBinding)

                    if let notice = model.calendarAccessNotice {
                        footnote(notice)
                            .foregroundStyle(.orange)
                    }

                    TextField("日历关键词（逗号分隔）", text: $model.settings.showsCalendarKeywords)
                        .zmPlainTextInput()

                    LabeledContent("已缓存") {
                        Text("\(model.shows.count) 场")
                            .foregroundStyle(model.shows.isEmpty ? .secondary : .primary)
                    }

                    Picker("新闹钟提前", selection: $model.settings.showsAlarmLeadMinutes) {
                        ForEach(ShowAlarm.leadOptions, id: \.self) { minutes in
                            Text("\(minutes) 分钟").tag(minutes)
                        }
                    }

                    LabeledContent("开演闹钟") {
                        Text("\(model.showAlarms.count) / \(ShowAlarm.maxConcurrent)")
                            .foregroundStyle(model.showAlarms.count == 0 ? .secondary : .primary)
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
                footnote(SettingsView.showFooter)
            }

            Section {
                TextField("推送中继地址", text: $model.settings.relayURL)
                    .zmPlainTextInput()
                    .keyboardType(.URL)

                SecretField(
                    title: "中继共享密钥",
                    key: .relay,
                    footer: "保存在系统钥匙串，随 X-Zhongmiao-Token 请求头发送。"
                )

                LabeledContent("设备令牌") {
                    Text(model.pushToken.map { String($0.prefix(10)) + "…" } ?? "未注册")
                        .zmFont(.caption, design: .monospaced)
                        .foregroundStyle(.secondary)
                }

                if let pushError = model.pushError {
                    footnote(pushError)
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
                footnote("中继不属于任何单个应用，所以留在这里。服务见仓库 server/push-relay。不配置也能用：页面内通知与后台拉取不需要它，只是没有「应用被杀死时立即送达」的能力。")
            }

            Section {
                settingsLink(
                    "诊断与日志",
                    systemImage: "stethoscope",
                    detail: model.network.isOnline ? "在线" : "离线"
                ) {
                    DiagnosticsView()
                }
            } header: {
                Text("诊断")
            } footer: {
                footnote("批量检测全部服务的连通性、查看原生接入状态与运行日志。单个服务的检测在它自己的配置页里，不必来回跳。")
            }

            Section {
                Stepper(value: $model.settings.inboxCapacity, in: 100...2000, step: 100) {
                    Text("收件箱容量：\(model.settings.inboxCapacity) 条")
                }

                Stepper(value: $model.settings.lookbackHours, in: 1...168) {
                    Text("冷启动回看：\(model.settings.lookbackHours) 小时")
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
                footnote("清除网页数据会删掉各应用的 Service Worker 缓存与 Cookie，之后需要重新登录、联网重新缓存。")
            }

            Section {
                LabeledContent("版本", value: appVersion)
                LabeledContent("平台", value: Platform.platformName)
                footnote("众妙是自托管应用的聚合入口：一个壳、一套通知、一份地址配置。后端仍是各自的 Go 服务，数据不出内网。")
            } header: {
                Text("关于")
            }
        }
    }
    #endif

    // MARK: - 行

    /// 分组底部的说明文字。长句要给 `fixedSize` 才会按可用宽度折行。
    private func footnote(_ text: String) -> some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
    }

    #if os(iOS)
    /// 跳到二级页的一行。
    private func settingsLink<Destination: View>(
        _ title: String,
        systemImage: String,
        detail: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            LabeledContent {
                Text(detail)
                    .foregroundStyle(.secondary)
            } label: {
                Label(title, systemImage: systemImage)
            }
        }
    }
    #endif

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

    /// 四档缩放：100% 与系统字号一致，往上每档加 15%。
    /// 四档已经覆盖 4K 屏幕上「小到看不清」到「再大就挤」的区间。
    static let interfaceScaleOptions: [Double] = [1, 1.15, 1.3, 1.45]

    static func interfaceScaleTitle(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    // MARK: 演出提醒

    #if os(iOS)
    /// 只有用户主动打开时才申请日历读取权限；被拒就保持关闭并给出原因，
    /// 避免出现「开关开着但读不到」的假状态。
    private var calendarAccessBinding: Binding<Bool> {
        Binding(
            get: { model.settings.showsUseCalendar },
            set: { newValue in
                guard newValue else {
                    model.calendarAccessNotice = nil
                    model.updateSettings { $0.showsUseCalendar = false }
                    return
                }
                Task {
                    guard await CalendarShowSource.requestAccess() else {
                        model.calendarAccessNotice = "没有拿到日历权限，开关保持关闭。请到「设置 → 隐私与安全性 → 日历」允许众妙访问后再打开。"
                        return
                    }
                    model.calendarAccessNotice = nil
                    model.updateSettings { $0.showsUseCalendar = true }
                }
            }
        )
    }
    #endif

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
        "演出时间取自幕间；「读取系统日历」默认关闭，打开时才申请一次日历读取权限，用系统日历里「幕间」同步过去的事件兜底。提醒走本地通知，App 被杀也照常到点。灵动岛最多常驻 8 小时，而 iOS 不允许 App 在精确时刻自己启动，所以要建两个快捷指令自动化（每天 10:00、15:00）跑「开启演出盯场」；演出前打开众妙也会自动开岛。开演闹钟是另一条通道：默认一场都不开，在演出详情里逐场打开后由系统持有，会覆盖静音与专注模式。幕间访问令牌在「服务与接入 → 幕间」里填写，这里读的就是那一份。"
        #else
        "演出时间取自幕间。提醒走本地通知，即便 App 已退出也照常到点。幕间访问令牌在「服务与接入 → 幕间」里填写，这里读的就是那一份。"
        #endif
    }
}

#if os(macOS)
/// 设置页内的二级页。macOS 上用 sheet 打开：主窗口顶部被 TabView 的标签占着，
/// push 出来的系统返回按钮会和它抢位置，不如一个明确的「完成」。
enum SettingsRoute: Hashable, Identifiable {
    case services
    case ntfy
    case diagnostics

    var id: Self { self }
}
#endif
