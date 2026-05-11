import Foundation

// MARK: - RealESRGANManager

/// 管理 `realesrgan-ncnn-vulkan` 运行时。
///
/// 优先级：
/// 1. App Bundle 内嵌二进制：`Resources/RealESRGAN/realesrgan-ncnn-vulkan`
/// 2. 回退到 Application Support 中已下载的版本
/// 3. 按需从 GitHub 下载最新 release
final class RealESRGANManager {

    static let shared = RealESRGANManager()
    private init() {}

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

    // MARK: - Embedded paths

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

    // MARK: - Public API

    /// 确保二进制可用，返回可执行文件 URL。
    /// - Parameter preferEmbedded: 优先使用 Bundle 内嵌版本（默认 true）。
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

    /// 返回 models 目录（优先内嵌，其次已下载）。
    func modelsDir(preferEmbedded: Bool = true) -> URL? {
        if preferEmbedded, let m = embeddedModelsDir { return m }

        let direct = installDirURL.appendingPathComponent("models", isDirectory: true)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }

        // 递归查找
        let fm = FileManager.default
        if let enumerator = fm.enumerator(
            at: installDirURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                if url.lastPathComponent == "models" { return url }
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

    // MARK: - Download & Install

    private func downloadAndInstallLatest() async throws {
        try FileManager.default.createDirectory(at: installDirURL, withIntermediateDirectories: true)

        let release = try await fetchLatestRelease()
        guard let asset = pickMacOSAsset(from: release.assets) else {
            throw ManagerError.noReleaseAsset
        }

        let zipDest = installDirURL.appendingPathComponent(asset.name)
        let zipURL  = try await download(urlString: asset.browser_download_url, to: zipDest)
        try unzip(zipURL: zipURL, to: installDirURL)

        // 递归查找二进制并移动到标准位置
        if let found = findBinaryRecursively(in: installDirURL) {
            try? FileManager.default.removeItem(at: downloadedBinURL)
            try FileManager.default.copyItem(at: found, to: downloadedBinURL)
            try makeExecutable(downloadedBinURL)
        }

        // 清理 zip 及解压目录
        try? FileManager.default.removeItem(at: zipURL)
        let unzipDir = zipURL.deletingPathExtension()
        try? FileManager.default.removeItem(at: unzipDir)
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

    private func download(urlString: String, to dest: URL) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw ManagerError.downloadFailed("无效 URL：\(urlString)")
        }
        let (tmp, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw ManagerError.downloadFailed("HTTP \(http.statusCode)")
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
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
