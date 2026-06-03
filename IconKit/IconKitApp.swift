import SwiftUI

@main
struct IconKitApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        // contentMinSize：允许用户自由调整窗口大小，但不小于 RootView 的 minWidth/minHeight
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 720)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("工具") {
                Button("选择图片…") {
                    NotificationCenter.default.post(name: .pickImage, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("导出图标…") {
                    NotificationCenter.default.post(name: .exportIcons, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let pickImage   = Notification.Name("IconKit.pickImage")
    static let exportIcons = Notification.Name("IconKit.exportIcons")
}
