import SwiftUI
import AppKit

struct ScaleReducerView: View {

    // MARK: - Types

    enum ExportMode: Int {
        case sameFolder
        case customFolder
    }

    // MARK: - State

    @State private var inputURLs: [URL] = []
    @State private var selectedURL: URL?          // 预览选中项
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
                .frame(minWidth: 260, maxWidth: 360)
            rightPanel
                .frame(minWidth: 400)
        }
        .navigationTitle("缩放图片")
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {

            // 拖拽区
            dropZone
                .padding([.horizontal, .top], 12)
                .padding(.bottom, 8)

            // 操作按钮行
            actionBar
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            Divider()

            // 文件列表
            fileList

            Divider()

            // 设置区
            settingsArea
                .padding(12)
        }
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(isTargeted
                      ? Color.accentColor.opacity(0.15)
                      : Color.secondary.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5])
                        )
                )

            VStack(spacing: 6) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 28))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
                Text(inputURLs.isEmpty
                     ? "拖拽 PNG / JPEG 到这里"
                     : "已选 \(inputURLs.count) 张，可继续拖入")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .frame(height: 100)
        .onDrop(of: ["public.file-url"], isTargeted: $isTargeted) { providers in
            var added = false
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { addURLs([url]) }
                }
                added = true
            }
            return added
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button("选择图片") { pickImages() }
            Button("选择文件夹") { pickFolder() }
            Toggle("递归", isOn: $recursiveScan)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("选择文件夹时递归扫描子目录")
            Spacer()
            Button("清空") {
                inputURLs.removeAll()
                selectedURL = nil
                previewImage = nil
                status = ""
                progressCurrent = 0
                progressTotal = 0
            }
            .foregroundStyle(.red)
            .disabled(inputURLs.isEmpty || isRunning)
        }
    }

    // MARK: - File List

    private var fileList: some View {
        List(selection: $selectedURL) {
            ForEach(inputURLs, id: \.self) { url in
                HStack(spacing: 6) {
                    Image(systemName: iconName(for: url))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(url.lastPathComponent)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        inputURLs.removeAll { $0 == url }
                        if selectedURL == url {
                            selectedURL = nil
                            previewImage = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRunning)
                }
                .tag(url)
            }
        .listStyle(.plain)
        .frame(minHeight: 120, maxHeight: .infinity)
        .onChange(of: selectedURL) { url in
            loadPreview(url: url)
        }
        }
    }

    // MARK: - Settings Area

    private var settingsArea: some View {
        VStack(alignment: .leading, spacing: 10) {

            // AI 放大
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("优先使用 Real-ESRGAN 提升质量", isOn: $preferAIUpscale)
                        .font(.callout)
                    Text("仅对 @2x→@3x 生成时生效；无可用模型则回退插值。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("打开 Real-ESRGAN 目录") { openRealESRGANDir() }
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .buttonStyle(.plain)
                }
                .padding(4)
            } label: {
                Label("AI 放大", systemImage: "wand.and.stars")
                    .font(.caption.bold())
            }

            // 导出目录
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
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
                        HStack(spacing: 6) {
                            Button("选择目录…") { pickExportDir() }
                                .disabled(isRunning)
                            if let dir = customExportDir {
                                Text(dir.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text("未选择")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    } else {
                        Text("导出到每张图片所在目录。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(4)
            } label: {
                Label("导出目录", systemImage: "folder")
                    .font(.caption.bold())
            }

            // 导出按钮 + 进度
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    Task { await exportBatchAsync() }
                } label: {
                    Label(isRunning ? "处理中…" : "批量导出",
                          systemImage: isRunning ? "hourglass" : "arrow.down.to.line")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputURLs.isEmpty || isRunning ||
                          (exportMode == .customFolder && customExportDir == nil))

                if isRunning && progressTotal > 0 {
                    ProgressView(value: Double(progressCurrent), total: Double(progressTotal))
                        .progressViewStyle(.linear)
                    Text("处理中：\(progressCurrent) / \(progressTotal)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(spacing: 0) {
            // 预览区
            ZStack {
                Color.secondary.opacity(0.06)

                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .padding(24)
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                        Text(inputURLs.isEmpty ? "选择文件后点击列表项预览" : "点击左侧列表项预览")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // 日志区
            if !status.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("日志", systemImage: "doc.text")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("清除") { status = "" }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                    }
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(status)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("logBottom")
                        .frame(maxHeight: 160)
                        .onChange(of: status) { _ in
                            proxy.scrollTo("logBottom", anchor: .bottom)
                        }
                        }
                    }
                }
                .padding(12)
                .background(.background)
            }
        }
    }

    // MARK: - UI Actions

    private func openRealESRGANDir() {
        let url = RealESRGANManager.shared.installDirURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

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

    private func addURLs(_ urls: [URL]) {
        let allowed = Set(["png", "jpg", "jpeg"])
        let filtered = urls
            .filter { allowed.contains($0.pathExtension.lowercased()) }
            .map { $0.standardizedFileURL }

        DispatchQueue.main.async {
            let existing = Set(inputURLs)
            let newOnes = filtered.filter { !existing.contains($0) }
            inputURLs.append(contentsOf: newOnes)
            inputURLs.sort { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
        }
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
            DispatchQueue.main.async { previewImage = img }
        }
    }

    private func iconName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png":  return "photo"
        case "jpg", "jpeg": return "photo.fill"
        default:     return "doc"
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
                try await exportOneAsync(inputURL: url)
                ok += 1
                status = appendLog(status, "✅ \(url.lastPathComponent)")
            } catch {
                failed += 1
                status = appendLog(status, "❌ \(url.lastPathComponent) — \(error.localizedDescription)")
            }
        }

        status = appendLog(status, "\n完成：成功 \(ok) 张 / 失败 \(failed) 张")
    }

    private func exportOneAsync(inputURL: URL) async throws {
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

        if inputName.contains("@3x") {
            // @3x → 生成 @3x / @2x / @1x
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

        } else if inputName.contains("@2x") {
            // @2x → 生成 @3x（AI 或插值）/ @2x / @1x
            if let out3x = try await make3xFrom2x(inputURL: inputURL, srcRep: srcRep) {
                try out3x.write(to: outDir.appendingPathComponent("\(baseName)@3x.png"))
            }
            try writeRep(srcRep, w: srcW, h: srcH,
                         to: outDir.appendingPathComponent("\(baseName)@2x.png"))
            try writeRep(srcRep,
                         w: Int(round(Double(srcW) / 2.0)),
                         h: Int(round(Double(srcH) / 2.0)),
                         to: outDir.appendingPathComponent("\(baseName).png"))

        } else {
            // 无 scale 标记 → 原样输出
            try writeRep(srcRep, w: srcW, h: srcH,
                         to: outDir.appendingPathComponent("\(baseName).png"))
        }
    }

    private func writeRep(_ rep: NSBitmapImageRep, w: Int, h: Int, to url: URL) throws {
        guard let data = renderPNG(from: rep, targetPixelsWide: w, targetPixelsHigh: h) else {
            throw NSError(domain: "IconKit", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "渲染失败：\(url.lastPathComponent)"])
        }
        try data.write(to: url)
    }

    // MARK: - AI Upscale

    private func make3xFrom2x(inputURL: URL, srcRep: NSBitmapImageRep) async throws -> Data? {
        let srcW = srcRep.pixelsWide
        let srcH = srcRep.pixelsHigh
        let targetW = Int(round(Double(srcW) * 1.5))
        let targetH = Int(round(Double(srcH) * 1.5))

        if preferAIUpscale, let ai = try await aiUpscaleTo4x(inputURL: inputURL) {
            guard let rep4x = NSBitmapImageRep(data: ai) else {
                return renderPNG(from: srcRep, targetPixelsWide: targetW, targetPixelsHigh: targetH)
            }
            let w3 = Int(round(Double(rep4x.pixelsWide) * 0.75))
            let h3 = Int(round(Double(rep4x.pixelsHigh) * 0.75))
            return renderPNG(from: rep4x, targetPixelsWide: w3, targetPixelsHigh: h3)
        }

        return renderPNG(from: srcRep, targetPixelsWide: targetW, targetPixelsHigh: targetH)
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

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }

        guard proc.terminationStatus == 0 else { return nil }
        return try? Data(contentsOf: outURL)
    }

    // MARK: - Render helper

    private func renderPNG(from srcRep: NSBitmapImageRep, targetPixelsWide: Int, targetPixelsHigh: Int) -> Data? {
        let w = max(1, targetPixelsWide)
        let h = max(1, targetPixelsHigh)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let cgCtx = CGContext(
                data: nil, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        cgCtx.interpolationQuality = .high
        cgCtx.clear(CGRect(x: 0, y: 0, width: w, height: h))

        let srcImage = NSImage(size: CGSize(width: srcRep.pixelsWide, height: srcRep.pixelsHigh))
        srcImage.addRepresentation(srcRep)

        let nsCtx = NSGraphicsContext(cgContext: cgCtx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        nsCtx.imageInterpolation = .high

        srcImage.draw(in: CGRect(x: 0, y: 0, width: w, height: h),
                      from: CGRect(x: 0, y: 0, width: srcRep.pixelsWide, height: srcRep.pixelsHigh),
                      operation: .sourceOver,
                      fraction: 1.0,
                      respectFlipped: false,
                      hints: [.interpolation: NSImageInterpolation.high])

        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = cgCtx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = CGSize(width: w, height: h)
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Log helper

    private func appendLog(_ current: String, _ line: String) -> String {
        current.isEmpty ? line : current + "\n" + line
    }
}

#Preview {
    NavigationStack { ScaleReducerView() }
        .frame(width: 860, height: 600)
}
