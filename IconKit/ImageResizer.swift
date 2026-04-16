import AppKit
import CoreGraphics

enum ImageResizer {
    /// Render to square PNG with transparent background (aspect-fit).
    static func renderPNG(from image: NSImage, pixelSize: Int) -> Data? {
        guard pixelSize > 0 else { return nil }

        let targetSize = CGSize(width: pixelSize, height: pixelSize)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { return nil }

        rep.size = targetSize

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high

        NSColor.clear.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()

        // aspect-fit
        let srcSize = image.size
        let scale = min(targetSize.width / srcSize.width, targetSize.height / srcSize.height)
        let drawSize = CGSize(width: srcSize.width * scale, height: srcSize.height * scale)
        let drawOrigin = CGPoint(
            x: (targetSize.width - drawSize.width) / 2,
            y: (targetSize.height - drawSize.height) / 2
        )
        image.draw(in: CGRect(origin: drawOrigin, size: drawSize),
                   from: .zero,
                   operation: .sourceOver,
                   fraction: 1.0,
                   respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high])

        return rep.representation(using: .png, properties: [:])
    }
}
