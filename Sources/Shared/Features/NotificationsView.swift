import SwiftUI
import UserNotifications
import ZhongmiaoCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct NotificationsView: View {

    @Environment(AppModel.self) private var model
    @State private var filterServiceID: String?

    var body: some View {
        List {
            if model.authorization == .notDetermined || model.authorization == .denied {
                permissionSection
            }

            if let filterServiceID {
                Section {
                    HStack {
                        Label(
                            "仅显示 \(ServiceDisplay.name(for: filterServiceID))",
                            systemImage: "line.3.horizontal.decrease.circle"
                        )
                        .zmFont(.footnote)
                        Spacer()
                        Button("查看全部") { self.filterServiceID = nil }
                            .zmFont(.footnote)
                    }
                }
            }

            if filterServiceID == nil, !appSummaries.isEmpty {
                Section {
                    ForEach(appSummaries) { summary in
                        Button {
                            filterServiceID = summary.id
                        } label: {
                            summaryRow(summary)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("按应用")
                } footer: {
                    Text("点一个应用只看它的通知；未读数计入全部未读。")
                }
            }

            if model.snapshot.items.isEmpty {
                Section {
                    EmptyStateView(
                        symbol: "bell.slash",
                        title: "还没有通知",
                        message: "应用的通知、ntfy 告警、以及页面内的提醒都会汇总到这里。离线期间收到的会在恢复网络后补发。还没配数据源的，可到「设置 → ntfy 主题」浏览服务器主题并一键订阅。",
                        actionTitle: model.authorization == .notDetermined ? "开启通知" : nil,
                        action: model.authorization == .notDetermined ? {
                            Task { await model.requestNotificationPermission() }
                        } : nil
                    )
                    .listRowBackground(Color.clear)
                }
            } else if filteredItems.isEmpty, let filterServiceID {
                Section {
                    EmptyStateView(
                        symbol: "line.3.horizontal.decrease.circle",
                        title: "当前筛选没有通知",
                        message: "「\(ServiceDisplay.name(for: filterServiceID))」暂时没有通知。",
                        actionTitle: "查看全部",
                        action: { self.filterServiceID = nil }
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(groupedDays, id: \.day) { group in
                    Section(RelativeTime.dayHeader(group.day)) {
                        ForEach(group.items) { item in
                            row(item)
                        }
                    }
                }
            }
        }
        .navigationTitle("通知")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("筛选", selection: $filterServiceID) {
                        Text("全部应用").tag(String?.none)
                        ForEach(activeSources) { source in
                            Text(source.name).tag(String?.some(source.id))
                        }
                    }

                    Divider()

                    Button {
                        guard filteredUnreadCount > 0 else { return }
                        model.markAllRead(serviceID: filterServiceID)
                        model.toast = "已全部标记为已读"
                    } label: {
                        Label(
                            filteredUnreadCount > 0 ? "全部标为已读（\(filteredUnreadCount)）" : "没有未读",
                            systemImage: "checkmark.circle"
                        )
                    }
                    .disabled(filteredUnreadCount == 0)

                    Button {
                        model.syncNow(reason: "手动")
                    } label: {
                        Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("筛选与批量操作")
            }
        }
        .refreshable {
            model.syncNow(reason: "下拉刷新")
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
    }

    // MARK: - 权限

    @ViewBuilder
    private var permissionSection: some View {
        Section {
            if model.authorization == .notDetermined {
                Button {
                    Task { await model.requestNotificationPermission() }
                } label: {
                    Label("开启通知，离线也能补发", systemImage: "bell.badge")
                }
            } else {
                Button {
                    openSystemSettings()
                } label: {
                    Label("通知已被关闭，去系统设置开启", systemImage: "exclamationmark.triangle")
                }
            }
        } footer: {
            Text(
                model.authorization == .notDetermined
                    ? "授权后，即使 App 在后台，各应用的事件也会通过推送或后台刷新送达；暂时收不到的通知会在恢复后补发。"
                    : "系统已关闭众妙的通知权限，收件箱仍会记录事件，但不会弹窗提醒。"
            )
        }
    }

    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    // MARK: - 行

    @ViewBuilder
    private func row(_ item: NotificationItem) -> some View {
        Button {
            model.openNotification(item)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                if let service = ServiceDisplay.glyph(for: item.serviceID) {
                    ServiceGlyph(service: service, size: 30)
                } else {
                    Image(systemName: "bell")
                        .zmFont(size: 13)
                        .frame(width: 30, height: 30)
                        .background(Color.zmCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.title)
                            .zmFont(.subheadline, weight: item.isRead ? .regular : .semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer(minLength: 6)
                        Text(RelativeTime.short(item.createdAt))
                            .zmFont(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if !item.body.isEmpty {
                        Text(item.body)
                            .zmFont(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 6) {
                        Text(ServiceDisplay.name(for: item.serviceID))
                            .zmFont(.caption2)
                            .foregroundStyle(.secondary)
                        if item.deliveredAt == nil {
                            CapsuleTag(text: "待补发", systemImage: "clock.arrow.circlepath", tint: .orange)
                        }
                        if item.priority == .timeSensitive {
                            CapsuleTag(text: "时效", systemImage: "bolt.fill", tint: .red)
                        }
                    }
                }

                if !item.isRead {
                    Circle()
                        .fill(.tint)
                        .frame(width: 7, height: 7)
                        .padding(.top, 6)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityValue(item.isRead ? "已读" : "未读")
        }
        .buttonStyle(.plain)
        #if os(macOS)
        // 没有触控板时横扫轨迹短、易误触，右键菜单才是删除与已读的主入口。
        .contextMenu {
            Button {
                model.markRead(item)
            } label: {
                Label("标为已读", systemImage: "checkmark.circle")
            }
            .disabled(item.isRead)

            Button(role: .destructive) {
                model.delete(item)
            } label: {
                Label("删除", systemImage: "trash")
            }

            Divider()

            Button {
                model.openNotification(item)
            } label: {
                Label("在该应用中打开", systemImage: "arrow.up.forward.app")
            }
        }
        #endif
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                model.delete(item)
            } label: {
                Label("删除", systemImage: "trash")
            }

            if !item.isRead {
                Button {
                    model.markRead(item)
                } label: {
                    Label("已读", systemImage: "checkmark")
                }
                .tint(.accentColor)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title)，来自\(ServiceDisplay.name(for: item.serviceID))")
        .accessibilityValue(item.isRead ? "已读" : "未读")
        .accessibilityHint("打开对应应用")
    }

    // MARK: - 数据

    /// 筛选菜单的条目：应用与独立订阅的 ntfy 主题统一按来源 id 展示。
    private struct SourceEntry: Identifiable, Hashable {
        let id: String
        let name: String
    }

    private var activeSources: [SourceEntry] {
        Set(model.snapshot.items.map(\.serviceID))
            .map { SourceEntry(id: $0, name: ServiceDisplay.name(for: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var filteredItems: [NotificationItem] {
        let items = model.snapshot.items
        guard let filterServiceID else { return items }
        return items.filter { $0.serviceID == filterServiceID }
    }

    /// 按应用汇总：未读多的在前，同一未读量按最近一条排序。
    private struct AppSummary: Identifiable {
        let id: String
        let name: String
        let unread: Int
        let latest: NotificationItem
    }

    private var appSummaries: [AppSummary] {
        Dictionary(grouping: model.snapshot.items, by: \.serviceID)
            .compactMap { entry -> AppSummary? in
                let items = entry.value
                guard let latest = items.max(by: { $0.createdAt < $1.createdAt }) else { return nil }
                return AppSummary(
                    id: entry.key,
                    name: ServiceDisplay.name(for: entry.key),
                    unread: items.lazy.filter { !$0.isRead }.count,
                    latest: latest
                )
            }
            .sorted { lhs, rhs in
                if lhs.unread != rhs.unread { return lhs.unread > rhs.unread }
                return lhs.latest.createdAt > rhs.latest.createdAt
            }
    }

    private func summaryRow(_ summary: AppSummary) -> some View {
        HStack(spacing: 10) {
            if let service = ServiceDisplay.glyph(for: summary.id) {
                ServiceGlyph(service: service, size: 26)
            } else {
                Image(systemName: "bell")
                    .zmFont(size: 12)
                    .frame(width: 26, height: 26)
                    .background(Color.zmCard, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(summary.name)
                        .zmFont(.subheadline, weight: summary.unread > 0 ? .semibold : .regular)
                        .foregroundStyle(.primary)
                    if summary.unread > 0 {
                        Text("\(summary.unread)")
                            .zmFont(.caption2, weight: .bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.red, in: Capsule())
                            .accessibilityLabel("\(summary.unread) 条未读")
                    }
                    Spacer(minLength: 4)
                    Text(RelativeTime.short(summary.latest.createdAt))
                        .zmFont(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(summary.latest.title)
                    .zmFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Image(systemName: "chevron.right")
                .zmFont(.caption2, weight: .semibold)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.name)，\(summary.unread) 条未读，最近一条：\(summary.latest.title)")
        .accessibilityHint("只看这个应用的通知")
    }

    /// 批量操作只针对当前可见范围，避免“按钮可点但没有任何变化”。
    private var filteredUnreadCount: Int {
        filteredItems.lazy.filter { !$0.isRead }.count
    }

    private var groupedDays: [(day: Date, items: [NotificationItem])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredItems) { calendar.startOfDay(for: $0.createdAt) }
        return groups
            .map { (day: $0.key, items: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.day > $1.day }
    }
}
