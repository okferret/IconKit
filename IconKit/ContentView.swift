import SwiftUI
import AppKit

struct ContentView: View {
    @State private var image: NSImage?
    @State private var imageURL: URL?
    @State private var imagePixelSize: CGSize = .zero

    @State private var includeApple = true
    @State private var includeAndroid = false

    // 默认只勾选 iOS
    @State private var appleSets: Set<AppleIconSet> = [.iOS]

    @State private var statusText: String = ""
    @State private var isExporting: Bool = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isTargeted = false   // 拖拽高亮

    private let sidebarWidth: CGFloat = 220

    var body: some View {
        HStack(spacing: 0) {
            sidebar.background(.background)
            Divider()
            detail
        }
        .alert("错误", isPresented: $showErrorAlert) {
            Button("好") {}
        } message: {
            Text(errorMessage)
        }
        // 响应菜单快捷键
        .onReceive(NotificationCenter.default.publisher(for: .pickImage)) { _ in
            pickImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportIcons)) { _ in
            if image != nil && (includeApple || includeAndroid) { export() }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // ── 输入 ──────────────────────────────────────────────────────
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Button("选择图片…") { pickImage() }
                            .keyboardShortcut("o", modifiers: .command)

                        if let url = imageURL {
                            Label(url.lastPathComponent, systemImage: "photo")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        if imagePixelSize != .zero {
                            Text(String(format: "%.0f × %.0f px", imagePixelSize.width, imagePixelSize.height))
                                .font(.caption)
                                .foregroundStyle(imagePixelSize.width >= 1024 ? Color.secondary : Color.orange)
                        }

                        Text("建议提供 1024×1024 PNG（带透明）。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: sidebarWidth, alignment: .leading)
                    .padding(5)
                } label: {
                    Label("输入", systemImage: "square.and.arrow.down")
                        .font(.caption.bold())
                }

                // ── 导出 ──────────────────────────────────────────────────────
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {

                        // Apple
                        Toggle(isOn: $includeApple) {
                            Label("Apple（Asset Catalog）", systemImage: "apple.logo")
                        }
                        if includeApple {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(AppleIconSet.allCases) { set in
                                    Toggle(set.displayName, isOn: Binding(
                                        get: { appleSets.contains(set) },
                                        set: { isOn in
                                            if isOn { appleSets.insert(set) } else { appleSets.remove(set) }
                                        }
                                    ))
                                    .font(.callout)
                                }
                            }
                            .padding(.leading, 4)
                        }

                        Divider()

                        // Android
                        Toggle(isOn: $includeAndroid) {
                            Label("Android（mipmap）", systemImage: "smartphone")
                        }

                        Divider()

                        // 导出按钮
                        Button {
                            export()
                        } label: {
                            Label(isExporting ? "导出中…" : "导出到文件夹…",
                                  systemImage: isExporting ? "hourglass" : "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(image == nil || (!includeApple && !includeAndroid) || isExporting)
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                    }
                    .frame(width: sidebarWidth, alignment: .leading)
                    .padding(5)
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                        .font(.caption.bold())
                }

                // ── 状态 ──────────────────────────────────────────────────────
                if !statusText.isEmpty {
                    GroupBox {
                        ScrollView {
                            Text(statusText)
                                .font(.caption)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 120)
                    } label: {
                        Label("状态", systemImage: "info.circle")
                            .font(.caption.bold())
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .frame(width: sidebarWidth + 40)
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            // 图片预览区
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isTargeted
                          ? Color.accentColor.opacity(0.15)
                          : Color.secondary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isTargeted ? Color.accentColor : Color.clear,
                                lineWidth: 2
                            )
                    )

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(24)
                        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Text("拖拽图片到这里")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("支持 PNG、JPEG，建议 1024×1024")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
            .onDrop(of: ["public.file-url"], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { loadImage(from: url) }
                }
                return true
            }

            Divider()

            // 底部工具栏
            HStack(spacing: 12) {
                Button {
                    previewInDock()
                } label: {
                    Label("预览到 Dock", systemImage: "dock.rectangle")
                }
                .disabled(image == nil)

                if image != nil {
                    Button {
                        image = nil
                        imageURL = nil
                        imagePixelSize = .zero
                        statusText = ""
                    } label: {
                        Label("清除", systemImage: "xmark.circle")
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if let url = imageURL {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("在 Finder 中显示", systemImage: "folder")
                    }
                    .foregroundStyle(.secondary)
                }

                Text("macOS 13.5+")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Actions

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
                self.imagePixelSize = ImageResizer.pixelSize(of: img)
                let sizeStr = String(format: "%.0f×%.0f px", self.imagePixelSize.width, self.imagePixelSize.height)
                self.statusText = "已载入：\(url.lastPathComponent)（\(sizeStr)）"
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
        panel.prompt = "导出到此处"
        panel.message = "选择图标资源的导出目录"

        if panel.runModal() != .OK { return }
        guard let dir = panel.url else { return }

        isExporting = true
        statusText = "正在导出…"

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var outputs: [String] = []

                if self.includeApple {
                    let appleOut = dir.appendingPathComponent("Apple", isDirectory: true)
                    try IconExporter.exportAppleAll(from: image, to: appleOut, sets: self.appleSets)
                    outputs.append("✅ Apple → \(appleOut.path)")
                }
                if self.includeAndroid {
                    let androidOut = dir.appendingPathComponent("Android", isDirectory: true)
                    try AndroidExporter.exportLauncherIcons(from: image, to: androidOut)
                    outputs.append("✅ Android → \(androidOut.path)")
                }

                DispatchQueue.main.async {
                    self.isExporting = false
                    self.statusText = "导出完成 🎉\n" + outputs.joined(separator: "\n")
                    // 在 Finder 中打开导出目录
                    NSWorkspace.shared.open(dir)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isExporting = false
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    private func previewInDock() {
        guard let image else { return }
        NSApplication.shared.applicationIconImage = image
        statusText = "已将当前图片设置为 Dock 图标（仅预览，重启后恢复）。"
    }

    private func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }
}

#Preview {
    ContentView()
        .frame(width: 860, height: 560)
}
