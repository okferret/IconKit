import Foundation

/// Manages `realesrgan-ncnn-vulkan` runtime.
///
/// Priority:
/// 1) Prefer **embedded binary** in app bundle: `Resources/RealESRGAN/realesrgan-ncnn-vulkan`
/// 2) Fallback to **auto-download** into Application Support (optional)
final class RealESRGANManager {
    static let shared = RealESRGANManager()
    private init() {}

    enum ManagerError: LocalizedError {
        case noEmbeddedBinary
        case noReleaseAsset
        case downloadFailed
        case unzipFailed
        case binaryNotFound

        var errorDescription: String? {
            switch self {
            case .noEmbeddedBinary: return "App 内未内嵌 realesrgan-ncnn-vulkan。"
            case .noReleaseAsset: return "未找到适用于 macOS 的 realesrgan-ncnn-vulkan release 资源。"
            case .downloadFailed: return "realesrgan-ncnn-vulkan 下载失败。"
            case .unzipFailed: return "realesrgan-ncnn-vulkan 解压失败。"
            case .binaryNotFound: return "realesrgan-ncnn-vulkan 可执行文件未找到。"
            }
        }
    }

    // MARK: - Embedded

    /// `IconKit.app/Contents/Resources/RealESRGAN/realesrgan-ncnn-vulkan`
    var embeddedBinaryURL: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("RealESRGAN", isDirectory: true)
            .appendingPathComponent("realesrgan-ncnn-vulkan")
    }

    /// `IconKit.app/Contents/Resources/RealESRGAN/models`
    var embeddedModelsDir: URL? {
        guard let base = Bundle.main.resourceURL?.appendingPathComponent("RealESRGAN", isDirectory: true) else {
            return nil
        }
        let models = base.appendingPathComponent("models", isDirectory: true)
        return FileManager.default.fileExists(atPath: models.path) ? models : nil
    }

    // MARK: - Download fallback (optional)

    struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
        let assets: [Asset]
    }

    /// Actual install directory (may be inside App Sandbox container).
    var installDirURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("IconKit/realesrgan", isDirectory: true)
    }

    var installDirPathHint: String {
        let p = installDirURL.path
        if p.contains("/Containers/") { return "(Sandbox) \(p)" }
        return p
    }

    private var downloadedBinURL: URL { installDirURL.appendingPathComponent("realesrgan-ncnn-vulkan") }

    /// Ensures binary exists.
    /// - If embedded in bundle, returns embedded path.
    /// - Else fallback to downloaded binary (download on demand).
    func ensureInstalled(preferEmbedded: Bool = true) async throws -> URL {
        if preferEmbedded, let embedded = embeddedBinaryURL, FileManager.default.isExecutableFile(atPath: embedded.path) {
            return embedded
        }

        if FileManager.default.isExecutableFile(atPath: downloadedBinURL.path) {
            return downloadedBinURL
        }

        try await downloadAndInstallLatest()
        guard FileManager.default.isExecutableFile(atPath: downloadedBinURL.path) else {
            throw ManagerError.binaryNotFound
        }
        return downloadedBinURL
    }

    func modelsDir(preferEmbedded: Bool = true) -> URL? {
        if preferEmbedded, let m = embeddedModelsDir { return m }

        let direct = installDirURL.appendingPathComponent("models", isDirectory: true)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }

        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: installDirURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                if url.lastPathComponent == "models" {
                    return url
                }
            }
        }
        return nil
    }

    // MARK: - Download latest

    private func downloadAndInstallLatest() async throws {
        try FileManager.default.createDirectory(at: installDirURL, withIntermediateDirectories: true)

        let release = try await fetchLatestRelease()
        guard let asset = pickMacOSAsset(from: release.assets) else {
            throw ManagerError.noReleaseAsset
        }

        let zipURL = try await download(urlString: asset.browser_download_url, to: installDirURL.appendingPathComponent(asset.name))
        try unzip(zipURL: zipURL, to: installDirURL)

        // try find binary recursively
        if let found = findBinaryRecursively(in: installDirURL) {
            try? FileManager.default.removeItem(at: downloadedBinURL)
            try FileManager.default.copyItem(at: found, to: downloadedBinURL)
            try makeExecutable(downloadedBinURL)
        }
        // clean files
        try? FileManager.default.removeItem(at: zipURL)
        try? FileManager.default.removeItem(at: zipURL.deletingPathExtension())
        
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/xinntao/Real-ESRGAN-ncnn-vulkan/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func pickMacOSAsset(from assets: [GitHubRelease.Asset]) -> GitHubRelease.Asset? {
        let zips = assets.filter { $0.name.lowercased().contains("mac") && $0.name.lowercased().hasSuffix(".zip") }
        return zips.first
    }

    private func download(urlString: String, to dest: URL) async throws -> URL {
        guard let url = URL(string: urlString) else { throw ManagerError.downloadFailed }
        let (tmp, resp) = try await URLSession.shared.download(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode ?? 0 < 400 else { throw ManagerError.downloadFailed }
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
        proc.standardError = pipe

        try proc.run()
        proc.waitUntilExit()

        guard proc.terminationStatus == 0 else {
            throw ManagerError.unzipFailed
        }
    }

    private func findBinaryRecursively(in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        for case let url as URL in enumerator {
            if url.lastPathComponent == "realesrgan-ncnn-vulkan" {
                return url
            }
        }
        return nil
    }

    private func makeExecutable(_ url: URL) throws {
        let attr = try FileManager.default.attributesOfItem(atPath: url.path)
        let perm = (attr[.posixPermissions] as? NSNumber)?.intValue ?? 0
        let newPerm = perm | 0o111 // add execute bits
        try FileManager.default.setAttributes([.posixPermissions: newPerm], ofItemAtPath: url.path)
    }
}
