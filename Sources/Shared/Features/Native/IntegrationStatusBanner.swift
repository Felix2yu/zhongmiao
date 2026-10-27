import SwiftUI
import ZhongmiaoCore

extension IntegrationCenter.CredentialState {

    var tint: Color {
        switch self {
        case .noAuth, .valid: .green
        case .checking: .secondary
        case .unknown, .unconfigured: .orange
        case .expired, .invalid: .red
        }
    }

    var symbol: String {
        switch self {
        case .noAuth: "lock.open"
        case .valid: "checkmark.circle.fill"
        case .checking: "arrow.triangle.2.circlepath"
        case .unknown: "questionmark.circle"
        case .unconfigured: "key"
        case .expired: "key.slash"
        case .invalid: "exclamationmark.triangle"
        }
    }
}

/// 原生页顶部的连接状态条。未连接/失效时给出明确的下一步，而不是锁死页面。
struct IntegrationStatusBanner: View {

    let state: IntegrationCenter.CredentialState
    let error: String?
    let onConfigure: () -> Void
    var onRetry: (() -> Void)?

    var body: some View {
        if let content {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: content.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(content.tint)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(content.title)
                        .font(.footnote.weight(.semibold))
                    if let detail = content.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 6)

                if content.showsConfigure {
                    Button(content.actionTitle) {
                        onConfigure()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if let onRetry {
                    Button("重试", action: onRetry)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(content.tint.opacity(0.09))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(content.tint.opacity(0.18))
                    .frame(height: 0.5)
            }
        }
    }

    private struct Content {
        var title: String
        var detail: String?
        var symbol: String
        var tint: Color
        var actionTitle: String
        var showsConfigure: Bool
    }

    private var content: Content? {
        switch state {
        case .noAuth:
            guard let error else { return nil }
            return Content(
                title: "刷新失败",
                detail: error,
                symbol: "exclamationmark.triangle",
                tint: .orange,
                actionTitle: "重试",
                showsConfigure: false
            )
        case .valid:
            guard let error else { return nil }
            return Content(
                title: "刷新失败，显示上次数据",
                detail: error,
                symbol: "exclamationmark.triangle",
                tint: .orange,
                actionTitle: "重试",
                showsConfigure: false
            )
        case .checking:
            return Content(
                title: "正在验证连接…",
                detail: nil,
                symbol: "arrow.triangle.2.circlepath",
                tint: .secondary,
                actionTitle: "重试",
                showsConfigure: false
            )
        case .unknown:
            return Content(
                title: "连接待验证",
                detail: error,
                symbol: "questionmark.circle",
                tint: .orange,
                actionTitle: "验证",
                showsConfigure: false
            )
        case .unconfigured:
            return Content(
                title: "尚未连接",
                detail: error ?? "填写凭据后即可使用原生界面；也可以继续用网页版。",
                symbol: "key",
                tint: .orange,
                actionTitle: "配置",
                showsConfigure: true
            )
        case .expired(let message):
            return Content(
                title: "凭据已失效",
                detail: message,
                symbol: "key.slash",
                tint: .red,
                actionTitle: "重新授权",
                showsConfigure: true
            )
        case .invalid(let message):
            return Content(
                title: "连接失败",
                detail: message,
                symbol: "exclamationmark.triangle",
                tint: .red,
                actionTitle: "检查凭据",
                showsConfigure: true
            )
        }
    }
}
