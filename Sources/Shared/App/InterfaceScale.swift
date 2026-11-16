import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - 界面缩放

/// 界面缩放倍数（1 为标准，1.15 / 1.3 / 1.45 逐档放大）。
///
/// 为什么不是 `dynamicTypeSize`：macOS 上 SwiftUI 的语义字号**不响应**动态字体。
/// 实测 `.font(.body).dynamicTypeSize(.accessibility3)` 与默认渲染出来的
/// 「中文示例 Abc」都是 79×16，一像素不差；系统那套按 App 调字号的能力也不在
/// App 的控制范围内。所以缩放只能自己按倍数重算字号与度量。
///
/// 影响范围：原生壳层（分类栏、行条目、设置卡片、文本与 SF Symbol 图标）。
/// 网页内容不跟随——各服务的页面有自己的响应式排版，整页缩放会变成横向滚动，
/// 而 SwiftUI 的 `WebPage`（iOS 26 / macOS 26 新接口）也没有暴露 pageZoom。
private struct InterfaceScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var interfaceScale: CGFloat {
        get { self[InterfaceScaleKey.self] }
        set { self[InterfaceScaleKey.self] = newValue }
    }
}

extension CGFloat {
    /// 布局度量按倍数放大并取整，避免出现 50.6 这类半像素、描边与分隔线发虚。
    func zmScaled(_ scale: CGFloat) -> CGFloat {
        scale == 1 ? self : (self * scale).rounded()
    }
}

// 字面量写 `12.zmScaled(scale)` 时 Swift 会先当 Int，补上这一组省掉满篇 `CGFloat(12)`。
extension Int {
    func zmScaled(_ scale: CGFloat) -> CGFloat { CGFloat(self).zmScaled(scale) }
}

extension Double {
    func zmScaled(_ scale: CGFloat) -> CGFloat { CGFloat(self).zmScaled(scale) }
}

extension ControlSize {
    /// 系统控件（开关、下拉、步进器、按钮）没有字号可改，只能换档：
    /// 小 / 常规 / 大 / 超大。跟着界面缩放走，免得行里的字变大了控件还是原样。
    static func zm(_ scale: CGFloat) -> ControlSize {
        if scale >= 1.35 { return .extraLarge }
        if scale >= 1.12 { return .large }
        return .regular
    }

    /// 设置行里的控件：标准档保持原来的紧凑尺寸，放大后跟着档位走。
    static func zmRow(_ scale: CGFloat) -> ControlSize {
        scale > 1 ? zm(scale) : .small
    }
}

extension View {
    /// 把界面缩放注入整棵子树：字号、布局度量、系统控件档位。
    /// 三个窗口（主窗口、设置、诊断）都在根上套一次。
    func zmInterfaceScale(_ scale: CGFloat) -> some View {
        self
            .environment(\.interfaceScale, scale)
            .controlSize(.zm(scale))
    }
}

// MARK: - 语义字号基线

/// macOS 语义字号的真实取值。
///
/// SwiftUI 在 macOS 上把 `.body`/`.caption` 这些样式映射到
/// `NSFont.preferredFont(forTextStyle:)`：body 13、callout 12、subheadline 11、
/// footnote 10、caption 10、caption2 10（medium）、title3 15、title2 17、
/// title 22、headline 13（bold）。缩放后仍用 `Font.system(size:weight:)` 还原，
/// 1 倍时与原来的语义字体逐像素一致（已用 `fittingSize` 对照过）。
enum Typography {

    #if os(macOS)
    static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        NSFont.preferredFont(forTextStyle: nsStyle(style)).pointSize
    }

    /// 语义样式自带的基础字重：headline 粗体、caption2 中粗，其余常规。
    static func defaultWeight(_ style: Font.TextStyle) -> Font.Weight {
        switch style {
        case .headline: .bold
        case .caption2: .medium
        default: .regular
        }
    }

    private static func nsStyle(_ style: Font.TextStyle) -> NSFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
    #endif
}

// MARK: - 修饰符

private struct ZmFontModifier: ViewModifier {

    var style: Font.TextStyle?
    var size: CGFloat?
    var weight: Font.Weight?
    var design: Font.Design?
    var monospacedDigit: Bool

    @Environment(\.interfaceScale) private var scale

    func body(content: Content) -> some View {
        content.font(resolved)
    }

    private var resolved: Font {
        #if os(iOS)
        // iOS 本身有动态字体，交给系统，不叠自己的倍数。
        var font: Font
        if let style {
            font = Font.system(style, design: design, weight: weight)
        } else {
            font = Font.system(size: size ?? 13, weight: weight ?? .regular, design: design ?? .default)
        }
        if monospacedDigit { font = font.monospacedDigit() }
        return font
        #else
        let baseSize: CGFloat
        let baseWeight: Font.Weight
        if let style {
            baseSize = Typography.baseSize(style)
            baseWeight = weight ?? Typography.defaultWeight(style)
        } else {
            baseSize = size ?? 13
            baseWeight = weight ?? .regular
        }
        var font = Font.system(size: baseSize * scale, weight: baseWeight, design: design ?? .default)
        if monospacedDigit { font = font.monospacedDigit() }
        return font
        #endif
    }
}

extension View {

    /// 语义字号 + 界面缩放。换成这个才会跟着设置里的缩放倍数放大。
    func zmFont(
        _ style: Font.TextStyle,
        weight: Font.Weight? = nil,
        monospacedDigit: Bool = false,
        design: Font.Design? = nil
    ) -> some View {
        modifier(ZmFontModifier(
            style: style,
            size: nil,
            weight: weight,
            design: design,
            monospacedDigit: monospacedDigit
        ))
    }

    /// 固定字号 + 界面缩放。
    func zmFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        monospacedDigit: Bool = false,
        design: Font.Design = .default
    ) -> some View {
        modifier(ZmFontModifier(
            style: nil,
            size: size,
            weight: weight,
            design: design,
            monospacedDigit: monospacedDigit
        ))
    }
}
