import ActivityKit
import SwiftUI
import WidgetKit
import ZhongmiaoCore

@main
struct ZhongmiaoWidgetBundle: WidgetBundle {
    var body: some Widget {
        ShowActivityWidget()
    }
}

/// 演出实时活动：锁屏卡片 + 灵动岛。
///
/// 这个 target 只依赖 `ZhongmiaoCore`，属性值类型与主 App 共用同一份定义
/// （ActivityKit 要求两侧类型完全一致）。
///
/// 两个硬约束写在前面，改 UI 时别踩：
/// 1. 实时活动**不能联网、不能定位**，所有数据必须来自开岛时传入的 attributes / state；
/// 2. 整份载荷上限 4KB，所以不放封面图，连座位都只在有值时才写进 state。
struct ShowActivityWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShowActivityAttributes.self) { context in
            LockScreenShowView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color(red: 0.16, green: 0.10, blue: 0.24))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.name)
                            .font(.headline)
                            .lineLimit(1)
                        if let venue = context.attributes.venue, !venue.isEmpty {
                            Text(venue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownView(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    BottomRowView(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                Image(systemName: "theatermasks")
                    .foregroundStyle(.purple)
            } compactTrailing: {
                // `style: .timer` 由系统自行刷新，不消耗 App 的任何后台时间。
                Text(context.attributes.startsAt, style: .timer)
                    .monospacedDigit()
                    .foregroundStyle(.purple)
            } minimal: {
                Image(systemName: "theatermasks")
                    .foregroundStyle(.purple)
            }
        }
    }
}

// MARK: - 锁屏

private struct LockScreenShowView: View {
    let attributes: ShowActivityAttributes
    let state: ShowActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "theatermasks")
                .font(.title2)
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 3) {
                Text(attributes.name)
                    .font(.headline)
                    .lineLimit(2)

                if let venue = attributes.venue, !venue.isEmpty {
                    Text(venue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                CountdownView(attributes: attributes, state: state)
                    .font(.subheadline.weight(.medium))
            }

            Spacer(minLength: 0)

            if let seat = attributes.seat, !seat.isEmpty {
                Text(seat)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.purple.opacity(0.25), in: .capsule)
            }
        }
        .padding(12)
    }
}

// MARK: - 岛内片段

/// 倒计时。三态共用这一个视图，避免四处各写一份判断。
private struct CountdownView: View {
    let attributes: ShowActivityAttributes
    let state: ShowActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .scheduled:
            HStack(spacing: 4) {
                Text("距开演")
                Text(attributes.startsAt, style: .timer)
            }
            .monospacedDigit()
            .foregroundStyle(.primary)
        case .ongoing:
            // 没有填时长的演出给不出散场倒计时，只能说「演出中」。
            Group {
                if let endsAt = state.endsAt {
                    HStack(spacing: 4) {
                        Text("距散场")
                        Text(endsAt, style: .timer)
                    }
                    .monospacedDigit()
                } else {
                    Text("演出中")
                }
            }
            .foregroundStyle(.orange)
        case .ended:
            Text("已结束")
                .foregroundStyle(.secondary)
        }
    }
}

/// 展开态底栏：座位与开演时刻，都是开岛时就定死的静态信息。
private struct BottomRowView: View {
    let attributes: ShowActivityAttributes
    let state: ShowActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 10) {
            Label(ShowActivityWidget.clock(attributes.startsAt), systemImage: "clock")
            if let seat = attributes.seat, !seat.isEmpty {
                Label(seat, systemImage: "seat")
            }
            Spacer(minLength: 0)
            Text(state.phase.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

extension ShowActivityWidget {
    static func clock(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return String(format: "%d:%02d", hour, minute)
    }
}

extension ShowPhase {
    var title: String {
        switch self {
        case .scheduled: "待开演"
        case .ongoing: "演出中"
        case .ended: "已结束"
        }
    }
}
