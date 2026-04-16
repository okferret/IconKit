import Foundation
import AppKit

enum AppleIconSet: String, CaseIterable, Identifiable {
    case iOS
    case watchOS
    case carPlay
    case iMessage
    case macOS

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iOS: return "iOS"
        case .watchOS: return "watchOS"
        case .carPlay: return "CarPlay"
        case .iMessage: return "iMessage"
        case .macOS: return "macOS"
        }
    }
}

enum IconForgeError: LocalizedError {
    case invalidImage
    case cannotCreateDirectory(URL)
    case cannotWrite(URL)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "输入图片无效。"
        case .cannotCreateDirectory(let url):
            return "无法创建目录：\(url.path)"
        case .cannotWrite(let url):
            return "无法写入文件：\(url.path)"
        }
    }
}

struct IconExporter {

    static func exportAppleAll(from image: NSImage, to outDir: URL, sets: Set<AppleIconSet>) throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        for set in sets {
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
            let fileName = "icon_\(spec.id)_\(px)x\(px).png"
            let fileURL = appIconSetDir.appendingPathComponent(fileName)

            guard let png = ImageResizer.renderPNG(from: image, pixelSize: px) else {
                throw IconForgeError.invalidImage
            }
            try png.write(to: fileURL)

            var item: [String: Any] = [
                "idiom": spec.idiom,
                "size": String(format: "%.0fx%.0f", spec.pointSize, spec.pointSize),
                "scale": String(format: "%.0fx", spec.scale),
                "filename": fileName
            ]
            if let role = spec.role { item["role"] = role }
            if let subtype = spec.subtype { item["subtype"] = subtype }
            if let platform = spec.platform { item["platform"] = platform }

            jsonImages.append(item)
        }

        let json: [String: Any] = [
            "images": jsonImages,
            "info": ["author": "IconForge", "version": 1]
        ]

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        let contentsURL = appIconSetDir.appendingPathComponent("Contents.json")
        try data.write(to: contentsURL)
    }
}

struct AppleIconSpec {
    let idiom: String
    let pointSize: CGFloat
    let scale: CGFloat

    // extra fields for some sets
    let role: String?
    let subtype: String?
    let platform: String?

    /// used only for deterministic filenames
    let id: String

    static func specs(for kind: AppleIconSet) -> [AppleIconSpec] {
        switch kind {
        case .iOS:
            // iOS AppIcon (common subset; includes iPad)
            return [
                .init(idiom: "iphone", pointSize: 20, scale: 2, role: nil, subtype: nil, platform: nil, id: "iphone20"),
                .init(idiom: "iphone", pointSize: 20, scale: 3, role: nil, subtype: nil, platform: nil, id: "iphone20"),
                .init(idiom: "iphone", pointSize: 29, scale: 2, role: nil, subtype: nil, platform: nil, id: "iphone29"),
                .init(idiom: "iphone", pointSize: 29, scale: 3, role: nil, subtype: nil, platform: nil, id: "iphone29"),
                .init(idiom: "iphone", pointSize: 40, scale: 2, role: nil, subtype: nil, platform: nil, id: "iphone40"),
                .init(idiom: "iphone", pointSize: 40, scale: 3, role: nil, subtype: nil, platform: nil, id: "iphone40"),
                .init(idiom: "iphone", pointSize: 60, scale: 2, role: nil, subtype: nil, platform: nil, id: "iphone60"),
                .init(idiom: "iphone", pointSize: 60, scale: 3, role: nil, subtype: nil, platform: nil, id: "iphone60"),

                .init(idiom: "ipad", pointSize: 20, scale: 1, role: nil, subtype: nil, platform: nil, id: "ipad20"),
                .init(idiom: "ipad", pointSize: 20, scale: 2, role: nil, subtype: nil, platform: nil, id: "ipad20"),
                .init(idiom: "ipad", pointSize: 29, scale: 1, role: nil, subtype: nil, platform: nil, id: "ipad29"),
                .init(idiom: "ipad", pointSize: 29, scale: 2, role: nil, subtype: nil, platform: nil, id: "ipad29"),
                .init(idiom: "ipad", pointSize: 40, scale: 1, role: nil, subtype: nil, platform: nil, id: "ipad40"),
                .init(idiom: "ipad", pointSize: 40, scale: 2, role: nil, subtype: nil, platform: nil, id: "ipad40"),
                .init(idiom: "ipad", pointSize: 76, scale: 1, role: nil, subtype: nil, platform: nil, id: "ipad76"),
                .init(idiom: "ipad", pointSize: 76, scale: 2, role: nil, subtype: nil, platform: nil, id: "ipad76"),
                .init(idiom: "ipad", pointSize: 83.5, scale: 2, role: nil, subtype: nil, platform: nil, id: "ipad83_5"),

                // App Store
                .init(idiom: "ios-marketing", pointSize: 1024, scale: 1, role: nil, subtype: nil, platform: nil, id: "marketing1024")
            ]

        case .watchOS:
            return [
                .init(idiom: "watch", pointSize: 24, scale: 2, role: "notificationCenter", subtype: "38mm", platform: nil, id: "watch24_38"),
                .init(idiom: "watch", pointSize: 27.5, scale: 2, role: "notificationCenter", subtype: "42mm", platform: nil, id: "watch27_5_42"),
                .init(idiom: "watch", pointSize: 33, scale: 2, role: "notificationCenter", subtype: "45mm", platform: nil, id: "watch33_45"),

                .init(idiom: "watch", pointSize: 29, scale: 2, role: "companionSettings", subtype: nil, platform: nil, id: "watch29"),
                .init(idiom: "watch", pointSize: 29, scale: 3, role: "companionSettings", subtype: nil, platform: nil, id: "watch29"),

                .init(idiom: "watch", pointSize: 40, scale: 2, role: "appLauncher", subtype: "38mm", platform: nil, id: "watch40_38"),
                .init(idiom: "watch", pointSize: 44, scale: 2, role: "appLauncher", subtype: "40mm", platform: nil, id: "watch44_40"),
                .init(idiom: "watch", pointSize: 50, scale: 2, role: "appLauncher", subtype: "44mm", platform: nil, id: "watch50_44"),
                .init(idiom: "watch", pointSize: 46, scale: 2, role: "appLauncher", subtype: "41mm", platform: nil, id: "watch46_41"),
                .init(idiom: "watch", pointSize: 51, scale: 2, role: "appLauncher", subtype: "45mm", platform: nil, id: "watch51_45"),
                .init(idiom: "watch", pointSize: 54, scale: 2, role: "appLauncher", subtype: "49mm", platform: nil, id: "watch54_49"),

                .init(idiom: "watch", pointSize: 86, scale: 2, role: "quickLook", subtype: "38mm", platform: nil, id: "watch86_38"),
                .init(idiom: "watch", pointSize: 98, scale: 2, role: "quickLook", subtype: "42mm", platform: nil, id: "watch98_42"),
                .init(idiom: "watch", pointSize: 108, scale: 2, role: "quickLook", subtype: "45mm", platform: nil, id: "watch108_45"),

                .init(idiom: "watch-marketing", pointSize: 1024, scale: 1, role: nil, subtype: nil, platform: nil, id: "watchmarketing1024")
            ]

        case .carPlay:
            return [
                .init(idiom: "car", pointSize: 60, scale: 2, role: nil, subtype: nil, platform: nil, id: "car60"),
                .init(idiom: "car", pointSize: 60, scale: 3, role: nil, subtype: nil, platform: nil, id: "car60")
            ]

        case .iMessage:
            return [
                .init(idiom: "messages", pointSize: 29, scale: 2, role: nil, subtype: "messaging", platform: nil, id: "msg29"),
                .init(idiom: "messages", pointSize: 29, scale: 3, role: nil, subtype: "messaging", platform: nil, id: "msg29"),
                .init(idiom: "messages", pointSize: 60, scale: 2, role: nil, subtype: "messaging", platform: nil, id: "msg60"),
                .init(idiom: "messages", pointSize: 60, scale: 3, role: nil, subtype: "messaging", platform: nil, id: "msg60"),
                .init(idiom: "messages", pointSize: 67, scale: 2, role: nil, subtype: "messages", platform: nil, id: "msg67"),

                .init(idiom: "messages", pointSize: 1024, scale: 1, role: nil, subtype: "messages", platform: nil, id: "msgmarketing1024")
            ]

        case .macOS:
            // macOS app icon set sizes
            return [
                .init(idiom: "mac", pointSize: 16, scale: 1, role: nil, subtype: nil, platform: nil, id: "mac16"),
                .init(idiom: "mac", pointSize: 16, scale: 2, role: nil, subtype: nil, platform: nil, id: "mac16"),
                .init(idiom: "mac", pointSize: 32, scale: 1, role: nil, subtype: nil, platform: nil, id: "mac32"),
                .init(idiom: "mac", pointSize: 32, scale: 2, role: nil, subtype: nil, platform: nil, id: "mac32"),
                .init(idiom: "mac", pointSize: 128, scale: 1, role: nil, subtype: nil, platform: nil, id: "mac128"),
                .init(idiom: "mac", pointSize: 128, scale: 2, role: nil, subtype: nil, platform: nil, id: "mac128"),
                .init(idiom: "mac", pointSize: 256, scale: 1, role: nil, subtype: nil, platform: nil, id: "mac256"),
                .init(idiom: "mac", pointSize: 256, scale: 2, role: nil, subtype: nil, platform: nil, id: "mac256"),
                .init(idiom: "mac", pointSize: 512, scale: 1, role: nil, subtype: nil, platform: nil, id: "mac512"),
                .init(idiom: "mac", pointSize: 512, scale: 2, role: nil, subtype: nil, platform: nil, id: "mac512")
            ]
        }
    }
}
