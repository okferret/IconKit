import AppKit
import CoreGraphics

// MARK: - ImageResizer

enum ImageResizer {

    // MARK: PNG

    /// 渲染为正方形 PNG（透明背景，aspect-fit，sRGB 色彩空间）。
    static func renderPNG(from image: NSImage, pixelSize: Int) -> Data? {
        guard let rep = makeRep(from: image, pixelSize: pixelSize) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: JPEG

    /// 渲染为正方形 JPEG（白色背景，aspect-fit，sRGB 色彩空间）。
    /// - Parameter quality: 0.0 ~ 1.0，默认 0.9
    static func renderJPEG(from image: NSImage, pixelSize: Int, quality: Double = 0.9) -> Data? {
        guard let rep = makeRep(from: image, pixelSize: pixelSize, opaqueBackground: true) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    // MARK: - Core render

    /// 核心渲染：返回 NSBitmapImageRep（sRGB，高质量插值）。
    /// - Parameter opaqueBackground: true 时用白色填充背景（适合 JPEG）；false 时透明（适合 PNG）。
    static func makeRep(from image: NSImage, pixelSize: Int, opaqueBackground: Bool = false) -> NSBitmapImageRep? {
        guard pixelSize > 0 else { return nil }

        let size = CGSize(width: pixelSize, height: pixelSize)

        // 使用 sRGB 色彩空间，保证颜色一致性
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let cgCtx = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        cgCtx.interpolationQuality = .high

        // 背景
        if opaqueBackground {
            cgCtx.setFillColor(CGColor.white)
            cgCtx.fill(CGRect(origin: .zero, size: size))
        } else {
            cgCtx.clear(CGRect(origin: .zero, size: size))
        }

        // aspect-fit 计算
        let srcSize = image.size
        guard srcSize.width > 0, srcSize.height > 0 else { return nil }
        let scale = min(CGFloat(pixelSize) / srcSize.width, CGFloat(pixelSize) / srcSize.height)
        let drawSize = CGSize(width: srcSize.width * scale, height: srcSize.height * scale)
        let drawOrigin = CGPoint(
            x: (CGFloat(pixelSize) - drawSize.width)  / 2,
            y: (CGFloat(pixelSize) - drawSize.height) / 2
        )
        let drawRect = CGRect(origin: drawOrigin, size: drawSize)

        // 通过 NSGraphicsContext 包装 CGContext 来绘制 NSImage
        let nsCtx = NSGraphicsContext(cgContext: cgCtx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        nsCtx.imageInterpolation = .high

        image.draw(in: drawRect,
                   from: .zero,
                   operation: .sourceOver,
                   fraction: 1.0,
                   respectFlipped: false,
                   hints: [.interpolation: NSImageInterpolation.high])

        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = cgCtx.makeImage() else { return nil }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = size
        return rep
    }

    // MARK: - Image info

    /// 返回图片的像素尺寸。
    ///
    /// 优先级：
    /// 1. 最大的 NSBitmapImageRep（像素尺寸最大者，适合多分辨率 TIFF）
    /// 2. 其他 rep 的 pixelsWide/pixelsHigh（PDF/矢量图会返回 0，需回退）
    /// 3. 回退到 image.size（逻辑点尺寸，矢量图场景）
    static func pixelSize(of image: NSImage) -> CGSize {
        // 找到像素面积最大的 BitmapImageRep
        let bestBitmap = image.representations
            .compactMap { $0 as? NSBitmapImageRep }
            .max { ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh) }

        if let rep = bestBitmap, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }

        // 对于 PDF/矢量图，尝试从任意 rep 获取非零尺寸
        for rep in image.representations {
            let w = rep.pixelsWide
            let h = rep.pixelsHigh
            if w > 0, h > 0 {
                return CGSize(width: w, height: h)
            }
        }

        // 最终回退：使用逻辑点尺寸（矢量图场景下 size 即为设计尺寸）
        return image.size
    }
}
