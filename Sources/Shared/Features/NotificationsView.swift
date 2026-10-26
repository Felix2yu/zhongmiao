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
                        model.markAllRead(serviceID: filterServiceID)
                        model.toast = "已全部标记为已读"
                    } label: {
                        Label("全部标为已读", systemImage: "checkmark.circle")
                    }
                    .disabled(model.snapshot.unreadCount == 0)

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
                        .font(.system(size: 13))
                        .frame(width: 30, height: 30)
                        .background(Color.zmCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.title)
                            .font(.subheadline.weight(item.isRead ? .regular : .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer(minLength: 6)
                        Text(RelativeTime.short(item.createdAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if !item.body.isEmpty {
                        Text(item.body)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 6) {
                        Text(ServiceDisplay.name(for: item.serviceID))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
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
        }
        .buttonStyle(.plain)
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

    private var groupedDays: [(day: Date, items: [NotificationItem])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredItems) { calendar.startOfDay(for: $0.createdAt) }
        return groups
            .map { (day: $0.key, items: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.day > $1.day }
    }
}
