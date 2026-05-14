import SwiftUI

@main
struct IconKitApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .windowResizability(.contentSize)
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
