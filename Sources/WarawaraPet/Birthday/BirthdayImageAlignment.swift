import AppKit
import Foundation

/// Content-aware alignment helpers for birthday props. The square 1024
/// canvases carry inset painted content, so anchoring must use VISIBLE
/// alpha bounds — never the raw canvas bounds. Bounds are computed once
/// per image and cached (no per-frame scans).
enum BirthdayImageAlignment {
    struct ContentBounds: Equatable {
        let minX: Int
        let minY: Int
        let maxX: Int
        let maxY: Int
        let pixelWidth: Int
        let pixelHeight: Int

        var contentWidth: Int { maxX - minX + 1 }
        var contentHeight: Int { maxY - minY + 1 }
        var bottomGap: Int { pixelHeight - 1 - maxY }
        var aspectRatio: CGFloat {
            CGFloat(contentWidth) / CGFloat(max(contentHeight, 1))
        }
    }

    private static let lock = NSLock()
    private static var cache: [String: ContentBounds] = [:]

    /// Visible (alpha > threshold) content bounds of an NSImage, in
    /// pixel coordinates. Cached per key; sampling stride 2 keeps the
    /// one-time scan cheap (~260k samples).
    static func contentBounds(of image: NSImage, cacheKey: String) -> ContentBounds? {
        lock.lock()
        if let hit = cache[cacheKey] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.03 else { continue }
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let bounds = ContentBounds(
            minX: minX, minY: minY, maxX: maxX, maxY: maxY,
            pixelWidth: width, pixelHeight: height
        )
        lock.lock()
        cache[cacheKey] = bounds
        lock.unlock()
        return bounds
    }

    /// Uniform scale factor so the image's VISIBLE content width becomes
    /// `targetContentWidth` when the image is displayed in a frame of
    /// `canvasPoints` points.
    static func scaleForContentWidth(
        of image: NSImage,
        canvasPoints: CGFloat,
        targetContentWidth: CGFloat,
        cacheKey: String
    ) -> CGFloat {
        guard let bounds = contentBounds(of: image, cacheKey: cacheKey),
              bounds.contentWidth > 0 else { return 1 }
        let displayedContentWidth = CGFloat(bounds.contentWidth) * canvasPoints / CGFloat(bounds.pixelWidth)
        guard displayedContentWidth > 0 else { return 1 }
        return targetContentWidth / displayedContentWidth
    }

    /// Displayed content width for an image rendered in a
    /// `canvasPoints` frame with the given scale (verification helper).
    static func displayedContentWidth(
        of image: NSImage,
        canvasPoints: CGFloat,
        scale: CGFloat,
        cacheKey: String
    ) -> CGFloat {
        guard let bounds = contentBounds(of: image, cacheKey: cacheKey) else { return canvasPoints }
        return CGFloat(bounds.contentWidth) * canvasPoints / CGFloat(bounds.pixelWidth) * scale
    }

    /// The image's visible content aspect ratio (width / height).
    static func aspectRatio(of image: NSImage, cacheKey: String) -> CGFloat? {
        contentBounds(of: image, cacheKey: cacheKey)?.aspectRatio
    }

    static func resetCacheForTesting() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }
}
