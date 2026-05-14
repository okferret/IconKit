import Foundation
import AppKit

// MARK: - AppleIconSet

enum AppleIconSet: String, CaseIterable, Identifiable {
    case iOS
    case watchOS
    case carPlay
    case iMessage
    case macOS
    case tvOS
    case visionOS

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iOS:      return "iOS / iPadOS"
        case .watchOS:  return "watchOS"
        case .carPlay:  return "CarPlay"
        case .iMessage: return "iMessage"
        case .macOS:    return "macOS"
        case .tvOS:     return "tvOS"
        case .visionOS: return "visionOS"
        }
    }
}

// MARK: - Errors

enum IconForgeError: LocalizedError {
    case invalidImage
    case cannotCreateDirectory(URL)
    case cannotWrite(URL)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "输入图片无效或无法渲染。"
        case .cannotCreateDirectory(let url):
            return "无法创建目录：\(url.path)"
        case .cannotWrite(let url):
            return "无法写入文件：\(url.path)"
        }
    }
}

// MARK: - IconExporter

struct IconExporter {

    /// 导出所有选中的 Apple 图标集
    /// 按 AppleIconSet.allCases 的稳定顺序遍历，确保输出目录顺序一致
    static func exportAppleAll(from image: NSImage, to outDir: URL, sets: Set<AppleIconSet>) throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        // 使用 allCases 保证稳定顺序，同时只处理 sets 中包含的项
        for set in AppleIconSet.allCases where sets.contains(set) {
            let setDir = outDir.appendingPathComponent("\(set.rawValue).appiconset", isDirectory: true)
            try exportAppleAppIconSet(from: image, to: setDir, kind: set)
        }
    }
    /// 生成 AppIcon.appiconset（含 Contents.json）
    static func exportAppleAppIconSet(from image: NSImage, to appIconSetDir: URL, kind: AppleIconSet) throws {
        try FileManager.default.createDirectory(at: appIconSetDir, withIntermediateDirectories: true)

        let specs = AppleIconSpec.specs(for: kind)
        var jsonImages: [[String: Any]] = []

        for spec in specs {
            let px = Int(round(spec.pointSize * spec.scale))
            // 用 pointSize + scale 共同构成唯一文件名，避免同 id 不同 scale 冲突
            let scaleStr = spec.scale == 1 ? "1x" : spec.scale == 2 ? "2x" : "3x"
            let fileName = "icon_\(spec.id)_\(scaleStr)_\(px)x\(px).png"
            let fileURL = appIconSetDir.appendingPathComponent(fileName)

            guard let png = ImageResizer.renderPNG(from: image, pixelSize: px) else {
                throw IconForgeError.invalidImage
            }
            try png.write(to: fileURL)

            var item: [String: Any] = [
                "filename": fileName,
                "idiom":    spec.idiom,
                "scale":    scaleStr,
                "size":     String(format: "%.4gx%.4g", spec.pointSize, spec.pointSize),
            ]
            if let role     = spec.role     { item["role"]     = role }
            if let subtype  = spec.subtype  { item["subtype"]  = subtype }
            if let platform = spec.platform { item["platform"] = platform }

            jsonImages.append(item)
        }

        let json: [String: Any] = [
            "images": jsonImages,
            "info": ["author": "IconKit", "version": 1]
        ]

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        let contentsURL = appIconSetDir.appendingPathComponent("Contents.json")
        try data.write(to: contentsURL)
    }
}

// MARK: - AppleIconSpec

struct AppleIconSpec {
    let idiom: String
    let pointSize: CGFloat
    let scale: CGFloat

    let role: String?
    let subtype: String?
    let platform: String?

    /// 用于文件名前缀（不含 scale，scale 单独拼接）
    let id: String

    // MARK: Convenience init
    init(_ idiom: String, _ pt: CGFloat, _ scale: CGFloat,
         role: String? = nil, subtype: String? = nil, platform: String? = nil, id: String) {
        self.idiom = idiom; self.pointSize = pt; self.scale = scale
        self.role = role; self.subtype = subtype; self.platform = platform; self.id = id
    }

    // MARK: Specs per platform

    static func specs(for kind: AppleIconSet) -> [AppleIconSpec] {
        switch kind {

        // ── iOS / iPadOS ──────────────────────────────────────────────────────
        case .iOS:
            return [
                // iPhone
                .init("iphone", 20,   2, id: "iphone20"),
                .init("iphone", 20,   3, id: "iphone20"),
                .init("iphone", 29,   2, id: "iphone29"),
                .init("iphone", 29,   3, id: "iphone29"),
                .init("iphone", 40,   2, id: "iphone40"),
                .init("iphone", 40,   3, id: "iphone40"),
                .init("iphone", 60,   2, id: "iphone60"),
                .init("iphone", 60,   3, id: "iphone60"),
                // iPad
                .init("ipad",   20,   1, id: "ipad20"),
                .init("ipad",   20,   2, id: "ipad20"),
                .init("ipad",   29,   1, id: "ipad29"),
                .init("ipad",   29,   2, id: "ipad29"),
                .init("ipad",   40,   1, id: "ipad40"),
                .init("ipad",   40,   2, id: "ipad40"),
                .init("ipad",   76,   1, id: "ipad76"),
                .init("ipad",   76,   2, id: "ipad76"),
                .init("ipad",   83.5, 2, id: "ipad83_5"),
                // App Store
                .init("ios-marketing", 1024, 1, id: "marketing1024"),
            ]

        // ── watchOS ───────────────────────────────────────────────────────────
        case .watchOS:
            return [
                .init("watch", 24,   2, role: "notificationCenter", subtype: "38mm",  id: "watch24_38"),
                .init("watch", 27.5, 2, role: "notificationCenter", subtype: "42mm",  id: "watch27_5_42"),
                .init("watch", 33,   2, role: "notificationCenter", subtype: "45mm",  id: "watch33_45"),
                .init("watch", 29,   2, role: "companionSettings",  id: "watch29"),
                .init("watch", 29,   3, role: "companionSettings",  id: "watch29"),
                .init("watch", 40,   2, role: "appLauncher", subtype: "38mm",  id: "watch40_38"),
                .init("watch", 44,   2, role: "appLauncher", subtype: "40mm",  id: "watch44_40"),
                .init("watch", 50,   2, role: "appLauncher", subtype: "44mm",  id: "watch50_44"),
                .init("watch", 46,   2, role: "appLauncher", subtype: "41mm",  id: "watch46_41"),
                .init("watch", 51,   2, role: "appLauncher", subtype: "45mm",  id: "watch51_45"),
                .init("watch", 54,   2, role: "appLauncher", subtype: "49mm",  id: "watch54_49"),
                .init("watch", 86,   2, role: "quickLook",   subtype: "38mm",  id: "watch86_38"),
                .init("watch", 98,   2, role: "quickLook",   subtype: "42mm",  id: "watch98_42"),
                .init("watch", 108,  2, role: "quickLook",   subtype: "45mm",  id: "watch108_45"),
                .init("watch-marketing", 1024, 1, id: "watchmarketing1024"),
            ]

        // ── CarPlay ───────────────────────────────────────────────────────────
        case .carPlay:
            return [
                .init("car", 60, 2, id: "car60"),
                .init("car", 60, 3, id: "car60"),
            ]

        // ── iMessage ──────────────────────────────────────────────────────────
        case .iMessage:
            return [
                .init("messages", 29,   2, subtype: "messaging", id: "msg29"),
                .init("messages", 29,   3, subtype: "messaging", id: "msg29"),
                .init("messages", 60,   2, subtype: "messaging", id: "msg60"),
                .init("messages", 60,   3, subtype: "messaging", id: "msg60"),
                .init("messages", 67,   2, subtype: "messages",  id: "msg67"),
                .init("messages", 1024, 1, subtype: "messages",  id: "msgmarketing1024"),
            ]

        // ── macOS ─────────────────────────────────────────────────────────────
        case .macOS:
            return [
                .init("mac", 16,  1, id: "mac16"),
                .init("mac", 16,  2, id: "mac16"),
                .init("mac", 32,  1, id: "mac32"),
                .init("mac", 32,  2, id: "mac32"),
                .init("mac", 128, 1, id: "mac128"),
                .init("mac", 128, 2, id: "mac128"),
                .init("mac", 256, 1, id: "mac256"),
                .init("mac", 256, 2, id: "mac256"),
                .init("mac", 512, 1, id: "mac512"),
                .init("mac", 512, 2, id: "mac512"),
            ]

        // ── tvOS ──────────────────────────────────────────────────────────────
        case .tvOS:
            return [
                .init("tv",             400, 1, id: "tv400"),
                .init("tv",             400, 2, id: "tv400"),
                .init("tv-marketing", 1280, 1, id: "tvmarketing1280"),
            ]

        // ── visionOS ──────────────────────────────────────────────────────────
        case .visionOS:
            return [
                .init("vision",            1024, 1, id: "vision1024"),
                .init("vision-marketing",  1024, 1, id: "visionmarketing1024"),
            ]
        }
    }
}
