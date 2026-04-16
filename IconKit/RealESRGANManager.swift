import Foundation

/// Downloads and manages `realesrgan-ncnn-vulkan` runtime without requiring system install.
////Users/okferret/Downloads/IconKit/IconKit/RealESRGANManager.swift
/// Strategy:
/// - On first use, fetch latest release info from GitHub API
/// - Download a macOS zip asset
/// - Unzip into Application Support
/// - Mark binary executable and reuse next time
final class RealESRGANManager {
    static let shared = RealESRGANManager()

    private init() {}

    enum ManagerError: LocalizedError {
        case noReleaseAsset
        case downloadFailed
        case unzipFailed
        case binaryNotFound

        var errorDescription: String? {
            switch self {
            case .noReleaseAsset: return "未找到适用于 macOS 的 realesrgan-ncnn-vulkan release 资源。"
            case .downloadFailed: return "realesrgan-ncnn-vulkan 下载失败。"
            case .unzipFailed: return "realesrgan-ncnn-vulkan 解压失败。"
            case .binaryNotFound: return "realesrgan-ncnn-vulkan 可执行文件未找到。"
            }
        }
    }

    struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
        let assets: [Asset]
    }

    private var installDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("IconKit/realesrgan", isDirectory: true)
    }

    private var binURL: URL { installDir.appendingPathComponent("realesrgan-ncnn-vulkan") }

    /// Ensures binary exists locally, otherwise downloads and installs.
    func ensureInstalled() async throws -> URL {
        if FileManager.default.isExecutableFile(atPath: binURL.path) {
            return binURL
        }

        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        let release = try await fetchLatestRelease()
        guard let asset = pickMacOSAsset(from: release.assets) else {
            throw ManagerError.noReleaseAsset
        }

        let zipURL = try await download(urlString: asset.browser_download_url, to: installDir.appendingPathComponent(asset.name))
        try unzip(zipURL: zipURL, to: installDir)

        // common layouts: either directly contains binary, or inside a folder
        if FileManager.default.fileExists(atPath: binURL.path) {
            try makeExecutable(binURL)
            return binURL
        }

        // try find recursively
        if let found = findBinaryRecursively(in: installDir) {
            // move to expected location
            try? FileManager.default.removeItem(at: binURL)
            try FileManager.default.copyItem(at: found, to: binURL)
            try makeExecutable(binURL)
            return binURL
        }

        throw ManagerError.binaryNotFound
    }

    func modelsDir() -> URL? {
        // many releases ship a "models" folder
        let direct = installDir.appendingPathComponent("models", isDirectory: true)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }

        // or "realesrgan-ncnn-vulkan/models" etc.
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: installDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                if url.lastPathComponent == "models" {
                    return url
                }
            }
        }
        return nil
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/xinntao/Real-ESRGAN-ncnn-vulkan/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func pickMacOSAsset(from assets: [GitHubRelease.Asset]) -> GitHubRelease.Asset? {
        // Prefer Apple Silicon/Universal; fallback to any macos zip.
        let zips = assets.filter { $0.name.lowercased().contains("mac") && $0.name.lowercased().hasSuffix(".zip") }
        if let best = zips.first(where: { $0.name.lowercased().contains("arm") || $0.name.lowercased().contains("universal") }) {
            return best
        }
        return zips.first
    }

    private func download(urlString: String, to dest: URL) async throws -> URL {
        guard let url = URL(string: urlString) else { throw ManagerError.downloadFailed }
        let (tmp, resp) = try await URLSession.shared.download(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode ?? 0 < 400 else { throw ManagerError.downloadFailed }

        // replace existing
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    private func unzip(zipURL: URL, to dir: URL) throws {
        // Use system unzip to avoid adding SwiftPM deps
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
        // add user execute bit
        let newPerm = perm | 0o100
        try FileManager.default.setAttributes([.posixPermissions: newPerm], ofItemAtPath: url.path)
    }
}
