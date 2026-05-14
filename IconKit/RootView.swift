import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Design Tokens

private enum DS {
    // 圆角
    static let radiusS: CGFloat  = 8
    static let radiusM: CGFloat  = 12
    static let radiusL: CGFloat  = 18
    static let radiusXL: CGFloat = 24

    // 间距
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat  = 8
    static let spacingM: CGFloat  = 12
    static let spacingL: CGFloat  = 16
    static let spacingXL: CGFloat = 24

    // 阴影
    static let shadowColor = Color.black.opacity(0.18)
    static let shadowRadius: CGFloat = 24
    static let shadowY: CGFloat = 8
}

// MARK: - RootView

struct RootView: View {

    // MARK: - Navigation

    enum SidebarItem: String, Hashable, CaseIterable {
        case export       = "export"
        case scaleReducer = "scaleReducer"

        var label: String {
            switch self {
            case .export:       return "应用图标"
            case .scaleReducer: return "缩放图片"
            }
        }

        var icon: String {
            switch self {
            case .export:       return "square.grid.3x3.fill"
            case .scaleReducer: return "arrow.up.left.and.arrow.down.right"
            }
        }

        var subtitle: String {
            switch self {
            case .export:       return "Apple & Android 图标集"
            case .scaleReducer: return "@1x / @2x / @3x 批量生成"
            }
        }

        var accentColor: Color {
            switch self {
            case .export:       return .blue
            case .scaleReducer: return .purple
            }
        }
    }

    @State private var selection: SidebarItem? = .scaleReducer

    // MARK: - Export State

    @State private var exportImage: NSImage?
    @State private var exportImageURL: URL?
    @State private var exportImagePixelSize: CGSize = .zero
    @State private var includeApple = true
    @State private var includeAndroid = false
    @State private var appleSets: Set<AppleIconSet> = [.iOS]
    @State private var exportStatus: String = ""
    @State private var isExporting: Bool = false
    @State private var showExportError = false
    @State private var exportErrorMessage = ""
    @State private var isDropTargeted = false

    // MARK: - Body

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebarList
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 250)
        } detail: {
            detailContent
                .frame(minWidth: 480)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 1000, height: 720)
        .alert("导出失败", isPresented: $showExportError) {
            Button("好的") {}
        } message: {
            Text(exportErrorMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pickImage)) { _ in
            if selection == .export { pickExportImage() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportIcons)) { _ in
            if selection == .export, exportImage != nil,
               (includeApple || includeAndroid) { runExport() }
        }
    }

    // MARK: - Sidebar List

    private var sidebarList: some View {
        List(selection: $selection) {
            // ── 功能导航 ──────────────────────────────────────────────────
            Section {
                ForEach(SidebarItem.allCases, id: \.self) { item in
                    sidebarNavRow(item)
                }
            } header: {
                Text("功能")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }

            // ── 应用图标 控制面板（仅在选中时展开）────────────────────────
            if selection == .export {
                exportControlSections
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("IconKit")
        .safeAreaInset(edge: .bottom) {
            if selection == .export {
                exportBottomBar
            } else {
                versionFooter
            }
        }
    }

    // ── 侧边栏导航行 ──────────────────────────────────────────────────────

    private func sidebarNavRow(_ item: SidebarItem) -> some View {
        HStack(spacing: DS.spacingM) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.radiusS)
                    .fill(
                        selection == item
                        ? item.accentColor.opacity(0.18)
                        : Color.secondary.opacity(0.1)
                    )
                    .frame(width: 30, height: 30)
                Image(systemName: item.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(
                        selection == item ? item.accentColor : Color.secondary
                    )
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(.system(size: 13, weight: .medium))
                Text(item.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .tag(item)
        .padding(.vertical, DS.spacingXS)
    }

    // ── 应用图标 控制 Sections ─────────────────────────────────────────────

    @ViewBuilder
    private var exportControlSections: some View {
        // 图片来源
        Section {
            Button {
                pickExportImage()
            } label: {
                Label("选择图片…", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .keyboardShortcut("o", modifiers: .command)

            if let url = exportImageURL {
                HStack(spacing: DS.spacingS) {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.blue.opacity(0.7))
                        .frame(width: 16)
                    Text(url.lastPathComponent)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("在 Finder 中显示")
                }
            }

            if exportImagePixelSize != .zero {
                HStack(spacing: DS.spacingS) {
                    Image(systemName: "ruler")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(String(format: "%.0f × %.0f px",
                                exportImagePixelSize.width,
                                exportImagePixelSize.height))
                        .font(.callout)
                        .foregroundStyle(exportImagePixelSize.width >= 1024
                                         ? Color.secondary : Color.orange)
                        .monospacedDigit()
                    if exportImagePixelSize.width < 1024 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
            }
        } header: {
            Label("图片来源", systemImage: "photo")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(nil)
        } footer: {
            Text("建议 1024×1024 PNG（带透明通道）")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }

        // Apple
        Section {
            Toggle(isOn: $includeApple.animation()) {
                Label("Asset Catalog", systemImage: "apple.logo")
            }
            if includeApple {
                ForEach(AppleIconSet.allCases) { set in
                    Toggle(isOn: Binding(
                        get: { appleSets.contains(set) },
                        set: { on in
                            if on { appleSets.insert(set) }
                            else  { appleSets.remove(set) }
                        }
                    )) {
                        Text(set.displayName)
                            .font(.callout)
                    }
                    .padding(.leading, 20)
                }
            }
        } header: {
            Label("Apple", systemImage: "apple.logo")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(nil)
        }

        // Android
        Section {
            Toggle(isOn: $includeAndroid) {
                Label("mipmap 资源", systemImage: "smartphone")
            }
        } header: {
            Label("Android", systemImage: "smartphone")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(nil)
        }

        // 状态
        if !exportStatus.isEmpty {
            Section {
                HStack(alignment: .top, spacing: DS.spacingS) {
                    Image(systemName: exportStatus.contains("完成") ? "checkmark.circle.fill" : "info.circle.fill")
                        .foregroundStyle(exportStatus.contains("完成") ? .green : .blue)
                        .font(.caption)
                        .padding(.top, 1)
                    Text(exportStatus)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                Label("状态", systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
    }

    // ── 底部操作栏 ─────────────────────────────────────────────────────────

    private var exportBottomBar: some View {
        VStack(spacing: DS.spacingS) {
            // 导出按钮
            Button { runExport() } label: {
                Group {
                    if isExporting {
                        HStack(spacing: DS.spacingS) {
                            ProgressView().controlSize(.small)
                            Text("导出中…")
                        }
                    } else {
                        Label("导出到文件夹…", systemImage: "square.and.arrow.up")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(exportImage == nil || (!includeApple && !includeAndroid) || isExporting)
            .keyboardShortcut("e", modifiers: [.command, .shift])

            // 辅助操作行
            HStack {
                Button {
                    guard let img = exportImage else { return }
                    NSApplication.shared.applicationIconImage = img
                    exportStatus = "已设为 Dock 图标（重启后恢复）"
                } label: {
                    Label("Dock 预览", systemImage: "dock.rectangle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(exportImage == nil)
                .help("将当前图片临时设为 Dock 图标")

                Spacer()

                if exportImage != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            exportImage = nil
                            exportImageURL = nil
                            exportImagePixelSize = .zero
                            exportStatus = ""
                        }
                    } label: {
                        Label("清除", systemImage: "xmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("清除当前图片")
                }
            }
        }
        .padding(.horizontal, DS.spacingM)
        .padding(.vertical, DS.spacingM)
        .background(.bar)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        switch selection ?? .export {
        case .export:
            exportPreview
        case .scaleReducer:
            ScaleReducerView()
        }
    }

    // ── 应用图标 预览区 ────────────────────────────────────────────────────

    private var exportPreview: some View {
        ZStack {
            // 渐变背景
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .windowBackgroundColor).opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 棋盘格背景（透明图标预览）
            if exportImage != nil {
                CheckerboardBackground()
                    .opacity(0.03)
            }

            // 拖拽高亮背景
            if isDropTargeted {
                RoundedRectangle(cornerRadius: DS.radiusXL)
                    .fill(Color.accentColor.opacity(0.06))
                    .padding(DS.spacingXL)
                    .transition(.opacity)
            }

            // 图片 / 提示
            if let img = exportImage {
                VStack(spacing: 0) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: DS.radiusL))
                        .padding(60)
                        .shadow(color: DS.shadowColor, radius: DS.shadowRadius, x: 0, y: DS.shadowY)
                        .transition(.opacity.combined(with: .scale(scale: 0.93)))

                    // 图片信息标签
                    if exportImagePixelSize != .zero {
                        HStack(spacing: DS.spacingS) {
                            Image(systemName: "photo")
                                .font(.caption2)
                            Text(String(format: "%.0f × %.0f px",
                                        exportImagePixelSize.width,
                                        exportImagePixelSize.height))
                                .font(.caption.monospacedDigit())
                            if let url = exportImageURL {
                                Text("·")
                                    .foregroundStyle(.quaternary)
                                Text(url.lastPathComponent)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, DS.spacingL)
                        .padding(.vertical, DS.spacingXS)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, DS.spacingXL)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            } else {
                dropHint
            }

            // 拖拽边框
            RoundedRectangle(cornerRadius: DS.radiusXL)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.12),
                    style: StrokeStyle(
                        lineWidth: isDropTargeted ? 2 : 1,
                        dash: isDropTargeted ? [] : [8, 4]
                    )
                )
                .padding(DS.spacingXL)
                .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    DispatchQueue.main.async { loadExportImage(from: url) }
                }
            }
            return true
        }
        .animation(.easeInOut(duration: 0.25), value: exportImage == nil)
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
    }

    private var dropHint: some View {
        VStack(spacing: DS.spacingXL) {
            ZStack {
                // 外圈光晕
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                (isDropTargeted ? Color.accentColor : Color.secondary).opacity(0.12),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)

                // 内圈
                Circle()
                    .fill(
                        isDropTargeted
                        ? Color.accentColor.opacity(0.12)
                        : Color.secondary.opacity(0.07)
                    )
                    .frame(width: 88, height: 88)

                Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "photo.badge.plus")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(
                        isDropTargeted
                        ? Color.accentColor
                        : Color.secondary.opacity(0.4)
                    )
                    .symbolEffect(.bounce, value: isDropTargeted)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isDropTargeted)

            VStack(spacing: DS.spacingS) {
                Text(isDropTargeted ? "松开以载入" : "拖拽图片到这里")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(
                        isDropTargeted ? Color.accentColor : Color.primary.opacity(0.5)
                    )
                Text("支持 PNG、JPEG · 建议 1024×1024")
                    .font(.subheadline)
                    .foregroundStyle(.quaternary)

                // 快捷键提示
                if !isDropTargeted {
                    HStack(spacing: DS.spacingXS) {
                        KeyboardShortcutBadge(key: "⌘", label: "O")
                        Text("选择文件")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                    }
                    .padding(.top, DS.spacingXS)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
        }
    }

    // MARK: - Footer

    private var versionFooter: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return HStack {
            Text("IconKit  v\(version) (\(build))")
                .font(.caption2)
                .foregroundStyle(.quaternary)
            Spacer()
        }
        .padding(.horizontal, DS.spacingL)
        .padding(.bottom, DS.spacingM)
    }

    // MARK: - Actions

    private func pickExportImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg]
        if panel.runModal() == .OK, let url = panel.url {
            loadExportImage(from: url)
        }
    }

    private func loadExportImage(from url: URL) {
        // NSImage 及 ImageResizer 均需在主线程操作，使用 Task 异步加载
        Task {
            let imgOpt: NSImage? = await Task.detached(priority: .userInitiated) {
                NSImage(contentsOf: url)
            }.value
            guard let img = imgOpt else {
                exportErrorMessage = "无法读取图片：\(url.lastPathComponent)"
                showExportError = true
                return
            }
            let pixelSize = await Task.detached(priority: .userInitiated) {
                ImageResizer.pixelSize(of: img)
            }.value
            withAnimation(.easeInOut(duration: 0.3)) {
                exportImage = img
                exportImageURL = url
            }
            exportImagePixelSize = pixelSize
            let sz = String(format: "%.0f×%.0f px", pixelSize.width, pixelSize.height)
            exportStatus = "已载入：\(url.lastPathComponent)（\(sz)）"
        }
    }

    private func runExport() {
        guard let image = exportImage else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "导出到此处"
        panel.message = "选择图标资源的导出目录"
        if panel.runModal() != .OK { return }
        guard let dir = panel.url else { return }

        isExporting = true
        exportStatus = "正在导出…"

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var outputs: [String] = []
                if self.includeApple {
                    let out = dir.appendingPathComponent("Apple", isDirectory: true)
                    try IconExporter.exportAppleAll(from: image, to: out, sets: self.appleSets)
                    outputs.append("✅ Apple → \(out.lastPathComponent)/")
                }
                if self.includeAndroid {
                    let out = dir.appendingPathComponent("Android", isDirectory: true)
                    try AndroidExporter.exportLauncherIcons(from: image, to: out)
                    outputs.append("✅ Android → \(out.lastPathComponent)/")
                }
                DispatchQueue.main.async {
                    self.isExporting = false
                    self.exportStatus = "导出完成 🎉\n" + outputs.joined(separator: "\n")
                    NSWorkspace.shared.open(dir)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isExporting = false
                    self.exportErrorMessage = error.localizedDescription
                    self.showExportError = true
                }
            }
        }
    }
}

// MARK: - Keyboard Shortcut Badge

private struct KeyboardShortcutBadge: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 2) {
            Text(key)
            Text(label)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.quaternary)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Checkerboard Background

private struct CheckerboardBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let tile: CGFloat = 14
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var col = 0
                var x: CGFloat = 0
                while x < size.width {
                    if (row + col) % 2 == 0 {
                        ctx.fill(
                            Path(CGRect(x: x, y: y, width: tile, height: tile)),
                            with: .color(.primary)
                        )
                    }
                    x += tile; col += 1
                }
                y += tile; row += 1
            }
        }
    }
}

#Preview {
    RootView()
        .frame(width: 1000, height: 800)
}
