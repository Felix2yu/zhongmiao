#if os(macOS)
import SwiftUI

/// macOS 设置页的外壳：一栏居中、固定行长。
///
/// 不用 `Form`：macOS 的 grouped Form 那层「卡片」是系统绘制的，暗色下与页面底色
/// 只差 7 阶（页面 30 / 卡片 37）、亮色下卡片反而比页面更深（238 / 246），
/// 分组立不起来。这里改用设计系统里同一对颜色（页面 246/30、卡片 255/40）自绘。
struct MacSettingsPage<Content: View>: View {

    @ViewBuilder var content: Content

    @Environment(\.interfaceScale) private var scale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22.zmScaled(scale)) {
                content
            }
            .frame(maxWidth: 700.zmScaled(scale), alignment: .leading)
            .padding(.horizontal, 24.zmScaled(scale))
            .padding(.top, 22.zmScaled(scale))
            .padding(.bottom, 32.zmScaled(scale))
            .frame(maxWidth: .infinity)
        }
        .background(Color.zmGrouped)
    }
}

/// 一个设置分组：灰字标题 + 圆角卡片 + 卡片下方的说明。
struct MacSettingsGroup<Content: View>: View {

    let title: String
    var footer: String = ""
    @ViewBuilder var content: Content

    @Environment(\.interfaceScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 6.zmScaled(scale)) {
            Text(title)
                .zmFont(size: 11, weight: .semibold)
                .foregroundStyle(.secondary)
                .padding(.leading, 10.zmScaled(scale))

            VStack(spacing: 0) {
                content
            }
            .padding(.vertical, 3.zmScaled(scale))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.zmCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }

            if !footer.isEmpty {
                Text(footer)
                    .zmFont(size: 11)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10.zmScaled(scale))
            }
        }
    }
}

/// 组内的一行：左边标题、右边控件。行高与左右留白对齐系统设置。
///
/// `fillsWidth` 给输入框这类要吃掉剩余宽度的控件：此时不再插 `Spacer`，
/// 否则输入框永远只有内在宽度，长地址会被截断。
struct MacSettingsRow<Control: View>: View {

    var title: String? = nil
    var fillsWidth = false
    @ViewBuilder var control: Control

    @Environment(\.interfaceScale) private var scale

    var body: some View {
        HStack(spacing: 12.zmScaled(scale)) {
            if let title {
                Text(title)
                    .fixedSize()
            }
            if !fillsWidth {
                Spacer(minLength: 8)
            }
            control
        }
        .padding(.horizontal, 14.zmScaled(scale))
        .padding(.vertical, 5.zmScaled(scale))
        .frame(minHeight: 32.zmScaled(scale))
    }
}

/// 行间分隔线。缩进与标题对齐，右端留 14 与控件对齐。
struct MacSettingsDivider: View {

    @Environment(\.interfaceScale) private var scale

    var body: some View {
        Divider()
            .padding(.leading, 14.zmScaled(scale))
            .padding(.trailing, 14.zmScaled(scale))
    }
}

/// 可点击的跳转行：整行热区、悬停微亮、右侧箭头。
struct MacSettingsLinkRow: View {

    let title: String
    let systemImage: String
    let detail: String
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.interfaceScale) private var scale

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8.zmScaled(scale)) {
                Label(title, systemImage: systemImage)
                Spacer(minLength: 8)
                Text(detail)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .zmFont(size: 10, weight: .semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14.zmScaled(scale))
            .padding(.vertical, 5.zmScaled(scale))
            .frame(minHeight: 32.zmScaled(scale))
            .background(hovering ? Color.primary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 自绘的 label 是一棵视图树，AX 里这层按钮拿不到标题，VoiceOver 只会念「按钮」。
        .accessibilityLabel(Text("\(title)，\(detail)"))
        .onHover { hovering = $0 }
    }
}

/// 组内的一条提醒（缺令牌、权限被拒这类），橙色小字。
struct MacSettingsHint: View {

    let text: String

    @Environment(\.interfaceScale) private var scale

    var body: some View {
        Text(text)
            .zmFont(size: 11)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14.zmScaled(scale))
            .padding(.vertical, 4.zmScaled(scale))
    }
}

/// 组内的按钮行。系统设置里按钮是独立一行、左对齐。
struct MacSettingsButtonRow: View {

    let title: String
    var systemImage: String? = nil
    var role: ButtonRole? = nil
    let action: () -> Void

    @Environment(\.interfaceScale) private var scale

    var body: some View {
        HStack(spacing: 0) {
            Button(role: role, action: action) {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .controlSize(.zmRow(scale))
            .zmPushButton(role: role)
            .accessibilityLabel(Text(title))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14.zmScaled(scale))
        .padding(.vertical, 5.zmScaled(scale))
        .frame(minHeight: 32.zmScaled(scale))
    }
}

/// 组内的一整行自定义内容：说明、能力清单、图标 + 标题这类没有「右侧控件」的行。
struct MacSettingsStackRow<Content: View>: View {

    @ViewBuilder var content: Content

    @Environment(\.interfaceScale) private var scale

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14.zmScaled(scale))
            .padding(.vertical, 6.zmScaled(scale))
            .frame(minHeight: 32.zmScaled(scale))
    }
}

/// 跳进行内的下一页（与 `MacSettingsLinkRow` 外观一致，但由 `NavigationLink` 驱动）。
struct MacSettingsNavigationRow<Destination: View>: View {

    let title: String
    let systemImage: String
    var detail: String = ""
    @ViewBuilder var destination: Destination

    @Environment(\.interfaceScale) private var scale
    @State private var hovering = false

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 8.zmScaled(scale)) {
                Label(title, systemImage: systemImage)
                Spacer(minLength: 8)
                if !detail.isEmpty {
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .zmFont(size: 10, weight: .semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14.zmScaled(scale))
            .padding(.vertical, 5.zmScaled(scale))
            .frame(minHeight: 32.zmScaled(scale))
            .background(hovering ? Color.primary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .onHover { hovering = $0 }
    }
}

// MARK: - 按钮

/// macOS 的操作按钮。
///
/// 系统的 `.bordered` 在 macOS 26 上是液态玻璃：叠在深色卡片上只剩一层几乎透明的底，
/// 看上去就是一行彩色文字——也就是「按钮都是扁的」。这里自己画中性底色 + 0.5pt 描边，
/// 悬停微亮、按下加深，暗亮两套主题都不依赖材质，边界始终看得见。
struct ZMPushButtonStyle: ButtonStyle {

    var role: ButtonRole?

    func makeBody(configuration: Configuration) -> some View {
        PushBody(configuration: configuration, role: role)
    }

    private struct PushBody: View {

        let configuration: Configuration
        let role: ButtonRole?

        @Environment(\.interfaceScale) private var scale
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        private var isDestructive: Bool { role == .destructive }
        private var corner: CGFloat { 6.zmScaled(scale) }

        private var fillOpacity: Double {
            if configuration.isPressed { return 0.20 }
            return hovering ? 0.13 : 0.08
        }

        var body: some View {
            configuration.label
                .foregroundStyle(isDestructive ? Color.red : Color.primary)
                .padding(.horizontal, 10.zmScaled(scale))
                .padding(.vertical, 4.zmScaled(scale))
                .background(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(Color.primary.opacity(fillOpacity))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 0.5)
                }
                .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovering = $0 }
        }
    }
}

extension View {
    /// 设置类界面里的操作按钮统一走这个样式。
    func zmPushButton(role: ButtonRole? = nil) -> some View {
        buttonStyle(ZMPushButtonStyle(role: role))
    }
}
#endif
