import Foundation
import Combine

// MARK: - RealESRGANManager

/// 管理 `realesrgan-ncnn-vulkan` 运行时。
///
/// 优先级：
/// 1. App Bundle 内嵌二进制：`Resources/RealESRGAN/realesrgan-ncnn-vulkan`
/// 2. Application Support 中已下载的版本
/// 3. 按需从 GitHub 下载最新 release
@MainActor
final class RealESRGANManager: ObservableObject {

    static let shared = RealESRGANManager()
    private init() {
        refreshState()
    }

    // MARK: - Install State

    enum InstallState: Equatable {
        case notInstalled
        case fetchingRelease
        case downloading(progress: Double)   // 0.0 ~ 1.0
        case extracting
        case installed(version: String)
        case failed(String)

        var isWorking: Bool {
            switch self {
            case .fetchingRelease, .downloading, .extracting: return true
            default: return false
            }
        }

        var isInstalled: Bool {
            if case .installed = self { return true }
            return false
        }

        var label: String {
            switch self {
            case .notInstalled:            return "未安装"
            case .fetchingRelease:         return "获取版本信息…"
            case .downloading(let p):      return String(format: "下载中 %.0f%%", p * 100)
            case .extracting:              return "解压中…"
            case .installed(let v):        return "已安装 \(v)"
            case .failed(let msg):         return "失败：\(msg)"
            }
        }

        var systemImage: String {
            switch self {
            case .notInstalled:   return "arrow.down.circle"
            case .fetchingRelease, .downloading, .extracting: return "arrow.down.circle.fill"
            case .installed:      return "checkmark.circle.fill"
            case .failed:         return "exclamationmark.triangle.fill"
            }
        }
    }

    // MARK: - Error

    enum ManagerError: LocalizedError {
        case noEmbeddedBinary
        case noReleaseAsset
        case downloadFailed(String)
        case unzipFailed(Int32)
        case binaryNotFound
        case processFailed(Int32, String)

        var errorDescription: String? {
            switch self {
            case .noEmbeddedBinary:
                return "App 内未内嵌 realesrgan-ncnn-vulkan 二进制。"
            case .noReleaseAsset:
                return "GitHub Release 中未找到适用于 macOS 的资源包。"
            case .downloadFailed(let detail):
                return "下载失败：\(detail)"
            case .unzipFailed(let code):
                return "解压失败（exit \(code)）。"
            case .binaryNotFound:
                return "安装后仍未找到 realesrgan-ncnn-vulkan 可执行文件。"
            case .processFailed(let code, let output):
                return "realesrgan-ncnn-vulkan 执行失败（exit \(code)）：\(output)"
            }
        }
    }

    // MARK: - Published State（主线程）

    @Published var installState: InstallState = .notInstalled
    /// 最新可用版本（检查更新后填充）
    @Published var latestVersion: String? = nil
    /// 是否有新版本可更新
    @Published var updateAvailable: Bool = false
    /// 检查更新的反馈信息（检查完成后短暂显示）
    @Published var checkFeedback: String? = nil
    /// 是否正在检查更新
    @Published var isCheckingUpdate: Bool = false

    // MARK: - Computed paths（纯计算，无 actor 隔离）

    /// `IconKit.app/Contents/Resources/RealESRGAN/realesrgan-ncnn-vulkan`
    var embeddedBinaryURL: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("RealESRGAN", isDirectory: true)
            .appendingPathComponent("realesrgan-ncnn-vulkan")
    }

    /// `IconKit.app/Contents/Resources/RealESRGAN/models`
    var embeddedModelsDir: URL? {
        guard let base = Bundle.main.resourceURL?
            .appendingPathComponent("RealESRGAN", isDirectory: true) else { return nil }
        let models = base.appendingPathComponent("models", isDirectory: true)
        return FileManager.default.fileExists(atPath: models.path) ? models : nil
    }

    // MARK: - Download paths

    struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
        let tag_name: String
        let assets: [Asset]
    }

    /// 实际安装目录（沙盒环境下位于容器内）。
    var installDirURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("IconKit/realesrgan", isDirectory: true)
    }

    var installDirPathHint: String {
        let p = installDirURL.path
        return p.contains("/Containers/") ? "(Sandbox) \(p)" : p
    }

    private var downloadedBinURL: URL {
        installDirURL.appendingPathComponent("realesrgan-ncnn-vulkan")
    }

    private var versionFileURL: URL {
        installDirURL.appendingPathComponent("version.txt")
    }

    // MARK: - Public API

    /// 刷新当前安装状态（不触发下载）。
    func refreshState() {
        if isAvailable {
            let ver = installedVersion ?? "内嵌版"
            installState = .installed(version: ver)
        } else {
            installState = .notInstalled
        }
        updateAvailable = false
    }

    /// 确保二进制可用，返回可执行文件 URL（供推理调用）。
    func ensureInstalled(preferEmbedded: Bool = true) async throws -> URL {
        // 1. 内嵌
        if preferEmbedded,
           let embedded = embeddedBinaryURL,
           FileManager.default.isExecutableFile(atPath: embedded.path) {
            return embedded
        }
        // 2. 已下载
        if FileManager.default.isExecutableFile(atPath: downloadedBinURL.path) {
            return downloadedBinURL
        }
        // 3. 按需下载
        try await downloadAndInstallLatest()
        guard FileManager.default.isExecutableFile(atPath: downloadedBinURL.path) else {
            throw ManagerError.binaryNotFound
        }
        return downloadedBinURL
    }

    /// 自动下载（若未安装）。供 UI 初始化时调用。
    func downloadIfNeeded() async {
        guard !installState.isWorking else { return }
        if isAvailable {
            refreshState()
            return
        }
        await performDownload()
    }

    /// 手动触发更新（强制重新下载最新版）。
    func forceUpdate() async {
        guard !installState.isWorking else { return }
        await performDownload(force: true)
    }

    /// 检查 GitHub 是否有新版本（不下载），并更新反馈信息。
    func checkForUpdate() async {
        guard !installState.isWorking, !isCheckingUpdate else { return }
        // 类本身已标注 @MainActor，直接赋值即可，无需 MainActor.run
        isCheckingUpdate = true
        checkFeedback = nil
        do {
            let release = try await fetchLatestRelease()
            let current = installedVersion ?? ""
            let hasUpdate = !current.isEmpty && current != release.tag_name
            latestVersion = release.tag_name
            updateAvailable = hasUpdate
            isCheckingUpdate = false
            if hasUpdate {
                checkFeedback = "发现新版本 \(release.tag_name)（当前 \(current)）"
            } else if current.isEmpty {
                checkFeedback = "最新版本：\(release.tag_name)"
            } else {
                checkFeedback = "已是最新版本 \(current) ✓"
            }
            // 3 秒后自动清除反馈
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !updateAvailable { checkFeedback = nil }
        } catch {
            let msg = error.localizedDescription
            isCheckingUpdate = false
            checkFeedback = "检查失败：\(msg)"
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            checkFeedback = nil
        }
    }

    /// 返回 models 目录（优先内嵌，其次已下载）。
    func modelsDir(preferEmbedded: Bool = true) -> URL? {
        if preferEmbedded, let m = embeddedModelsDir { return m }

        let direct = installDirURL.appendingPathComponent("models", isDirectory: true)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }

        let fm = FileManager.default
        if let enumerator = fm.enumerator(
            at: installDirURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                // 必须确认是目录，避免同名普通文件被误返回
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if url.lastPathComponent == "models" && isDir { return url }
            }
        }
        return nil
    }
    /// 检查是否有可用的二进制（不触发下载）。
    var isAvailable: Bool {
        if let embedded = embeddedBinaryURL,
           FileManager.default.isExecutableFile(atPath: embedded.path) { return true }
        return FileManager.default.isExecutableFile(atPath: downloadedBinURL.path)
    }

    /// 已安装版本号。
    var installedVersion: String? {
        // 优先读取下载版本号文件
        if let ver = try? String(contentsOf: versionFileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !ver.isEmpty {
            return ver
        }
        // 内嵌版本：读取 Bundle 内的 version.txt
        if let base = Bundle.main.resourceURL {
            let f = base.appendingPathComponent("RealESRGAN/version.txt")
            if let ver = try? String(contentsOf: f, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), !ver.isEmpty {
                return "内嵌 \(ver)"
            }
        }
        return nil
    }

    // MARK: - Private Download

    private func performDownload(force: Bool = false) async {
        do {
            try await downloadAndInstallLatest(force: force)
            let ver = installedVersion ?? "unknown"
            // 类本身已标注 @MainActor，直接赋值即可
            installState = .installed(version: ver)
            updateAvailable = false
        } catch {
            let msg = error.localizedDescription
            installState = .failed(msg)
        }
    }

    private func downloadAndInstallLatest(force: Bool = false) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: installDirURL, withIntermediateDirectories: true)

        // 类已标注 @MainActor，直接赋值即可
        installState = .fetchingRelease
        let release = try await fetchLatestRelease()

        // 若非强制更新且版本相同，跳过下载
        if !force, let current = installedVersion, current == release.tag_name, isAvailable {
            installState = .installed(version: current)
            return
        }

        guard let asset = pickMacOSAsset(from: release.assets) else {
            throw ManagerError.noReleaseAsset
        }

        let zipDest = installDirURL.appendingPathComponent(asset.name)
        let zipURL = try await downloadWithProgress(
            urlString: asset.browser_download_url,
            to: zipDest,
            onProgress: { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.installState = .downloading(progress: progress)
                }
            }
        )

        installState = .extracting
        try unzip(zipURL: zipURL, to: installDirURL)

        // 递归查找二进制并复制到标准位置
        if let found = findBinaryRecursively(in: installDirURL) {
            try? fm.removeItem(at: downloadedBinURL)
            try fm.copyItem(at: found, to: downloadedBinURL)
            try makeExecutable(downloadedBinURL)

            // 同步复制 models 目录（与二进制同级）
            let srcModels = found.deletingLastPathComponent()
                .appendingPathComponent("models", isDirectory: true)
            let dstModels = installDirURL.appendingPathComponent("models", isDirectory: true)
            if fm.fileExists(atPath: srcModels.path) {
                try? fm.removeItem(at: dstModels)
                try? fm.copyItem(at: srcModels, to: dstModels)
            }
        }

        // 保存版本号
        try? release.tag_name.data(using: .utf8)?.write(to: versionFileURL)

        // 清理 zip 及解压目录
        try? fm.removeItem(at: zipURL)
        let unzipDir = zipURL.deletingPathExtension()
        try? fm.removeItem(at: unzipDir)
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/xinntao/Real-ESRGAN-ncnn-vulkan/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw ManagerError.downloadFailed("HTTP \(http.statusCode)")
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func pickMacOSAsset(from assets: [GitHubRelease.Asset]) -> GitHubRelease.Asset? {
        assets.first {
            let n = $0.name.lowercased()
            return n.contains("mac") && n.hasSuffix(".zip")
        }
    }

    /// 带进度回调的下载
    private func downloadWithProgress(
        urlString: String,
        to dest: URL,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw ManagerError.downloadFailed("无效 URL：\(urlString)")
        }
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadProgressDelegate(
                dest: dest,
                onProgress: onProgress,
                completion: { continuation.resume(with: $0) }
            )
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            delegate.session = session
            session.downloadTask(with: url).resume()
        }
    }

    private func unzip(zipURL: URL, to dir: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-o", zipURL.path, "-d", dir.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = pipe
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw ManagerError.unzipFailed(proc.terminationStatus)
        }
    }

    private func findBinaryRecursively(in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator {
            if url.lastPathComponent == "realesrgan-ncnn-vulkan" { return url }
        }
        return nil
    }

    private func makeExecutable(_ url: URL) throws {
        let attr = try FileManager.default.attributesOfItem(atPath: url.path)
        let perm  = (attr[.posixPermissions] as? NSNumber)?.intValue ?? 0o644
        try FileManager.default.setAttributes(
            [.posixPermissions: (perm | 0o111) as NSNumber],
            ofItemAtPath: url.path
        )
    }
}

// MARK: - DownloadProgressDelegate

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    let dest: URL
    let onProgress: (Double) -> Void
    let completion: (Result<URL, Error>) -> Void
    var session: URLSession?

    /// 防止 didFinishDownloadingTo 和 didCompleteWithError 同时触发时 completion 被多次调用
    private var completed = false

    init(dest: URL,
         onProgress: @escaping (Double) -> Void,
         completion: @escaping (Result<URL, Error>) -> Void) {
        self.dest = dest
        self.onProgress = onProgress
        self.completion = completion
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard !completed else { return }
        completed = true
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
            completion(.success(dest))
        } catch {
            completion(.failure(error))
        }
        self.session = nil
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let error else { return }
        // 仅在尚未通过 didFinishDownloadingTo 完成时才回调
        guard !completed else { return }
        completed = true
        completion(.failure(error))
        self.session = nil
    }
}
