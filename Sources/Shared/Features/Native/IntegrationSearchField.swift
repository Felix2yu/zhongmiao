import SwiftUI

/// 原生页共用的搜索输入框。
///
/// 各页的搜索交互保持一致：放大镜图标、清除按钮、聚焦高亮、回车即搜。
/// 页面自己决定「输入即搜」还是「回车才搜」，这里只管外观与输入。
struct IntegrationSearchField: View {

    @Binding var text: String
    var placeholder: String
    /// 回车或点清除时触发；输入即搜的页面留空即可。
    var onSubmit: (() -> Void)?
    /// 输入变化时触发（输入即搜）。
    var onChange: (() -> Void)?

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.search)
                .onSubmit {
                    focused = false
                    onSubmit?()
                }
                .onChange(of: text) { _, _ in
                    onChange?()
                }

            if !text.isEmpty {
                Button {
                    text = ""
                    onSubmit?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            focused ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .animation(.easeOut(duration: 0.12), value: focused)
    }
}
