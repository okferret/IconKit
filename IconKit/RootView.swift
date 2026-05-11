import SwiftUI

struct RootView: View {
    enum SidebarItem: String, Hashable, CaseIterable {
        case scaleReducer = "scaleReducer"
        case export       = "export"

        var label: String {
            switch self {
            case .scaleReducer: return "缩放图片"
            case .export:       return "应用图标"
            }
        }

        var icon: String {
            switch self {
            case .scaleReducer: return "arrow.up.left.and.arrow.down.right"
            case .export:       return "square.grid.3x3.fill"
            }
        }
    }

    @State private var selection: SidebarItem? = .export

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(selection: $selection) {
            Section("功能") {
                ForEach(SidebarItem.allCases, id: \.self) { item in
                    Label(item.label, systemImage: item.icon)
                        .tag(item)
                }
            }

            Section("帮助") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("拖拽图片到右侧区域", systemImage: "hand.draw")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("建议使用 1024×1024 PNG", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("IconKit")
        .safeAreaInset(edge: .bottom) {
            versionFooter
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        switch selection ?? .export {
        case .scaleReducer:
            NavigationStack {
                ScaleReducerView()
                    .navigationTitle("缩放图片")
            }
        case .export:
            ContentView()
        }
    }

    // MARK: - Footer

    private var versionFooter: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return HStack {
            Text("IconKit \(version) (\(build))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

#Preview {
    RootView()
        .frame(width: 860, height: 560)
}
