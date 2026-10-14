import AppKit
import XCTest
@testable import WarawaraPet

/// Static art invariants for the packaged rig (Phase 5D evidence):
/// the body must carry no baked facial features, and the eye variants
/// must be registered within a tight tolerance so normalized crossfades
/// cannot produce double eyes.
final class WarawaraRigArtInvariantsTests: XCTestCase {
    private var rigRoot: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/WarawaraPet/Resources/Assets/WarawaraRig")
    }

    private func bitmap(named path: String) throws -> NSBitmapImageRep? {
        let url = rigRoot.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("rig asset missing: \(path)")
        }
        guard let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep
    }

    /// Scans a canvas-space region (top-left origin) and returns the
    /// minimum luminance of opaque pixels. NSBitmapImageRep rows are
    /// top-to-bottom, so canvas Y maps 1:1.
    private func minLuminance(
        in canvasRegion: CGRect, of rep: NSBitmapImageRep
    ) -> Double {
        var minLum = Double.greatestFiniteMagnitude
        for canvasY in Int(canvasRegion.minY)..<Int(canvasRegion.maxY) {
            guard canvasY >= 0, canvasY < rep.pixelsHigh else { continue }
            for canvasX in Int(canvasRegion.minX)..<Int(canvasRegion.maxX) {
                guard let color = rep.colorAt(x: canvasX, y: canvasY),
                      color.alphaComponent > 0.5 else { continue }
                let lum = 0.2126 * Double(color.redComponent)
                    + 0.7152 * Double(color.greenComponent)
                    + 0.0722 * Double(color.blueComponent)
                minLum = min(minLum, lum * 255)
            }
        }
        return minLum
    }

    /// Dark-pixel centroids in the eye band, split at canvas x == 512
    /// (left eye / right eye), in canvas coordinates.
    private func eyeCentroids(of rep: NSBitmapImageRep) -> [(Double, Double)] {
        var leftSumX = 0.0, leftSumY = 0.0, leftCount = 0.0
        var rightSumX = 0.0, rightSumY = 0.0, rightCount = 0.0
        for canvasY in 380..<520 {
            guard canvasY >= 0, canvasY < rep.pixelsHigh else { continue }
            for canvasX in 250..<800 {
                guard let color = rep.colorAt(x: canvasX, y: canvasY),
                      color.alphaComponent > 0.5 else { continue }
                let lum = 0.2126 * Double(color.redComponent)
                    + 0.7152 * Double(color.greenComponent)
                    + 0.0722 * Double(color.blueComponent)
                guard lum * 255 < 90 else { continue }
                if canvasX < 512 {
                    leftSumX += Double(canvasX); leftSumY += Double(canvasY); leftCount += 1
                } else {
                    rightSumX += Double(canvasX); rightSumY += Double(canvasY); rightCount += 1
                }
            }
        }
        guard leftCount > 0, rightCount > 0 else { return [] }
        return [
            (leftSumX / leftCount, leftSumY / leftCount),
            (rightSumX / rightCount, rightSumY / rightCount)
        ]
    }

    func testBodyCarriesNoBakedFacialPixels() throws {
        guard let rep = try bitmap(named: "body/body_base.png") else {
            XCTFail("body_base.png not decodable")
            return
        }
        let eyeBand = CGRect(x: 320, y: 400, width: 380, height: 90)
        let mouthBand = CGRect(x: 460, y: 480, width: 100, height: 90)
        let eyeMin = minLuminance(in: eyeBand, of: rep)
        let mouthMin = minLuminance(in: mouthBand, of: rep)
        // Measured clean value is 232; lock a generous margin.
        XCTAssertGreaterThanOrEqual(eyeMin, 200, "body must have no dark eye pixels")
        XCTAssertGreaterThanOrEqual(mouthMin, 200, "body must have no dark mouth pixels")
    }

    func testEyeVariantsAreRegisteredWithinTolerance() throws {
        let variants = ["eyes/eyes_open", "eyes/eyes_half", "eyes/eyes_closed",
                        "eyes/eyes_focused", "eyes/eyes_pressed"]
        var centroids: [String: [(Double, Double)]] = [:]
        for name in variants {
            guard let rep = try bitmap(named: "\(name).png") else { continue }
            let centers = eyeCentroids(of: rep)
            XCTAssertEqual(centers.count, 2, "\(name) must have exactly two eye clusters")
            centroids[name] = centers
        }
        guard let reference = centroids["eyes/eyes_open"] else {
            throw XCTSkip("eyes_open missing")
        }
        for (name, centers) in centroids where name != "eyes_open" {
            for index in 0..<min(centers.count, reference.count) {
                let dx = abs(centers[index].0 - reference[index].0)
                let dy = abs(centers[index].1 - reference[index].1)
                XCTAssertLessThanOrEqual(dx, 6, "\(name) eye \(index) drifts horizontally from open")
                XCTAssertLessThanOrEqual(dy, 6, "\(name) eye \(index) drifts vertically from open")
            }
        }
    }
}
