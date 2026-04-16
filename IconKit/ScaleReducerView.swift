import SwiftUI
import AppKit

struct ScaleReducerView: View {
    enum ExportMode {
        case sameFolder
        case customFolder
    }

    @State private var inputURL: URL?
    @State private var status: String = ""

    @State private var exportMode: ExportMode = .sameFolder
    @State private var customExportDir: URL?

    /// “提升质量”开关：优先尝试自动下载并调用 Real-ESRGAN（参考 Upscayl 的底层方案），否则回退到高质量插值。
    @State private var preferAIUpscale: Bool = true

    private var fileName: String { inputURL?.lastPathComponent ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.12))

                VStack(spacing: 8) {
                    Text(inputURL == nil ? "拖拽 PNG（@3x/@2x）到这里" : "已载入：\(fileName)")
                        .font(.headline)
                    Text("也可以点“选择图片…”。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .frame(height: 140)
            .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { load(url) }
                }
                return true
            }

            HStack {
                Button("选择图片…") { pick() }
                Spacer()
                Button("导出（@3x/@2x/1x）") {
                    Task { await exportAsync() }
                }
                .disabled(inputURL == nil)
            }

            GroupBox("放大/质量") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("提升质量（自动下载并使用 Real-ESRGAN；无则插值）", isOn: $preferAIUpscale)
                    Text("说明：开启后会在首次使用时自动下载 realesrgan-ncnn-vulkan 到“应用支持目录”，无需系统安装。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }

            GroupBox("导出目录") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: Binding(
                        get: { exportMode == .sameFolder ? 0 : 1 },
                        set: { exportMode = ($0 == 0) ? .sameFolder : .customFolder }
                    )) {
                        Text("同一文件夹（默认）").tag(0)
                        Text("指定目录").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if exportMode == .customFolder {
                        HStack {
                            Button("选择导出目录…") { pickExportDir() }
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
                        Text("将导出到输入文件所在目录。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }

            Text("规则：\n• 输入 @3x：生成 3 个文件：@3x（重新渲染一份）、@2x（2/3）、1x（1/3）\n• 输入 @2x：生成 3 个文件：@3x（放大到 1.5x，尽量提升质量）、@2x（重新渲染一份）、1x（1/2）\n• 其他：生成 1x（重新渲染一份）")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !status.isEmpty {
                Text(status)
                    .font(.caption)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("导出图片")
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png]
        if panel.runModal() == .OK, let url = panel.url {
            load(url)
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

    private func load(_ url: URL) {
        DispatchQueue.main.async {
            inputURL = url
            status = ""
        }
    }

    private func resolveOutDir(for inputURL: URL) -> URL? {
        switch exportMode {
        case .sameFolder:
            return inputURL.deletingLastPathComponent()
        case .customFolder:
            return customExportDir
        }
    }

    @MainActor
    private func exportAsync() async {
        guard let inputURL else { return }
        guard let outDir = resolveOutDir(for: inputURL) else {
            status = "请先选择导出目录。"
            return
        }

        do {
            let data = try Data(contentsOf: inputURL)
            guard let srcRep = NSBitmapImageRep(data: data) else {
                status = "无法解析 PNG。"
                return
            }

            let srcW = srcRep.pixelsWide
            let srcH = srcRep.pixelsHigh

            let baseName = inputURL.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "@3x", with: "")
                .replacingOccurrences(of: "@2x", with: "")

            var written: [String] = []

            if fileName.contains("@3x") {
                if let out = renderPNG(from: srcRep, targetPixelsWide: srcW, targetPixelsHigh: srcH) {
                    let url = outDir.appendingPathComponent("\(baseName)@3x.png")
                    try out.write(to: url)
                    written.append(url.lastPathComponent)
                }
                if let out = renderPNG(from: srcRep,
                                       targetPixelsWide: Int(round(Double(srcW) * 2.0 / 3.0)),
                                       targetPixelsHigh: Int(round(Double(srcH) * 2.0 / 3.0))) {
                    let url = outDir.appendingPathComponent("\(baseName)@2x.png")
                    try out.write(to: url)
                    written.append(url.lastPathComponent)
                }
                if let out = renderPNG(from: srcRep,
                                       targetPixelsWide: Int(round(Double(srcW) / 3.0)),
                                       targetPixelsHigh: Int(round(Double(srcH) / 3.0))) {
                    let url = outDir.appendingPathComponent("\(baseName).png")
                    try out.write(to: url)
                    written.append(url.lastPathComponent)
                }
            } else if fileName.contains("@2x") {
                if let out3x = try await make3xFrom2x(inputURL: inputURL, srcRep: srcRep) {
                    let url = outDir.appendingPathComponent("\(baseName)@3x.png")
                    try out3x.write(to: url)
                    written.append(url.lastPathComponent)
                }

                if let out = renderPNG(from: srcRep, targetPixelsWide: srcW, targetPixelsHigh: srcH) {
                    let url = outDir.appendingPathComponent("\(baseName)@2x.png")
                    try out.write(to: url)
                    written.append(url.lastPathComponent)
                }
                if let out = renderPNG(from: srcRep,
                                       targetPixelsWide: Int(round(Double(srcW) / 2.0)),
                                       targetPixelsHigh: Int(round(Double(srcH) / 2.0))) {
                    let url = outDir.appendingPathComponent("\(baseName).png")
                    try out.write(to: url)
                    written.append(url.lastPathComponent)
                }
            } else {
                if let out = renderPNG(from: srcRep, targetPixelsWide: srcW, targetPixelsHigh: srcH) {
                    let url = outDir.appendingPathComponent("\(baseName).png")
                    try out.write(to: url)
                    written.append(url.lastPathComponent)
                }
            }

            status = written.isEmpty
                ? "没有生成任何文件。"
                : "已导出到：\(outDir.path)\n" + written.joined(separator: "\n")
        } catch {
            status = "导出失败：\(error.localizedDescription)"
        }
    }

    /// @2x -> @3x：尽量提升质量。
    /// - preferAIUpscale 开启：自动下载/调用 realesrgan-ncnn-vulkan 先 2x 到 @4x，再高质量缩回 @3x。
    /// - 否则：直接插值放大到 1.5x。
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

    /// Uses realesrgan-ncnn-vulkan (auto-installed) to upscale input by 2x -> output(@4x from @2x).
    private func aiUpscaleTo4x(inputURL: URL) async throws -> Data? {
        let tool: URL
        do {
            tool = try await RealESRGANManager.shared.ensureInstalled()
        } catch {
            return nil
        }

        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("IconForge", isDirectory: true)
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

        // make sure models can be found
        if let models = RealESRGANManager.shared.modelsDir() {
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
}

#Preview {
    NavigationStack { ScaleReducerView() }
}
