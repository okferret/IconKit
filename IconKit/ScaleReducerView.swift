import SwiftUI
import AppKit

struct ScaleReducerView: View {
    enum ExportMode {
        case sameFolder
        case customFolder
    }

    @State private var inputURLs: [URL] = []
    @State private var status: String = ""

    @State private var exportMode: ExportMode = .sameFolder
    @State private var customExportDir: URL?

    /// “提升质量”开关：优先尝试调用 Real-ESRGAN（内嵌优先；否则可回退下载），失败则回退插值。
    @State private var preferAIUpscale: Bool = true

    /// 选择文件夹导入时是否递归扫描
    @State private var recursiveScan: Bool = false

    /// 批量导出时的运行态
    @State private var isRunning: Bool = false
    @State private var progressText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.12))

                VStack(spacing: 8) {
                    Text(inputURLs.isEmpty ? "拖拽 PNG（支持多张）到这里" : "已选择：\(inputURLs.count) 张")
                        .font(.headline)
                    Text("也可以点“选择图片…”或“选择文件夹…”。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .frame(height: 140)
            .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
                var added = false
                for p in providers {
                    _ = p.loadObject(ofClass: URL.self) { url, _ in
                        if let url { addURLs([url]) }
                    }
                    added = true
                }
                return added
            }

            HStack(spacing: 10) {
                Button("选择图片") {
                    pickImages()
                }.foregroundStyle(.foreground)
                Button("选择文件夹") { pickFolder() }

                Toggle("递归", isOn: $recursiveScan)
                    .toggleStyle(.switch)
                    .help("选择文件夹时，是否递归扫描子目录")

                Button("清空") {
                    inputURLs.removeAll()
                    status = ""
                    progressText = ""
                }
                .disabled(inputURLs.isEmpty || isRunning)

                Button("打开 Real-ESRGAN 目录") { openRealESRGANDir() }

                Spacer()

                Button(isRunning ? "处理中…" : "批量导出") {
                    Task { await exportBatchAsync() }
                }
                .disabled(inputURLs.isEmpty || isRunning || (exportMode == .customFolder && customExportDir == nil))
            }

            if !inputURLs.isEmpty {
                GroupBox("文件列表") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(inputURLs, id: \.self) { url in
                                HStack {
                                    Text(url.lastPathComponent)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                    Button {
                                        inputURLs.removeAll { $0 == url }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isRunning)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 140)
                }
            }

            GroupBox("放大/质量") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("提升质量（优先内嵌 Real-ESRGAN；无则插值）", isOn: $preferAIUpscale)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Real-ESRGAN 安装/缓存目录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(RealESRGANManager.shared.installDirPathHint)
                            .font(.caption)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }

                    Text("提示：批量处理时，只有当输入文件名包含 @2x 且需要生成 @3x 时才会触发 AI 放大。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(5)
            }

            GroupBox("导出目录") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: Binding(
                        get: { exportMode == .sameFolder ? 0 : 1 },
                        set: { exportMode = ($0 == 0) ? .sameFolder : .customFolder }
                    )) {
                        Text("同一文件夹（每张图各自目录）").tag(0)
                        Text("统一导出到指定目录").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if exportMode == .customFolder {
                        HStack(spacing: 5) {
                            Button("选择导出目录") { pickExportDir() }
                                .disabled(isRunning)
                            if let customExportDir {
                                Text(customExportDir.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text("未选择")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("将导出到每张输入图片所在目录。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(5)
            }

            if !progressText.isEmpty {
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !status.isEmpty {
                GroupBox("日志") {
                    ScrollView {
                        Text(status)
                            .font(.caption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                }
            }

            Spacer()
        }
        .padding()
        .navigationTitle("ScaleReducer")
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
        panel.allowedContentTypes = [.png]
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
            let urls = scanPNGs(in: dir, recursive: recursiveScan)
            addURLs(urls)
            if urls.isEmpty {
                status = appendLog(status, "⚠️ 文件夹内未找到 PNG：\(dir.path)")
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
        let filtered = urls
            .filter { $0.pathExtension.lowercased() == "png" }
            .map { $0.standardizedFileURL }

        DispatchQueue.main.async {
            let set = Set(inputURLs)
            let newOnes = filtered.filter { !set.contains($0) }
            inputURLs.append(contentsOf: newOnes)
            inputURLs.sort { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
        }
    }

    private func scanPNGs(in dir: URL, recursive: Bool) -> [URL] {
        let fm = FileManager.default
        let opts: FileManager.DirectoryEnumerationOptions = recursive ? [.skipsHiddenFiles] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: opts) else {
            return []
        }
        var out: [URL] = []
        for case let url as URL in e {
            if url.pathExtension.lowercased() == "png" {
                out.append(url)
            }
        }
        return out
    }

    // MARK: - Export

    private func resolveOutDir(for inputURL: URL) -> URL? {
        switch exportMode {
        case .sameFolder:
            return inputURL.deletingLastPathComponent()
        case .customFolder:
            return customExportDir
        }
    }

    @MainActor
    private func exportBatchAsync() async {
        if inputURLs.isEmpty { return }

        isRunning = true
        defer { isRunning = false }

        var ok = 0
        var failed = 0

        status = ""
        progressText = ""

        for (idx, url) in inputURLs.enumerated() {
            progressText = "处理中：\(idx + 1)/\(inputURLs.count) · \(url.lastPathComponent)"

            do {
                try await exportOneAsync(inputURL: url)
                ok += 1
                status = appendLog(status, "✅ \(url.lastPathComponent)")
            } catch {
                failed += 1
                status = appendLog(status, "❌ \(url.lastPathComponent) · \(error.localizedDescription)")
            }
        }

        progressText = "完成：成功 \(ok) / 失败 \(failed)"
    }

    private func exportOneAsync(inputURL: URL) async throws {
        guard let outDir = resolveOutDir(for: inputURL) else {
            throw NSError(domain: "IconKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "请先选择导出目录。"])
        }

        let data = try Data(contentsOf: inputURL)
        guard let srcRep = NSBitmapImageRep(data: data) else {
            throw NSError(domain: "IconKit", code: -2, userInfo: [NSLocalizedDescriptionKey: "无法解析 PNG。"])
        }

        let srcW = srcRep.pixelsWide
        let srcH = srcRep.pixelsHigh

        let inputName = inputURL.lastPathComponent
        let baseName = inputURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "@3x", with: "")
            .replacingOccurrences(of: "@2x", with: "")

        if inputName.contains("@3x") {
            if let out = renderPNG(from: srcRep, targetPixelsWide: srcW, targetPixelsHigh: srcH) {
                try out.write(to: outDir.appendingPathComponent("\(baseName)@3x.png"))
            }
            if let out = renderPNG(from: srcRep,
                                   targetPixelsWide: Int(round(Double(srcW) * 2.0 / 3.0)),
                                   targetPixelsHigh: Int(round(Double(srcH) * 2.0 / 3.0))) {
                try out.write(to: outDir.appendingPathComponent("\(baseName)@2x.png"))
            }
            if let out = renderPNG(from: srcRep,
                                   targetPixelsWide: Int(round(Double(srcW) / 3.0)),
                                   targetPixelsHigh: Int(round(Double(srcH) / 3.0))) {
                try out.write(to: outDir.appendingPathComponent("\(baseName).png"))
            }
        } else if inputName.contains("@2x") {
            if let out3x = try await make3xFrom2x(inputURL: inputURL, srcRep: srcRep) {
                try out3x.write(to: outDir.appendingPathComponent("\(baseName)@3x.png"))
            }
            if let out = renderPNG(from: srcRep, targetPixelsWide: srcW, targetPixelsHigh: srcH) {
                try out.write(to: outDir.appendingPathComponent("\(baseName)@2x.png"))
            }
            if let out = renderPNG(from: srcRep,
                                   targetPixelsWide: Int(round(Double(srcW) / 2.0)),
                                   targetPixelsHigh: Int(round(Double(srcH) / 2.0))) {
                try out.write(to: outDir.appendingPathComponent("\(baseName).png"))
            }
        } else {
            if let out = renderPNG(from: srcRep, targetPixelsWide: srcW, targetPixelsHigh: srcH) {
                try out.write(to: outDir.appendingPathComponent("\(baseName).png"))
            }
        }
    }

    /// @2x -> @3x：尽量提升质量。
    private func make3xFrom2x(inputURL: URL, srcRep: NSBitmapImageRep) async throws -> Data? {
        let srcW = srcRep.pixelsWide
        let srcH = srcRep.pixelsHigh
        let targetW = Int(round(Double(srcW) * 1.5))
        let targetH = Int(round(Double(srcH) * 1.5))

        if preferAIUpscale, let ai = try await aiUpscaleTo4x(inputURL: inputURL) {
            guard let rep4x = NSBitmapImageRep(data: ai) else {
                return renderPNG(from: srcRep, targetPixelsWide: targetW, targetPixelsHigh: targetH)
            }
            let w4 = rep4x.pixelsWide
            let h4 = rep4x.pixelsHigh
            let w3 = Int(round(Double(w4) * 0.75))
            let h3 = Int(round(Double(h4) * 0.75))
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

        guard proc.terminationStatus == 0 else {
            return nil
        }

        return try? Data(contentsOf: outURL)
    }

    private func renderPNG(from srcRep: NSBitmapImageRep, targetPixelsWide: Int, targetPixelsHigh: Int) -> Data? {
        let w = max(1, targetPixelsWide)
        let h = max(1, targetPixelsHigh)

        guard let dstRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: w,
            pixelsHigh: h,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        dstRep.size = CGSize(width: w, height: h)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let ctx = NSGraphicsContext(bitmapImageRep: dstRep) else { return nil }
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high

        NSColor.clear.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: w, height: h)).fill()

        let srcImage = NSImage(size: CGSize(width: srcRep.pixelsWide, height: srcRep.pixelsHigh))
        srcImage.addRepresentation(srcRep)

        srcImage.draw(in: CGRect(x: 0, y: 0, width: w, height: h),
                      from: CGRect(x: 0, y: 0, width: srcRep.pixelsWide, height: srcRep.pixelsHigh),
                      operation: .sourceOver,
                      fraction: 1.0,
                      respectFlipped: true,
                      hints: [.interpolation: NSImageInterpolation.high])

        return dstRep.representation(using: .png, properties: [:])
    }

    private func appendLog(_ current: String, _ line: String) -> String {
        if current.isEmpty { return line }
        return current + "\n" + line
    }
}

#Preview {
    NavigationStack { ScaleReducerView() }
}
