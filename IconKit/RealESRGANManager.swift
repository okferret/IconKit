import Foundation
import Combine
import SystemConfiguration

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

    // MARK: - Private State

    /// 用于防止多次并发检查时 sleep 结束后错误清除反馈信息
    private var currentCheckID: UUID = UUID()

    // MARK: - GitHub Token

    private static let tokenKey = "com.iconkit.github.token"

    /// 当前保存的 GitHub Personal Access Token（存储于 UserDefaults）。
    /// 设置后自动持久化；置为 nil 或空字符串时删除。
    var githubToken: String? {
        get {
            let v = UserDefaults.standard.string(forKey: Self.tokenKey)
            return (v?.isEmpty == false) ? v : nil
        }
        set {
            if let v = newValue, !v.isEmpty {
                UserDefaults.standard.set(v, forKey: Self.tokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.tokenKey)
            }
        }
    }

    /// Token 是否已配置
    var hasGitHubToken: Bool { !(githubToken ?? "").isEmpty }

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
        // 记录本次检查的任务 ID，防止 sleep 结束后被后续检查的结果覆盖
        let checkID = UUID()
        currentCheckID = checkID
        do {
            let release = try await fetchLatestRelease()
            let currentRaw = installedVersion ?? ""
            let currentTag = currentRaw.hasPrefix("内嵌 ") ? String(currentRaw.dropFirst(3)) : currentRaw
            let hasUpdate = !currentTag.isEmpty && currentTag != release.tag_name
            latestVersion = release.tag_name
            updateAvailable = hasUpdate
            isCheckingUpdate = false
            if hasUpdate {
                checkFeedback = "发现新版本 \(release.tag_name)（当前 \(currentRaw)）"
            } else if currentTag.isEmpty {
                checkFeedback = "最新版本：\(release.tag_name)"
            } else {
                checkFeedback = "已是最新版本 \(currentRaw) ✓"
            }
            // 3 秒后自动清除反馈（仅当本次检查仍是最新一次时才清除）
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if currentCheckID == checkID, !updateAvailable { checkFeedback = nil }
        } catch {
            let msg = error.localizedDescription
            isCheckingUpdate = false
            checkFeedback = "检查失败：\(msg)"
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if currentCheckID == checkID { checkFeedback = nil }
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

    // MARK: - Proxy-Aware URLSession

    /// 检测系统当前代理设置，返回代理感知的 URLSessionConfiguration。
    ///
    /// 直接将 CFNetworkCopySystemProxySettings() 返回的原始字典赋给
    /// connectionProxyDictionary，确保 URLSession 使用系统代理。
    private func makeProxyAwareConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default

        if let proxySettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as NSDictionary? {
            // 直接使用原始字典，key 已是 CFString/NSString，与 connectionProxyDictionary 兼容
            config.connectionProxyDictionary = proxySettings as? [AnyHashable: Any]
            print("[RealESRGAN] 代理配置已注入: HTTPProxy=\(proxySettings["HTTPProxy"] ?? "nil"):\(proxySettings["HTTPPort"] ?? "nil") HTTPSProxy=\(proxySettings["HTTPSProxy"] ?? "nil"):\(proxySettings["HTTPSPort"] ?? "nil")")
        } else {
            print("[RealESRGAN] 未检测到系统代理配置，使用直连")
        }

        return config
    }

    /// 构建带标准请求头的 URLRequest（GitHub API 及文件下载通用）。
    private func makeRequest(url: URL, timeoutInterval: TimeInterval = 30) -> URLRequest {
        var req = URLRequest(url: url)
        req.timeoutInterval = timeoutInterval
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("IconKit/1.0 (macOS; Swift)", forHTTPHeaderField: "User-Agent")
        return req
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
        // 注意：installedVersion 对内嵌版本返回 "内嵌 vX.X.X"，需去除前缀后再比较
        let currentRaw = installedVersion ?? ""
        let currentTag = currentRaw.hasPrefix("内嵌 ") ? String(currentRaw.dropFirst(3)) : currentRaw
        if !force, !currentTag.isEmpty, currentTag == release.tag_name, isAvailable {
            installState = .installed(version: currentRaw)
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
        var req = makeRequest(url: url, timeoutInterval: 15)

        // 若设置了 GitHub Token，注入认证头以提升 API 速率限制（60→5000次/小时）
        // 优先级：Keychain 存储的 Token > 环境变量 GITHUB_TOKEN
        let keychainToken = githubToken
        let envToken = ProcessInfo.processInfo.environment["GITHUB_TOKEN"]
        let token = keychainToken ?? envToken

        print("[RealESRGAN] fetchLatestRelease: keychainToken=\(keychainToken != nil ? "已设置(\(keychainToken!.prefix(8))...)" : "nil") envToken=\(envToken != nil ? "已设置" : "nil")")

        if let token, !token.isEmpty {
            // GitHub API 支持 token 和 Bearer 两种格式
            // Fine-grained token (github_pat_) 和 classic token (ghp_) 均使用 token 前缀
            req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
            print("[RealESRGAN] 已注入 Authorization 头，token 前缀: \(token.prefix(4))")
        } else {
            print("[RealESRGAN] 未配置 Token，使用匿名请求（限速 60次/小时）")
        }

        // 使用代理感知的 URLSession
        let session = URLSession(configuration: makeProxyAwareConfiguration())
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            print("[RealESRGAN] fetchLatestRelease 失败 HTTP \(http.statusCode) url=\(http.url?.absoluteString ?? "?") body=\(body)")
            // 速率限制时给出更友好的错误提示
            if http.statusCode == 403, body.contains("rate limit") {
                throw ManagerError.downloadFailed("GitHub API 速率限制，请稍后重试或配置 GitHub Token")
            }
            if http.statusCode == 401 {
                throw ManagerError.downloadFailed("GitHub Token 无效或已过期，请重新配置")
            }
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
        print("[RealESRGAN] 开始下载 url=\(urlString)")
        // 构建带 User-Agent 的请求，避免某些代理/CDN 因缺少 UA 而返回 403
        let req = makeRequest(url: url, timeoutInterval: 60)
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadProgressDelegate(
                dest: dest,
                onProgress: onProgress,
                completion: { result in
                    switch result {
                    case .success(let u):
                        print("[RealESRGAN] 下载成功 dest=\(u.path)")
                    case .failure(let e):
                        print("[RealESRGAN] 下载失败 error=\(e)")
                    }
                    continuation.resume(with: result)
                }
            )
            // 使用代理感知的配置，确保下载时也能走系统代理
            // 注意：URLSession 强引用 delegate，delegate 通过 weak 引用 session，避免循环引用
            let session = URLSession(configuration: makeProxyAwareConfiguration(), delegate: delegate, delegateQueue: nil)
            delegate.session = session
            let task = session.downloadTask(with: req)
            task.resume()
            // 持有 session 直到任务完成，防止提前释放
            _ = session
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
    /// 使用 weak 引用避免与 URLSession 形成循环引用
    /// （URLSession 强引用 delegate，delegate 弱引用 session）
    weak var session: URLSession?

    /// 防止 didFinishDownloadingTo 和 didCompleteWithError 同时触发时 completion 被多次调用
    private var completed = false

    init(dest: URL,
         onProgress: @escaping (Double) -> Void,
         completion: @escaping (Result<URL, Error>) -> Void) {
        self.dest = dest
        self.onProgress = onProgress
        self.completion = completion
    }

    // 处理 HTTP 重定向（GitHub Release 下载会 302 跳转到 objects.githubusercontent.com）
    // 默认实现会跟随重定向但可能丢失自定义请求头，此处显式保留 User-Agent
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        var redirectRequest = request
        print("[RealESRGAN] 重定向 \(response.statusCode) -> \(request.url?.absoluteString ?? "?")")
        // 保留 User-Agent，防止重定向后被 CDN/代理拦截返回 403
        if redirectRequest.value(forHTTPHeaderField: "User-Agent") == nil {
            redirectRequest.setValue("IconKit/1.0 (macOS; Swift)", forHTTPHeaderField: "User-Agent")
        }
        completionHandler(redirectRequest)
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

