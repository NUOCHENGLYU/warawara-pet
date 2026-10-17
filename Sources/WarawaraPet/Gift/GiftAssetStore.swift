import AppKit
import Foundation

/// Phase 7 final-gift artwork store: the meteor asset (the birthday
/// assets live in BirthdayAssetStore). Design-locked SHA256 manifest.
final class GiftAssetStore {
    static let shared = GiftAssetStore()

    /// Production meteor assets: the approved-origin head + sparkle
    /// (from the dynamic-trail handoff). The old full-canvas meteor with
    /// its baked tail is kept as a verified REFERENCE ONLY — never drawn.
    static let requiredFileNames: [String] = [
        "meteor_head_from_approved.png",
        "meteor_sparkle_from_approved.png",
        "meteor_celfilm.png"
    ]

    static let expectedSHA256: [String: String] = [
        "meteor_head_from_approved.png": "9c4560fd2afb0d71c4f6102fe021c4fcd772574f5ab392edbed7809021703f57",
        "meteor_sparkle_from_approved.png": "7ee30c62c88974bad019fc99ac931b357754eecdcc822948329180ee21342805",
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

    func reset() {
        imageCache.removeAll()
        resolvedBaseURL = nil
    }
}
