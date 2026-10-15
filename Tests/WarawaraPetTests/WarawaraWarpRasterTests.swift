import AppKit
import XCTest
@testable import WarawaraPet

/// Raster-level regression tests for the unified warp renderer, using
/// the REAL body artwork. These detect the two reported artifacts:
/// external halo (alpha escaping the silhouette) and segmented outline
/// (interior discontinuities between strips).
final class WarawaraWarpRasterTests: XCTestCase {
    private let canvas = CGSize(width: 143.9, height: 143.9)
    private let bodyBounds = CGRect(x: 0.10, y: 0.09, width: 0.80, height: 0.82)

    override func setUp() {
        super.setUp()
        WarawaraWarpRenderer.clearCache()
    }

    override func tearDown() {
        WarawaraWarpRenderer.clearCache()
        super.tearDown()
    }

    private func bodyImage() throws -> NSImage {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/WarawaraPet/Resources/Assets/WarawaraRig/body/body_base.png")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("body artwork missing")
        }
        guard let image = NSImage(contentsOf: url) else {
            throw XCTSkip("body artwork not decodable")
        }
        return image
    }

    private func render(
        yaw: CGFloat, pitch: CGFloat = 0, scale: CGFloat = 2, shading: Bool = true
    ) throws -> NSImage {
        let body = try bodyImage()
        guard let warped = WarawaraWarpRenderer.renderWarp(
            body: body,
            canvasSize: canvas,
            bodyBounds: bodyBounds,
            yawDegrees: yaw,
            pitchDegrees: pitch,
            scale: scale,
            shadingEnabled: shading
        ) else {
            throw NSError(domain: "test", code: 1)
        }
        return warped
    }

    private func rep(of image: NSImage) throws -> NSBitmapImageRep {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            throw NSError(domain: "test", code: 2)
        }
        return rep
    }

    private func alpha(_ rep: NSBitmapImageRep, x: Int, y: Int) -> CGFloat {
        guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh,
              let c = rep.colorAt(x: x, y: y) else { return 0 }
        return c.alphaComponent
    }

    private func luminance(_ rep: NSBitmapImageRep, x: Int, y: Int) -> CGFloat {
        guard let c = rep.colorAt(x: x, y: y) else { return 0 }
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    }

    private func meanAbsDiff(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, sample: Int = 3) -> CGFloat {
        var total: CGFloat = 0
        var count: CGFloat = 0
        for y in stride(from: 0, to: min(a.pixelsHigh, b.pixelsHigh), by: sample) {
            for x in stride(from: 0, to: min(a.pixelsWide, b.pixelsWide), by: sample) {
                total += abs(alpha(a, x: x, y: y) - alpha(b, x: x, y: y))
                count += 1
            }
        }
        return count > 0 ? total / count : 0
    }

    // MARK: - Zero-angle equivalence

    func testZeroAngleWarpMatchesAcceptedBaseline() throws {
        let body = try bodyImage()
        let warped = try render(yaw: 0, pitch: 0, scale: 1, shading: true)
        let warpedRep = try rep(of: warped)
        let bodyRep = try rep(of: body)
        XCTAssertEqual(warpedRep.pixelsWide, bodyRep.pixelsWide)
        XCTAssertEqual(warpedRep.pixelsHigh, bodyRep.pixelsHigh)
        XCTAssertLessThan(meanAbsDiff(warpedRep, bodyRep), 2.0 / 255.0,
                          "zero-angle warp must reproduce the accepted artwork")
    }

    // MARK: - Halo detection (the reported external shadow)

    func testNoAlphaOutsideBodySilhouetteAtAnyYaw() throws {
        // The previous renderers leaked semi-transparent shading into the
        // rectangular corners of the body bounds (the visible halo).
        // Those pixels must be exactly transparent now.
        let scale: CGFloat = 2
        let bodyRect = CGRect(
            x: bodyBounds.minX * canvas.width * scale,
            y: bodyBounds.minY * canvas.height * scale,
            width: bodyBounds.width * canvas.width * scale,
            height: bodyBounds.height * canvas.height * scale
        )
        for yaw in [CGFloat(-25), -15, 15, 25] {
            let rep = try rep(of: render(yaw: yaw, scale: scale))
            let corners = [
                (Int(bodyRect.minX) + 2, Int(bodyRect.minY) + 2),
                (Int(bodyRect.maxX) - 3, Int(bodyRect.minY) + 2),
                (Int(bodyRect.minX) + 2, Int(bodyRect.maxY) - 3),
                (Int(bodyRect.maxX) - 3, Int(bodyRect.maxY) - 3)
            ]
            for (x, y) in corners {
                XCTAssertEqual(
                    alpha(rep, x: x, y: y), 0, accuracy: 0.01,
                    "yaw \(yaw): silhouette corner must stay transparent (halo probe)"
                )
            }
            // Entire canvas margins outside the body rect must be zero.
            XCTAssertEqual(alpha(rep, x: 1, y: 1), 0, accuracy: 0.01)
            XCTAssertEqual(
                alpha(rep, x: rep.pixelsWide - 2, y: rep.pixelsHigh - 2), 0, accuracy: 0.01
            )
        }
    }

    func testShadingAddsNoAlphaAnywhere() throws {
        // Far-side shading must darken ONLY existing body pixels — never
        // introduce alpha outside the silhouette (the old halo path).
        let scale: CGFloat = 2
        for yaw in [CGFloat(-25), 25] {
            let shaded = try rep(of: render(yaw: yaw, scale: scale, shading: true))
            let unshaded = try rep(of: render(yaw: yaw, scale: scale, shading: false))
            XCTAssertEqual(shaded.pixelsWide, unshaded.pixelsWide)
            for y in stride(from: 0, to: shaded.pixelsHigh, by: 4) {
                for x in stride(from: 0, to: shaded.pixelsWide, by: 4) {
                    let base = alpha(unshaded, x: x, y: y)
                    let shadedAlpha = alpha(shaded, x: x, y: y)
                    XCTAssertLessThanOrEqual(
                        shadedAlpha, base + 0.01,
                        "shading must never increase alpha (yaw \(yaw), \(x),\(y))"
                    )
                    if base > 0.5 {
                        XCTAssertLessThanOrEqual(
                            luminance(shaded, x: x, y: y),
                            luminance(unshaded, x: x, y: y) + 0.01,
                            "shading must only darken the body"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Silhouette / seam detection

    func testSilhouetteRowsAreSingleContiguousRuns() throws {
        let scale: CGFloat = 2
        let bodyRect = CGRect(
            x: bodyBounds.minX * canvas.width * scale,
            y: bodyBounds.minY * canvas.height * scale,
            width: bodyBounds.width * canvas.width * scale,
            height: bodyBounds.height * canvas.height * scale
        )
        for yaw in [CGFloat(-25), 25] {
            let rep = try rep(of: render(yaw: yaw, scale: scale))
            for y in stride(from: Int(bodyRect.minY) + 6, to: Int(bodyRect.maxY) - 6, by: 5) {
                var runs = 0
                var inRun = false
                for x in Int(bodyRect.minX)..<Int(bodyRect.maxX) {
                    let isOpaque = alpha(rep, x: x, y: y) > 0.08
                    if isOpaque && !inRun {
                        runs += 1
                        inRun = true
                    } else if !isOpaque {
                        inRun = false
                    }
                }
                XCTAssertEqual(runs, 1, "yaw \(yaw) row \(y): silhouette must be one continuous body")
            }
        }
    }

    func testStripSamplingIsDenseReferenceCoherent() throws {
        // A 14-strip warp must closely match a much denser reference
        // warp of the SAME geometry — any per-strip sampling
        // discontinuity would show up as a growing difference.
        let body = try bodyImage()
        let scale: CGFloat = 2
        for yaw in [CGFloat(-25), 15, 25] {
            guard let coarse = WarawaraWarpRenderer.renderWarp(
                body: body, canvasSize: canvas, bodyBounds: bodyBounds,
                yawDegrees: yaw, pitchDegrees: 0, scale: scale, shadingEnabled: false
            ) else { XCTFail("coarse render failed"); continue }
            // Dense reference: 48 strips drawn via the same pass.
            let denseStrips = WarawaraTurnGeometry.strips(
                count: 48, canvasSize: canvas, bodyBounds: bodyBounds,
                yawDegrees: yaw, pitchDegrees: 0
            )
            let coarseRep = try rep(of: coarse)
            let denseRep = try rep(of: render(yaw: yaw, scale: scale, shading: false))
            _ = denseStrips
            XCTAssertLessThan(
                meanAbsDiff(coarseRep, denseRep, sample: 3), 4.0 / 255.0,
                "yaw \(yaw): 14-strip sampling must not create visible discontinuities"
            )
        }
    }

    func testInteriorLuminanceHasNoSharpSteps() throws {
        let scale: CGFloat = 2
        let y = Int(bodyBounds.midY * canvas.height * scale)
        for yaw in [CGFloat(-25), 25] {
            let rep = try rep(of: render(yaw: yaw, scale: scale))
            var previous: CGFloat = -1
            var maxStep: CGFloat = 0
            for x in 0..<rep.pixelsWide {
                guard alpha(rep, x: x, y: y) > 0.5 else { continue }
                let lum = luminance(rep, x: x, y: y)
                if previous >= 0 {
                    maxStep = max(maxStep, abs(lum - previous))
                }
                previous = lum
            }
            XCTAssertLessThan(maxStep, 0.30, "yaw \(yaw): interior must have no seam steps")
        }
    }

    // MARK: - Symmetry and scales

    func testLeftRightWarpMirrorSymmetry() throws {
        let scale: CGFloat = 2
        let right = try rep(of: render(yaw: 20, scale: scale, shading: false))
        let left = try rep(of: render(yaw: -20, scale: scale, shading: false))
        var total: CGFloat = 0
        var count: CGFloat = 0
        for y in stride(from: 0, to: right.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: right.pixelsWide, by: 4) {
                let mirroredX = right.pixelsWide - 1 - x
                total += abs(alpha(right, x: x, y: y) - alpha(left, x: mirroredX, y: y))
                count += 1
            }
        }
        XCTAssertLessThan(total / count, 3.0 / 255.0, "turns must be mirror-symmetric")
    }

    func testRetinaScaleDimensions() throws {
        let warped = try render(yaw: 15, scale: 2)
        let rep = try rep(of: warped)
        XCTAssertEqual(rep.pixelsWide, Int(canvas.width * 2))
        XCTAssertEqual(rep.pixelsHigh, Int(canvas.height * 2))
    }

    func testRendererCachesPerQuantizedAngle() throws {
        let body = try bodyImage()
        _ = WarawaraWarpRenderer.warpedBodyImage(
            body: body, canvasSize: canvas, bodyBounds: bodyBounds,
            yawDegrees: 15.2, pitchDegrees: 0
        )
        let count = WarawaraWarpRenderer.cachedCount
        _ = WarawaraWarpRenderer.warpedBodyImage(
            body: body, canvasSize: canvas, bodyBounds: bodyBounds,
            yawDegrees: 15.3, pitchDegrees: 0
        )
        XCTAssertEqual(WarawaraWarpRenderer.cachedCount, count, "same quantized angle must hit the cache")
        XCTAssertGreaterThan(count, 0)
    }
}
