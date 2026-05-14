import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - ScaleReducerView

struct ScaleReducerView: View {

    // MARK: - Types

    enum ExportMode: Int {
        case sameFolder
        case customFolder
    }

    // MARK: - State

    @State private var inputURLs: [URL] = []
    @State private var selectedURL: URL?
    @State private var previewImage: NSImage?

    @State private var status: String = ""
    @State private var exportMode: ExportMode = .sameFolder
    @State private var customExportDir: URL?

    @State private var preferAIUpscale: Bool = true
    @State private var recursiveScan: Bool = false

    @State private var isRunning: Bool = false
    @State private var progressCurrent: Int = 0
    @State private var progressTotal: Int = 0

    @State private var isTargeted: Bool = false

    // MARK: - Body

    var body: some View {
        HSplitView {
            leftPanel
                .frame(minWidth: 270, maxWidth: 340)
            rightPanel
                .frame(minWidth: 260, maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
    VStack(alignment: .leading, spacing: 0) {

        // 拖拽区 + 操作栏（固定顶部）
        VStack(spacing: 10) {
            dropZone
            actionBar
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)

        Divider().opacity(0.4)

        // 文件列表（固定高度）
        fileList

        Divider().opacity(0.4)

        // 设置区（可滚动，占满剩余空间）
        ScrollView(.vertical, showsIndicators: false) {
            settingsAreaScrollable
                .padding(14)
        }
        .frame(maxHeight: .infinity)

        Divider().opacity(0.4)

        // 批量导出按钮（固定底部，始终可见）
        exportActionArea
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
    }
    .background(Color(nsColor: .windowBackgroundColor))
}
    // MARK: - Drop Zone

    private var dropZone: some View {
        ZStack {
            // 背景
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    isTargeted
                    ? Color.accentColor.opacity(0.08)
                    : Color.secondary.opacity(0.05)
                )

            // 边框
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.2),
                    style: StrokeStyle(
                        lineWidth: isTargeted ? 1.5 : 1,
                        dash: isTargeted ? [] : [6, 3]
                    )
                )

            // 内容
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            isTargeted
                            ? Color.accentColor.opacity(0.12)
                            : Color.secondary.opacity(0.08)
                        )
                        .frame(width: 52, height: 52)

                    Image(systemName: isTargeted ? "arrow.down.circle.fill" : "photo.stack")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(
                            isTargeted ? Color.accentColor : Color.secondary.opacity(0.5)
                        )
                        .symbolEffect(.bounce, value: isTargeted)
                }

                VStack(spacing: 3) {
                    Text(isTargeted ? "松开以添加" :
                         (inputURLs.isEmpty ? "拖拽 PNG / JPEG 到这里" : "已选 \(inputURLs.count) 张，可继续拖入"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)

                    if !isTargeted && inputURLs.isEmpty {
                        Text("或点击下方按钮选择文件")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                    }
                }
            }
            .padding(20)
        }
        .frame(height: 120)
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            let group = DispatchGroup()
            var collected: [URL] = []
            let lock = NSLock()

            for p in providers {
                group.enter()
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url {
                        lock.lock()
                        collected.append(url)
                        lock.unlock()
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                if !collected.isEmpty { addURLs(collected) }
            }
            return !providers.isEmpty
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 6) {
            Button {
                pickImages()
            } label: {
                Label("选择图片", systemImage: "photo.badge.plus")
                    .font(.callout)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                pickFolder()
            } label: {
                Label("选择文件夹", systemImage: "folder.badge.plus")
                    .font(.callout)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Toggle(isOn: $recursiveScan) {
                Text("递归")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("选择文件夹时递归扫描子目录")

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    inputURLs.removeAll()
                    selectedURL = nil
                    previewImage = nil
                    status = ""
                    progressCurrent = 0
                    progressTotal = 0
                }
            } label: {
                Image(systemName: "trash")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red.opacity(0.8))
            .help("清空文件列表")
            .disabled(inputURLs.isEmpty || isRunning)
        }
    }

    // MARK: - File List

    private var fileList: some View {
        Group {
            if inputURLs.isEmpty {
                // 空状态
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 24))
                        .foregroundStyle(.quaternary)
                    Text("暂无文件")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 80, maxHeight: 200)
            } else {
                List(selection: $selectedURL) {
                    ForEach(inputURLs, id: \.self) { url in
                        fileRow(url: url)
                            .tag(url)
                    }
                }
                .listStyle(.plain)
                .frame(minHeight: 80, maxHeight: 200)
            }
        }
        .onChange(of: selectedURL) { _, newURL in
            loadPreview(url: newURL)
        }
    }

    private func fileRow(url: URL) -> some View {
        HStack(spacing: 8) {
            // 文件类型图标
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(fileIconColor(for: url).opacity(0.12))
                    .frame(width: 22, height: 22)
                Image(systemName: iconName(for: url))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(fileIconColor(for: url))
            }

            Text(url.lastPathComponent)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    inputURLs.removeAll { $0 == url }
                    if selectedURL == url {
                        selectedURL = nil
                        previewImage = nil
                    }
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(isRunning)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Settings Area

    // 可滚动设置区（不含导出按钮）
    private var settingsAreaScrollable: some View {
        VStack(alignment: .leading, spacing: 12) {

            // AI 放大
            settingsCard(
                icon: "wand.and.stars",
                iconColor: .purple,
                title: "AI 放大"
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("优先使用 Real-ESRGAN 提升质量", isOn: $preferAIUpscale)
                        .font(.callout)
                    Text("对 @1x→@2x/@3x 及 @2x→@3x 生成时生效；无可用模型则回退插值。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    RealESRGANInstallView()
                }
            }
            .frame(maxWidth: .infinity)

            // 导出目录
            settingsCard(
                icon: "folder",
                iconColor: .orange,
                title: "导出目录"
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: Binding(
                        get: { exportMode.rawValue },
                        set: { exportMode = ExportMode(rawValue: $0) ?? .sameFolder }
                    )) {
                        Text("与原图同目录").tag(0)
                        Text("统一导出目录").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if exportMode == .customFolder {
                        HStack(spacing: 8) {
                            Button("选择目录…") { pickExportDir() }
                                .disabled(isRunning)
                                .controlSize(.small)
                                .buttonStyle(.bordered)
                            if let dir = customExportDir {
                                Label(dir.lastPathComponent, systemImage: "folder.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                Label("未选择", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text("导出到每张图片所在目录")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    // 设置卡片容器
    private func settingsCard<Content: View>(
        icon: String,
        iconColor: Color,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题行
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 18, height: 18)
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private var exportActionArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await exportBatchAsync() }
            } label: {
                HStack(spacing: 6) {
                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Label(
                        isRunning ? "处理中…" : "批量导出",
                        systemImage: isRunning ? "hourglass" : "arrow.down.to.line"
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(inputURLs.isEmpty || isRunning ||
                      (exportMode == .customFolder && customExportDir == nil))

            if isRunning && progressTotal > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        ProgressView(value: Double(progressCurrent), total: Double(progressTotal))
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                        Text("\(progressCurrent)/\(progressTotal)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                    Text("正在处理第 \(progressCurrent) 张，共 \(progressTotal) 张…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(spacing: 0) {
            // 预览区（四周统一 16pt 边距）
            previewArea
                .padding(16)

            // 日志区
            if !status.isEmpty {
                Divider()
                    .opacity(0.5)
                logArea
            }
        }
    }

    private var previewArea: some View {
        ZStack {
            // 背景
            Color(nsColor: .windowBackgroundColor)

            if let previewImage {
                VStack(spacing: 0) {
                    Image(nsImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 6)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))

                    // 图片信息
                    if let url = selectedURL {
                        HStack(spacing: 6) {
                            Image(systemName: iconName(for: url))
                                .font(.caption2)
                            Text(url.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 12)
                        .transition(.opacity)
                    }
                }
                .padding(20)
            } else {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.secondary.opacity(0.06))
                            .frame(width: 72, height: 72)
                        Image(systemName: "photo")
                            .font(.system(size: 30, weight: .ultraLight))
                            .foregroundStyle(.quaternary)
                    }
                    Text(inputURLs.isEmpty ? "选择文件后点击列表项预览" : "点击左侧列表项预览")
                        .font(.callout)
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 虚线边框用 overlay，padding 才能正确内缩
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    Color.secondary.opacity(0.15),
                    style: StrokeStyle(lineWidth: 1, dash: [8, 4])
                )
        )
        .cornerRadius(16.0)
        .animation(.easeInOut(duration: 0.2), value: previewImage == nil)
    }

    private var logArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text")
                        .font(.caption2)
                    Text("日志")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        status = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("清除日志")
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(status)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 2)
                        .id("logBottom")
                }
                .frame(maxHeight: 140)
                .onChange(of: status) { _, _ in
                    withAnimation { proxy.scrollTo("logBottom", anchor: .bottom) }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - UI Actions

    private func pickImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg]
        if panel.runModal() == .OK {
            addURLs(panel.urls)
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if panel.runModal() == .OK, let dir = panel.url {
            let urls = scanImages(in: dir, recursive: recursiveScan)
            addURLs(urls)
            if urls.isEmpty {
                status = appendLog(status, "⚠️ 文件夹内未找到 PNG/JPEG：\(dir.path)")
            }
        }
    }

    private func pickExportDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            customExportDir = url
        }
    }

    @MainActor
    private func addURLs(_ urls: [URL]) {
        let allowed = Set(["png", "jpg", "jpeg"])
        let filtered = urls
            .filter { allowed.contains($0.pathExtension.lowercased()) }
            .map { $0.standardizedFileURL }

        // 已在主线程（@MainActor），直接操作 State，无需 DispatchQueue.main.async
        let existing = Set(inputURLs)
        let newOnes = filtered.filter { !existing.contains($0) }
        inputURLs.append(contentsOf: newOnes)
        inputURLs.sort { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
    }

    private func scanImages(in dir: URL, recursive: Bool) -> [URL] {
        let fm = FileManager.default
        let opts: FileManager.DirectoryEnumerationOptions = recursive
            ? [.skipsHiddenFiles]
            : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: opts) else {
            return []
        }
        let allowed = Set(["png", "jpg", "jpeg"])
        var out: [URL] = []
        for case let url as URL in e {
            if allowed.contains(url.pathExtension.lowercased()) {
                out.append(url)
            }
        }
        return out
    }

    private func loadPreview(url: URL?) {
        guard let url else { previewImage = nil; return }
        DispatchQueue.global(qos: .userInitiated).async {
            let img = NSImage(contentsOf: url)
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.2)) {
                    previewImage = img
                }
            }
        }
    }

    private func iconName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png":  return "photo"
        case "jpg", "jpeg": return "photo.fill"
        default:     return "doc"
        }
    }

    private func fileIconColor(for url: URL) -> Color {
        switch url.pathExtension.lowercased() {
        case "png":  return .blue
        case "jpg", "jpeg": return .orange
        default:     return .secondary
        }
    }

    // MARK: - Export

    private func resolveOutDir(for inputURL: URL) -> URL? {
        switch exportMode {
        case .sameFolder:  return inputURL.deletingLastPathComponent()
        case .customFolder: return customExportDir
        }
    }

    @MainActor
    private func exportBatchAsync() async {
        guard !inputURLs.isEmpty else { return }

        isRunning = true
        progressCurrent = 0
        progressTotal = inputURLs.count
        status = ""

        defer { isRunning = false }

        var ok = 0
        var failed = 0

        for (idx, url) in inputURLs.enumerated() {
            progressCurrent = idx + 1
            do {
                let note = try await exportOneAsync(inputURL: url)
                ok += 1
                let suffix = note.isEmpty ? "" : "（\(note)）"
                status = appendLog(status, "✅ \(url.lastPathComponent)\(suffix)")
            } catch {
                failed += 1
                status = appendLog(status, "❌ \(url.lastPathComponent) — \(error.localizedDescription)")
            }
        }

        status = appendLog(status, "\n完成：成功 \(ok) 张 / 失败 \(failed) 张")
    }

    @discardableResult
    private func exportOneAsync(inputURL: URL) async throws -> String {
        guard let outDir = resolveOutDir(for: inputURL) else {
            throw NSError(domain: "IconKit", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "请先选择导出目录。"])
        }

        let data = try Data(contentsOf: inputURL)
        guard let srcRep = NSBitmapImageRep(data: data) else {
            throw NSError(domain: "IconKit", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "无法解析图片。"])
        }

        let srcW = srcRep.pixelsWide
        let srcH = srcRep.pixelsHigh

        let inputName = inputURL.lastPathComponent
        let baseName = inputURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "@3x", with: "")
            .replacingOccurrences(of: "@2x", with: "")
            .replacingOccurrences(of: "@1x", with: "")

        if inputName.contains("@3x") {
            // 使用 renderPNGExact 统一渲染，确保输出始终为 PNG 格式（即使源文件是 JPEG）
            try writeRep(srcRep, w: srcW, h: srcH,
                         to: outDir.appendingPathComponent("\(baseName)@3x.png"))
            try writeRep(srcRep,
                         w: Int(round(Double(srcW) * 2.0 / 3.0)),
                         h: Int(round(Double(srcH) * 2.0 / 3.0)),
                         to: outDir.appendingPathComponent("\(baseName)@2x.png"))
            try writeRep(srcRep,
                         w: Int(round(Double(srcW) / 3.0)),
                         h: Int(round(Double(srcH) / 3.0)),
                         to: outDir.appendingPathComponent("\(baseName).png"))
            return ""

        } else if inputName.contains("@2x") {
            if let out3x = try await make3xFrom2x(inputURL: inputURL, srcRep: srcRep) {
                try out3x.write(to: outDir.appendingPathComponent("\(baseName)@3x.png"))
            }
            try writeRep(srcRep, w: srcW, h: srcH,
                         to: outDir.appendingPathComponent("\(baseName)@2x.png"))
            try writeRep(srcRep,
                         w: Int(round(Double(srcW) / 2.0)),
                         h: Int(round(Double(srcH) / 2.0)),
                         to: outDir.appendingPathComponent("\(baseName).png"))
            return ""

        } else if inputName.contains("@1x") {
            // @1x → 生成 @1x、@2x、@3x（AI 只跑一次，复用 4x 结果）
            try writeRep(srcRep, w: srcW, h: srcH,
                         to: outDir.appendingPathComponent("\(baseName).png"))
            let (out2x, out3x) = try await makeUpscaledFrom1x(inputURL: inputURL, srcRep: srcRep)
            if let out2x { try out2x.write(to: outDir.appendingPathComponent("\(baseName)@2x.png")) }
            if let out3x { try out3x.write(to: outDir.appendingPathComponent("\(baseName)@3x.png")) }
            return ""

        } else {
            try writeRep(srcRep, w: srcW, h: srcH,
                         to: outDir.appendingPathComponent("\(baseName).png"))
            return "无 @scale 标记，仅输出原图"
        }
    }

    private func writeRep(_ rep: NSBitmapImageRep, w: Int, h: Int, to url: URL) throws {
        guard let data = renderPNGExact(from: rep, w: w, h: h) else {
            throw NSError(domain: "IconKit", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "渲染失败：\(url.lastPathComponent)"])
        }
        try data.write(to: url)
    }

    private func renderPNGExact(from srcRep: NSBitmapImageRep, w: Int, h: Int) -> Data? {
        let w = max(1, w)
        let h = max(1, h)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let cgCtx = CGContext(
                data: nil, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        cgCtx.interpolationQuality = .high
        cgCtx.clear(CGRect(x: 0, y: 0, width: w, height: h))

        // 通过 CGImage 路径绘制，避免将 srcRep 添加到新 NSImage 时可能引发的所有权冲突
        guard let srcCGImage = srcRep.cgImage else { return nil }
        cgCtx.draw(srcCGImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let cgImage = cgCtx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = CGSize(width: w, height: h)
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - AI Upscale

    /// @2x → @3x：目标尺寸为 srcW * 1.5
    private func make3xFrom2x(inputURL: URL, srcRep: NSBitmapImageRep) async throws -> Data? {
        let srcW = srcRep.pixelsWide
        let srcH = srcRep.pixelsHigh
        let targetW = Int(round(Double(srcW) * 1.5))
        let targetH = Int(round(Double(srcH) * 1.5))

        if preferAIUpscale, let ai = try await aiUpscaleTo4x(inputURL: inputURL) {
            guard let rep4x = NSBitmapImageRep(data: ai) else {
                return renderPNGExact(from: srcRep, w: targetW, h: targetH)
            }
            let w3 = Int(round(Double(rep4x.pixelsWide) * 0.75))
            let h3 = Int(round(Double(rep4x.pixelsHigh) * 0.75))
            return renderPNGExact(from: rep4x, w: w3, h: h3)
        }

        return renderPNGExact(from: srcRep, w: targetW, h: targetH)
    }
    /// @1x → @2x + @3x：AI 只跑一次，同时返回两个尺寸的 PNG Data。
    private func makeUpscaledFrom1x(
        inputURL: URL,
        srcRep: NSBitmapImageRep
    ) async throws -> (Data?, Data?) {
        let srcW = srcRep.pixelsWide
        let srcH = srcRep.pixelsHigh

        if preferAIUpscale, let ai = try await aiUpscaleTo4x(inputURL: inputURL),
           let rep4x = NSBitmapImageRep(data: ai) {
            // 4x 结果缩到 2x（50%）和 3x（75%）
            let w2 = Int(round(Double(rep4x.pixelsWide) * 0.5))
            let h2 = Int(round(Double(rep4x.pixelsHigh) * 0.5))
            let w3 = Int(round(Double(rep4x.pixelsWide) * 0.75))
            let h3 = Int(round(Double(rep4x.pixelsHigh) * 0.75))
            return (
                renderPNGExact(from: rep4x, w: w2, h: h2),
                renderPNGExact(from: rep4x, w: w3, h: h3)
            )
        }

        // 回退：高质量插值
        return (
            renderPNGExact(from: srcRep, w: srcW * 2, h: srcH * 2),
            renderPNGExact(from: srcRep, w: srcW * 3, h: srcH * 3)
        )
    }

    private func aiUpscaleTo4x(inputURL: URL) async throws -> Data? {
        let tool: URL
        do {
            tool = try await RealESRGANManager.shared.ensureInstalled(preferEmbedded: true)
        } catch {
            return nil
        }

        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("IconKit", isDirectory: true)
        try? fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let outURL = tmpDir.appendingPathComponent(UUID().uuidString + ".png")

        let proc = Process()
        proc.executableURL = tool
        proc.arguments = [
            "-i", inputURL.path,
            "-o", outURL.path,
            "-n", "realesrgan-x4plus",
            "-s", "2",
            "-f", "png"
        ]
        if let models = RealESRGANManager.shared.modelsDir(preferEmbedded: true) {
            proc.currentDirectoryURL = models.deletingLastPathComponent()
        }
        let pipe = Pipe()
        proc.standardError = pipe
        proc.standardOutput = pipe

        // terminationHandler 在系统私有队列回调，使用 CheckedContinuation 安全桥接到 async/await
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
            proc.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    let data = try? Data(contentsOf: outURL)
                    continuation.resume(returning: data)
                } else {
                    // 进程失败时返回 nil 而非抛出，由上层决定是否回退到插值
                    continuation.resume(returning: nil)
                }
            }
            do {
                try proc.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Log helper

    private func appendLog(_ current: String, _ line: String) -> String {
        current.isEmpty ? line : current + "\n" + line
    }
}

#Preview {
    ScaleReducerView()
        .frame(width: 780, height: 748)
}
