import SwiftUI
import ZhongmiaoCore

/// 所有原生页共用的右上角菜单：刷新、提醒/接入设置、网页版。
struct IntegrationScreenMenu: View {

    @Environment(AppModel.self) private var model

    let service: ServiceDefinition
    let definition: IntegrationDefinition
    let onRefresh: () -> Void

    @State private var sheet: Sheet?

    private enum Sheet: String, Identifiable {
        case settings
        case web

        var id: String { rawValue }
    }

    var body: some View {
        Menu {
            Button {
                onRefresh()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }

            Button {
                sheet = .settings
            } label: {
                Label(definition.supportsReminders ? "提醒与接入设置" : "接入设置", systemImage: "slider.horizontal.3")
            }

            if model.url(for: service) != nil {
                Button {
                    sheet = .web
                } label: {
                    Label("在网页版打开", systemImage: "safari")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("更多操作")
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .settings:
                NavigationStack {
                    ServiceConfigView(service: service, showsDoneButton: true)
                }
            case .web:
                if let url = model.url(for: service) {
                    NavigationStack {
                        ServiceScreen(service: service, initialURL: url)
                    }
                }
            }
        }
    }
}
