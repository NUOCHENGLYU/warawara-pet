import AppKit
import Foundation

/// Phase 7 gift artwork store: wearables + meteor, with the approved
/// design-locked SHA256 manifest and pixel-integrity checks for the
/// front/rear layer splits.
final class GiftAssetStore {
    static let shared = GiftAssetStore()

    static let requiredFileNames: [String] = [
        "christmas_hat.png",
        "audio_headphones.png",
        "audio_headphones_front.png",
        "audio_headphones_rear.png",
        "cny_red_scarf.png",
        "cny_red_scarf_front.png",
        "cny_red_scarf_rear.png",
        "meteor_celfilm.png"
    ]

    /// Approved design-lock hashes (Warawara_Final_Gift_Art_v1).
    static let expectedSHA256: [String: String] = [
        "christmas_hat.png": "683ae401c120b36f734cd13af7dc4ffe86e5ee22ce4a8e32637c970fbb580cf1",
        "audio_headphones.png": "78c052aad11b9f2ee306a482da7216837220db116f77d73c3899c3d77f65ab33",
        "audio_headphones_front.png": "e36a61accf3459fb39b92454a5b074226504c350d05fd4b230669eafb51bf159",
        "audio_headphones_rear.png": "73afedd3cd0d89479c06ceb5d7b8ae0a6673bc998a0a1a4723e84ccbdaa37a77",
        "cny_red_scarf.png": "2fb0dae06582b1c399e6ab81f3f44ca124f82f78dbdb127cd667b4a987f9ecb9",
        "cny_red_scarf_front.png": "41bd4617c5ffc3dc92309e476f69a4d6607490e4352b248756d60384ea6c444b",
        "cny_red_scarf_rear.png": "4d9732ecbd71f5a60e2aedde8a484ee20ba9ca3468d8c324911dd9e6c9ca041e",
        "meteor_celfilm.png": "049f0e05b20be1198926be29d697dadadf0b443e41e216e90f0ea1c9abd55312"
    ]

    private var imageCache: [String: NSImage] = [:]
    private var resolvedBaseURL: URL?

    static func candidateBaseURLs() -> [URL] {
        var roots: [URL] = []
        #if SWIFT_PACKAGE
        if let url = Bundle.module.resourceURL { roots.append(url) }
        #endif
        if let url = Bundle.main.resourceURL { roots.append(url) }
        roots.append(
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")
        )
        roots.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/WarawaraPet/Resources")
        )
        return roots.map { $0.appendingPathComponent("Gift") }
    }

    func resolveBaseURL() -> URL? {
        if let resolvedBaseURL { return resolvedBaseURL }
        for candidate in Self.candidateBaseURLs()
        where FileManager.default.fileExists(atPath: candidate.path) {
            resolvedBaseURL = candidate
            return candidate
        }
        return nil
    }

    func image(named fileName: String) -> NSImage? {
        if let cached = imageCache[fileName] { return cached }
        guard let base = resolveBaseURL() else { return nil }
        let url = base.appendingPathComponent(fileName)
        guard let image = NSImage(contentsOf: url) else { return nil }
        imageCache[fileName] = image
        return image
    }

    func verifyAllRequiredAssets() -> (ok: Bool, details: String) {
        var missing: [String] = []
        for name in Self.requiredFileNames {
            if image(named: name) == nil { missing.append(name) }
        }
        if missing.isEmpty {
            return (true, "all \(Self.requiredFileNames.count) assets present")
        }
        return (false, "missing: \(missing)")
    }

    func verifySHA256() -> (ok: Bool, details: String) {
        var mismatches: [String] = []
        var missing: [String] = []
        for (name, expected) in Self.expectedSHA256 {
            guard let base = resolveBaseURL(),
                  let data = try? Data(contentsOf: base.appendingPathComponent(name)) else {
                missing.append(name)
                continue
            }
            if BirthdaySHA256.hash(data) != expected {
                mismatches.append(name)
            }
        }
        if mismatches.isEmpty && missing.isEmpty {
            return (true, "all \(Self.expectedSHA256.count) hashes match")
        }
        return (false, "mismatched: \(mismatches) missing: \(missing)")
    }

    /// The front+rear split layers must reconstruct their approved source
    /// painting pixel by pixel (no redesign, no independent transforms).
    func verifySplitIntegrity() -> (ok: Bool, details: String) {
        for (source, front, rear) in [
            ("audio_headphones.png", "audio_headphones_front.png", "audio_headphones_rear.png"),
            ("cny_red_scarf.png", "cny_red_scarf_front.png", "cny_red_scarf_rear.png")
        ] {
            guard let sourceImage = image(named: source),
                  let frontImage = image(named: front),
                  let rearImage = image(named: rear) else {
                return (false, "missing split layers for \(source)")
            }
            guard let sourceTiff = sourceImage.tiffRepresentation,
                  let sourceRep = NSBitmapImageRep(data: sourceTiff),
                  let frontTiff = frontImage.tiffRepresentation,
                  let frontRep = NSBitmapImageRep(data: frontTiff),
                  let rearTiff = rearImage.tiffRepresentation,
                  let rearRep = NSBitmapImageRep(data: rearTiff) else {
                return (false, "split layers not decodable for \(source)")
            }
            let width = sourceRep.pixelsWide
            let height = sourceRep.pixelsHigh
            guard width == 1024, height == 1024,
                  frontRep.pixelsWide == 1024, frontRep.pixelsHigh == 1024,
                  rearRep.pixelsWide == 1024, rearRep.pixelsHigh == 1024 else {
                return (false, "unexpected canvas size for \(source)")
            }
            var mismatched = 0
            for y in 0..<height {
                for x in 0..<width {
                    guard let sc = sourceRep.colorAt(x: x, y: y),
                          let fc = frontRep.colorAt(x: x, y: y),
                          let rc = rearRep.colorAt(x: x, y: y) else { continue }
                    let alphaTolerance: CGFloat = 6
                    let colorTolerance: CGFloat = 10
                    let combinedA = fc.alphaComponent + rc.alphaComponent
                    let sameA = abs(combinedA - sc.alphaComponent) <= alphaTolerance
                    let sameR = abs((fc.redComponent + rc.redComponent) - sc.redComponent) <= colorTolerance
                    let sameG = abs((fc.greenComponent + rc.greenComponent) - sc.greenComponent) <= colorTolerance
                    let sameB = abs((fc.blueComponent + rc.blueComponent) - sc.blueComponent) <= colorTolerance
                    if !(sameA && sameR && sameG && sameB) {
                        mismatched += 1
                    }
                    if mismatched > 500 { break }
                }
                if mismatched > 500 { break }
            }
            if mismatched > 0 {
                return (false, "\(source): \(mismatched)+ pixel mismatches between source and split sum")
            }
        }
        return (true, "headphone + scarf splits reconstruct their sources pixel-exactly")
    }

    func reset() {
        imageCache.removeAll()
        resolvedBaseURL = nil
    }
}
