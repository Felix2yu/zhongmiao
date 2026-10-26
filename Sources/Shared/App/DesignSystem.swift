import SwiftUI
import ZhongmiaoCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - 颜色

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: Double
        switch cleaned.count {
        case 3:
            r = Double((value >> 8) & 0xF) / 15
            g = Double((value >> 4) & 0xF) / 15
            b = Double(value & 0xF) / 15
        default:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// 分组列表背景（跨平台语义色）。
    static var zmGrouped: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// 卡片背景（跨平台语义色）。
    static var zmCard: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

// MARK: - 服务图标

/// 统一的方形图标：色块 + SF Symbol。
/// 不依赖网络图片，避免离线时出现空白占位。
struct ServiceGlyph: View {
    let service: ServiceDefinition
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: service.tint).opacity(0.95),
                        Color(hex: service.tint).opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: service.symbol)
                    .font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - 小标签

struct CapsuleTag: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(tint)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

// MARK: - 离线横幅

struct OfflineBanner: View {
    let text: String
    var showsProgress = false

    var body: some View {
        HStack(spacing: 8) {
            if showsProgress {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: "wifi.slash")
                    .font(.footnote.weight(.semibold))
            }
            Text(text)
                .font(.footnote)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 加载错误视图

struct LoadFailureView: View {
    let title: String
    let detail: String
    let retry: () -> Void
    var openInBrowser: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("重试", action: retry)
                    .buttonStyle(.borderedProminent)
                if let openInBrowser {
                    Button("在浏览器打开", action: openInBrowser)
                        .buttonStyle(.bordered)
                }
            }
            .padding(.top, 2)
        }
        .padding(28)
        .frame(maxWidth: 420)
    }
}

// MARK: - 时间格式化

enum RelativeTime {
    static func short(_ date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86_400 { return "\(Int(interval / 3600)) 小时前" }
        if interval < 7 * 86_400 { return "\(Int(interval / 86_400)) 天前" }
        return date.formatted(.dateTime.year().month().day())
    }

    static func dayHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.month().day().weekday(.abbreviated))
    }
}

// MARK: - 跨平台输入修饰

extension View {
    /// 地址/标识类输入：不自动大写、不自动纠错（macOS 没有大写相关的修饰符）。
    @ViewBuilder
    func zmPlainTextInput() -> some View {
        #if os(iOS)
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }
}
