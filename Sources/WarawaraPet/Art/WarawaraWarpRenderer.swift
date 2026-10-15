import AppKit
import CoreGraphics
import Foundation

/// Unified CoreGraphics renderer for the 2.5D body warp.
///
/// The warped body is rasterized in ONE coherent CoreGraphics pass into
/// a premultiplied RGBA buffer (no per-strip SwiftUI views, no separate
/// surfaces), so:
/// - the silhouette is continuous (adjacent strips share exact pixel
///   edges — no gaps, no overlaps, no independent edge filtering),
/// - far-side volume shading is applied by multiplying the ALREADY
///   DRAWN body pixels in-buffer — only pixels with alpha > 0 are
///   darkened, so shading can never escape the character outline (no
///   rectangular halo),
/// - the result is a single NSImage composited exactly like the
///   accepted neutral artwork (no offscreen Canvas class of artifacts).
///
/// Results are cached keyed by quantized angle (0.5-degree steps) and
/// canvas size; the warp renders only while the turn is active, and at
/// rest the cache is untouched.
enum WarawaraWarpRenderer {
    static let stripCount = 14

    private static var cache: [String: NSImage] = [:]
    private static var cacheOrder: [String] = []
    private static let cacheLimit = 32

    /// Returns the warped body image, or nil when the turn is inactive
    /// (caller keeps the plain accepted artwork).
    static func warpedBodyImage(
        body: NSImage,
        canvasSize: CGSize,
        bodyBounds: CGRect,
        yawDegrees: CGFloat,
        pitchDegrees: CGFloat,
        scale: CGFloat = 2,
        shadingEnabled: Bool = true
    ) -> NSImage? {
        guard WarawaraTurnGeometry.isActive(yawDegrees: yawDegrees, pitchDegrees: pitchDegrees) else {
            return nil
        }
        let key = "\(Int((yawDegrees * 2).rounded()))_\(Int((pitchDegrees * 2).rounded()))_\(Int(canvasSize.width))_\(Int(canvasSize.height))_\(Int(scale))_\(shadingEnabled ? 1 : 0)"
        if let hit = cache[key] {
            touch(key)
            return hit
        }
        guard let rendered = renderWarp(
            body: body,
            canvasSize: canvasSize,
            bodyBounds: bodyBounds,
            yawDegrees: yawDegrees,
            pitchDegrees: pitchDegrees,
            scale: scale,
            shadingEnabled: shadingEnabled
        ) else { return nil }
        cache[key] = rendered
        cacheOrder.append(key)
        if cacheOrder.count > cacheLimit {
            let evicted = cacheOrder.removeFirst()
            cache[evicted] = nil
        }
        return rendered
    }

    /// Diagnostic access to the underlying pixel pass.
    static func renderWarp(
        body: NSImage,
        canvasSize: CGSize,
        bodyBounds: CGRect,
        yawDegrees: CGFloat,
        pitchDegrees: CGFloat,
        scale: CGFloat,
        shadingEnabled: Bool
    ) -> NSImage? {
        guard let cg = body.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let pxW = max(Int((canvasSize.width * scale).rounded()), 1)
        let pxH = max(Int((canvasSize.height * scale).rounded()), 1)
        let bytesPerRow = pxW * 4
        var buffer = [UInt8](repeating: 0, count: pxH * bytesPerRow)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue

        let strips = WarawaraTurnGeometry.strips(
            count: stripCount,
            canvasSize: canvasSize,
            bodyBounds: bodyBounds,
            yawDegrees: yawDegrees,
            pitchDegrees: pitchDegrees
        )

        let drawnOK: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(
                    data: base,
                    width: pxW,
                    height: pxH,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                  ) else { return false }

            // CGBitmapContext: memory row 0 is the TOP scanline, while
            // the CG coordinate origin is bottom-left. Image draws use
            // the normal (unflipped) CTM so they render upright; strip
            // destinations are converted from top-left geometry to
            // bottom-left CG coordinates here.
            ctx.interpolationQuality = .high

            // Pixel-aligned strip edges: computed once from the same
            // cumulative geometry so adjacent strips share exact edges.
            var edgePoints: [CGFloat] = [strips[0].destination.minX]
            for strip in strips { edgePoints.append(strip.destination.maxX) }
            let pixelEdges = edgePoints.map { ($0 * scale).rounded() }
            let sourceScaleX = CGFloat(cg.width) / canvasSize.width
            let sourceScaleY = CGFloat(cg.height) / canvasSize.height
            var sourceEdges: [CGFloat] = [strips[0].source.minX]
            for strip in strips { sourceEdges.append(strip.source.maxX) }
            let sourcePixelEdges = sourceEdges.map { ($0 * sourceScaleX).rounded() }

            for index in 0..<strips.count {
                let strip = strips[index]
                let destX = pixelEdges[index]
                let destYTop = (strip.destination.minY * scale).rounded()
                let destWidth = pixelEdges[index + 1] - destX
                let destHeight = (strip.destination.height * scale).rounded()
                guard destWidth > 0, destHeight > 0 else { continue }
                let destYBottom = CGFloat(pxH) - destYTop - destHeight

                let srcX = sourcePixelEdges[index]
                let srcWidth = sourcePixelEdges[index + 1] - srcX
                let srcY = (strip.source.minY * sourceScaleY).rounded()
                let srcHeight = (strip.source.height * sourceScaleY).rounded()
                guard srcWidth > 0, srcHeight > 0 else { continue }

                let sourceRect = CGRect(x: srcX, y: srcY, width: srcWidth, height: srcHeight)
                guard let crop = cg.cropping(to: sourceRect) else { continue }
                ctx.draw(crop, in: CGRect(x: destX, y: destYBottom, width: destWidth, height: destHeight))
            }
            return true
        }
        guard drawnOK else { return nil }

        // In-buffer volume shading: darken only pixels that already have
        // alpha, strip by strip. Operates on the premultiplied buffer in
        // TOP-LEFT row order (byte row 0 = top scanline).
        if shadingEnabled {
            applyShading(
                to: &buffer,
                pxW: pxW,
                pxH: pxH,
                strips: strips,
                scale: scale,
                yawDegrees: yawDegrees
            )
        }

        let provider = CGDataProvider(data: Data(buffer) as CFData)
        guard let finalImage = CGImage(
            width: pxW,
            height: pxH,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider!,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else { return nil }
        return NSImage(cgImage: finalImage, size: canvasSize)
    }

    /// Multiplies the RGB of already-drawn (alpha > 0) pixels by
    /// (1 - stripShade) inside each strip's pixel rect. Transparent
    /// pixels are never touched, so the shading is EXACTLY confined to
    /// the body silhouette.
    private static func applyShading(
        to buffer: inout [UInt8],
        pxW: Int,
        pxH: Int,
        strips: [WarawaraTurnGeometry.Strip],
        scale: CGFloat,
        yawDegrees: CGFloat
    ) {
        for index in 0..<strips.count {
            let shade = WarawaraTurnGeometry.stripShade(
                at: index, count: strips.count, yawDegrees: yawDegrees
            )
            guard shade > 0.001 else { continue }
            let strip = strips[index]
            let x0 = max(Int((strip.destination.minX * scale).rounded()), 0)
            let x1 = min(Int((strip.destination.maxX * scale).rounded()), pxW)
            let y0 = max(Int((strip.destination.minY * scale).rounded()), 0)
            let y1 = min(Int((strip.destination.maxY * scale).rounded()), pxH)
            guard x1 > x0, y1 > y0 else { continue }
            let factor = Float(1 - shade)
            for y in y0..<y1 {
                var offset = (y * pxW + x0) * 4
                for _ in x0..<x1 {
                    let alpha = buffer[offset + 3]
                    if alpha > 0 {
                        buffer[offset] = UInt8(Float(buffer[offset]) * factor)
                        buffer[offset + 1] = UInt8(Float(buffer[offset + 1]) * factor)
                        buffer[offset + 2] = UInt8(Float(buffer[offset + 2]) * factor)
                    }
                    offset += 4
                }
            }
        }
    }

    private static func touch(_ key: String) {
        guard let index = cacheOrder.firstIndex(of: key) else { return }
        cacheOrder.remove(at: index)
        cacheOrder.append(key)
    }

    /// Test/diagnostic access.
    static var cachedCount: Int { cache.count }

    static func clearCache() {
        cache.removeAll()
        cacheOrder.removeAll()
    }
}
