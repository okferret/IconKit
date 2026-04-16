import SwiftUI
import AppKit

struct ContentView: View {
    @State private var image: NSImage?
    @State private var imageURL: URL?

    @State private var includeApple = true
    @State private var includeAndroid = false

    // 默认只勾选 iOS
    @State private var appleSets: Set<AppleIconSet> = [.iOS]

    @State private var statusText: String = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                //.frame(minWidth: 200, idealWidth: 240, maxWidth: 380)
                .background(.ultraThinMaterial)

            Divider()

            detail
        }
        .alert("错误", isPresented: $showErrorAlert) {
            Button("好") {}
        } message: {
            Text(errorMessage)
        }.navigationTitle("应用图标")
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox("输入") {
                    VStack(alignment: .leading, spacing: 10) {
                        Button("选择图片…") { pickImage() }
                        if let url = imageURL {
                            Text(url.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Text("建议提供 1024×1024 PNG（带透明）。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 200, alignment: .leading)
                    .padding(5)
                }

                GroupBox("导出") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Apple（Asset Catalog）", isOn: $includeApple)
                        if includeApple {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(AppleIconSet.allCases) { set in
                                    Toggle(set.displayName, isOn: Binding(
                                        get: { appleSets.contains(set) },
                                        set: { isOn in
                                            if isOn { appleSets.insert(set) } else { appleSets.remove(set) }
                                        }
                                    ))
                                }
                            }
                            .padding(.leading, 2)
                        }

                        Toggle("Android（mipmap/drawable）", isOn: $includeAndroid)

                        Button("导出到文件夹…") { export() }
                            .disabled(image == nil || (!includeApple && !includeAndroid))
                    }
                    .frame(width: 200, alignment: .leading)
                    .padding(5)
                }

                if !statusText.isEmpty {
                    GroupBox("状态") {
                        Text(statusText)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(12)
        }
    }

    private var detail: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.secondary.opacity(0.10))

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(20)
                } else {
                    VStack(spacing: 8) {
                        Text("拖拽图片到这里")
                            .font(.headline)
                        Text("或使用左侧“选择图片…”")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minHeight: 420)
            .padding(16)
            .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { loadImage(from: url) }
                }
                return true
            }

            HStack {
                Button("预览到 Dock") { previewInDock() }
                    .disabled(image == nil)
                Spacer()
                Text("macOS 13.5+")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg]
        if panel.runModal() == .OK, let url = panel.url {
            loadImage(from: url)
        }
    }

    private func loadImage(from url: URL) {
        DispatchQueue.main.async {
            if let img = NSImage(contentsOf: url) {
                self.imageURL = url
                self.image = img
                self.statusText = "已载入：\(url.lastPathComponent)"
            } else {
                self.showError("无法读取图片：\(url.lastPathComponent)")
            }
        }
    }

    private func export() {
        guard let image else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "导出"

        if panel.runModal() != .OK { return }
        guard let dir = panel.url else { return }

        do {
            var outputs: [URL] = []

            if includeApple {
                let appleOut = dir.appendingPathComponent("Apple", isDirectory: true)
                try IconExporter.exportAppleAll(from: image, to: appleOut, sets: appleSets)
                outputs.append(appleOut)
            }
            if includeAndroid {
                let androidOut = dir.appendingPathComponent("Android", isDirectory: true)
                try AndroidExporter.exportLauncherIcons(from: image, to: androidOut)
                outputs.append(androidOut)
            }

            statusText = "导出完成：\n" + outputs.map { $0.path }.joined(separator: "\n")
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func previewInDock() {
        guard let image else { return }
        NSApplication.shared.applicationIconImage = image
        statusText = "已将当前图片设置为应用 Dock 图标（仅预览，不会写入 AppIcon）。"
    }

    private func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }
}

#Preview {
    ContentView()
}
