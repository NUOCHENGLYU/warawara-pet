import AppKit
import Foundation

/// Phase 8C bottle-mail artwork store — the OFFICIAL v3 pack
/// (`Warawara_BottleMail_Phase8C_Ghibli_Minimal_v3/assets-1024/`).
/// Final illustration assets (not layered rigs): the morph itself is
/// procedural (scale + mask + expression blend over these states).
///
/// Loading failures degrade gracefully to the procedural placeholder
/// bottle — the pet never disappears because art is missing.
final class BottleMailArtStore {
    static let shared = BottleMailArtStore()

    /// The five shipped v3 assets.
    static let requiredFileNames: [String] = [
        "bottle_idle.png",
        "bottle_unread.png",
        "bottle_opening.png",
        "scroll_sealed.png",
        "letter_paper_blank.png"
    ]

    /// The poof-transition companion pack (smoke layers + one-shot
    /// audio). Missing poof assets degrade to the geometric-reveal
    /// fallback — the swap stays hidden either way.
    static let poofFileNames: [String] = [
        "smoke_core.png",
        "smoke_soft.png",
        "smoke_small.png",
        "smoke_wisps.png",
        "landing_dust.png",
        "soft_poof.wav"
    ]

    private var imageCache: [String: NSImage] = [:]
    private var contentBoundsCache: [String: CGRect] = [:]
    private var resolvedBaseURL: URL?
    /// Test/diagnostic seam: forces the store to a specific directory
    /// (e.g. an empty temp dir to exercise the fallback path).
    var baseURLOverride: URL?
    /// Last load failure (file names) for diagnostics / tests.
    private(set) var missingFileNames: [String] = []

    /// Same resolution order as the other art stores: SwiftPM bundle ->
    /// main bundle -> app Resources -> source tree (development/CI).
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
        return roots.map { $0.appendingPathComponent("BottleMail") }
    }

    func resolveBaseURL() -> URL? {
        if let resolvedBaseURL { return resolvedBaseURL }
        if let baseURLOverride, FileManager.default.fileExists(atPath: baseURLOverride.path) {
            resolvedBaseURL = baseURLOverride
            return resolvedBaseURL
        }
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
        guard let image = NSImage(contentsOf: url) else {
            return nil
        }
        imageCache[fileName] = image
        return image
    }

    /// Convenience accessors for the known assets.
    var bottleIdle: NSImage? { image(named: "bottle_idle.png") }
    var bottleUnread: NSImage? { image(named: "bottle_unread.png") }
    var bottleOpening: NSImage? { image(named: "bottle_opening.png") }
    var scrollSealed: NSImage? { image(named: "scroll_sealed.png") }
    var letterPaper: NSImage? { image(named: "letter_paper_blank.png") }
    var smokeCore: NSImage? { image(named: "smoke_core.png") }
    var smokeSoft: NSImage? { image(named: "smoke_soft.png") }
    var smokeSmall: NSImage? { image(named: "smoke_small.png") }
    var smokeWisps: NSImage? { image(named: "smoke_wisps.png") }
    var landingDust: NSImage? { image(named: "landing_dust.png") }

    /// The one-shot poof sound URL (nil when missing).
    func audioURL(named fileName: String) -> URL? {
        guard let base = resolveBaseURL() else { return nil }
        let url = base.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// True when all three bottle state images are usable (the art path).
    var hasBottleArt: Bool {
        bottleIdle != nil && bottleUnread != nil && bottleOpening != nil
    }

    /// True when the full poof pack is usable (occlusion smoke layers
    /// + landing dust + the one-shot audio).
    var hasPoofAssets: Bool {
        smokeCore != nil && smokeSoft != nil && smokeSmall != nil
            && smokeWisps != nil && landingDust != nil
            && audioURL(named: "soft_poof.wav") != nil
    }

    /// Normalized opaque-content bounds (0...1 in canvas space, y down
    /// from the top) for layout — measured from the alpha channel.
    func contentBounds(named fileName: String) -> CGRect? {
        if let cached = contentBoundsCache[fileName] { return cached }
        guard let image = image(named: fileName),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let width = cg.width
        let height = cg.height
        guard width > 0, height > 0,
              let provider = cg.dataProvider,
              let data = provider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return nil
        }
        let bytesPerRow = cg.bytesPerRow
        let bytesPerPixel = max(cg.bitsPerPixel / 8, 1)
        let alphaInfo = cg.alphaInfo
        let alphaLast = alphaInfo == .premultipliedLast || alphaInfo == .last
        let alphaOffset = alphaLast ? bytesPerPixel - 1 : 0
        let hasAlpha = alphaInfo != .none && alphaInfo != .noneSkipFirst && alphaInfo != .noneSkipLast

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let index = y * bytesPerRow + x * bytesPerPixel
                let alpha = hasAlpha ? Int(bytes[index + alphaOffset]) : 255
                if alpha > 24 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let bounds = CGRect(
            x: CGFloat(minX) / CGFloat(width),
            y: CGFloat(minY) / CGFloat(height),
            width: CGFloat(maxX - minX) / CGFloat(width),
            height: CGFloat(maxY - minY) / CGFloat(height)
        )
        contentBoundsCache[fileName] = bounds
        return bounds
    }

    func verifyAllRequiredAssets() -> (ok: Bool, details: String) {
        var missing: [String] = []
        for name in Self.requiredFileNames where image(named: name) == nil {
            missing.append(name)
        }
        for name in Self.poofFileNames {
            if name.hasSuffix(".wav") {
                if audioURL(named: name) == nil { missing.append(name) }
            } else if image(named: name) == nil {
                missing.append(name)
            }
        }
        missingFileNames = missing
        if missing.isEmpty {
            return (true, "all \(Self.requiredFileNames.count + Self.poofFileNames.count) assets present")
        }
        EventDiagnostics.bottleMail("ART_MISSING", details: "files=\(missing.joined(separator: ","))")
        return (false, "missing: \(missing)")
    }

    /// Diagnose line for the packaged-app check (never prints paths).
    func diagnostics() -> String {
        let state = verifyAllRequiredAssets()
        let boundsState = contentBounds(named: "bottle_unread.png") == nil ? "none" : "ok"
        return "BOTTLE_ART ok=\(state.ok) details=\(state.details) bounds=\(boundsState)"
    }

    func reset() {
        imageCache.removeAll()
        contentBoundsCache.removeAll()
        resolvedBaseURL = nil
        missingFileNames = []
        // The override survives reset() on purpose (a test harness sets
        // it once); clear it explicitly when needed.
    }

    /// Resets everything INCLUDING the override.
    func resetFully() {
        reset()
        baseURLOverride = nil
    }
}
