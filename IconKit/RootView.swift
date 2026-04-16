import SwiftUI

struct RootView: View {
    enum SidebarItem: Hashable {
        case scaleReducer
        case export
    }

    @State private var selection: SidebarItem? = .scaleReducer

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("导出缩放图片", systemImage: "arrow.up.left.and.arrow.down.right")
                        .tag(SidebarItem.scaleReducer)
                    Label("导出应用图标", systemImage: "square.and.arrow.up")
                        .tag(SidebarItem.export)
                } header: {
                    Text("IconKit")
                }

                Section {
                    Label("拖拽图片到右侧即可开始", systemImage: "photo")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .tag(nil as SidebarItem?)
                        .disabled(true)
                } header: {
                    Text("提示")
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("IconKit")
        } detail: {
            Group {
                switch selection ?? .scaleReducer {
                case .scaleReducer:
                    NavigationStack { ScaleReducerView() }
                case .export:
                    ContentView()
                }
            }
        }
    }
}

#Preview {
    RootView()
}
