import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// Loads and caches the sprite manifest and PNG frames. All decoding
/// happens once per image; animation frames reuse the cached instances.
/// Any missing or invalid asset produces `nil` and the caller falls back
/// to the procedural placeholder — never a crash.
final class WarawaraSpriteLoader {
    static let shared = WarawaraSpriteLoader()

    private(set) var manifest: WarawaraSpriteManifest?
    private var imageCache: [String: NSImage] = [:]
    /// Human-readable last failure (diagnostics only).
    private(set) var lastErrorDescription: String?
    /// Base URLs tried by the last `loadDefaultResources()` call.
    private(set) var attemptedBaseURLs: [URL] = []
    /// The base URL whose sprites.json actually loaded. Frame paths are
    /// resolved relative to THIS root, not to a re-derived default.
    private(set) var loadedBaseURL: URL?

    /// Loads sprites.json from the given base URL (the bundle resource
    /// root). Returns true when a valid manifest was loaded.
    @discardableResult
    func loadManifest(from baseURL: URL) -> Bool {
        let manifestURL = baseURL.appendingPathComponent("sprites.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            lastErrorDescription = "cannot read \(manifestURL.path)"
            manifest = nil
            loadedBaseURL = nil
            return false
        }
        guard let decoded: WarawaraSpriteManifest = {
            do { return try JSONDecoder().decode(WarawaraSpriteManifest.self, from: data) }
            catch {
                lastErrorDescription = "decode error: \(error)"
                return nil
            }
        }() else {
            manifest = nil
            loadedBaseURL = nil
            return false
        }
        guard let validated = WarawaraSpriteManifest.validated(decoded) else {
            lastErrorDescription = "invalid manifest at \(manifestURL.path)"
            manifest = nil
            loadedBaseURL = nil
            return false
        }
        manifest = validated
        loadedBaseURL = baseURL
        return true
    }

    /// Candidate base URLs in the order the app probes them. Covers both
    /// `swift run`/`swift test` (SPM build directory bundle) and the
    /// packaged `.app` (Contents/Resources/WarawaraPet_WarawaraPet.bundle),
    /// so the same startup call works in development and release.
    static func candidateBaseURLs() -> [URL] {
        var urls: [URL] = []
        let add: (URL?) -> Void = { candidate in
            guard let candidate else { return }
            let standardized = candidate.standardizedFileURL
            guard !urls.contains(standardized) else { return }
            urls.append(standardized)
        }
        #if SWIFT_PACKAGE
        add(Bundle.module.resourceURL)
        #endif
        add(Bundle.main.resourceURL)
        add(Bundle.main.resourceURL?.appendingPathComponent("WarawaraPet_WarawaraPet.bundle"))
        add(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/WarawaraPet_WarawaraPet.bundle"))
        return urls
    }

    /// The default bundle resource root: the SPM resource bundle when
    /// available, otherwise the main bundle's Resources (packaged app).
    static var defaultResourceURL: URL? {
        #if SWIFT_PACKAGE
        return Bundle.module.resourceURL
        #else
        return Bundle.main.resourceURL
        #endif
    }

    var hasSprites: Bool { manifest != nil }

    /// Loads the default sprite resources once. The app calls this from
    /// startup BEFORE the first pet render; it is idempotent and safe to
    /// call again. On failure the attempted paths and reason are recorded
    /// and logged — the UI must never fall back to the placeholder
    /// silently.
    @discardableResult
    func loadDefaultResources(candidateBaseURLs candidates: [URL]? = nil) -> Bool {
        if hasSprites { return true }
        let urls = candidates ?? Self.candidateBaseURLs()
        attemptedBaseURLs = urls
        var failures: [String] = []
        for url in urls {
            if loadManifest(from: url) {
                lastErrorDescription = nil
                return true
            }
            failures.append("\(url.path): \(lastErrorDescription ?? "unknown error")")
        }
        let summary = failures.joined(separator: "; ")
        lastErrorDescription = summary
        NSLog("[WarawaraPet] sprite resources failed to load — %@", summary)
        return false
    }

    func animation(named key: String) -> WarawaraSpriteManifest.Animation? {
        manifest?.animations[key]
    }

    /// Cached image for a manifest frame path. Decodes via NSImage first,
    /// then falls back to ImageIO (CGImageSource) for PNG variants that
    /// NSImage rejects. The manifest path may contain subdirectories; the
    /// flat basename is also tried because SwiftPM flattens resource
    /// subdirectories into the bundle root.
    func image(forRelativePath path: String, baseURL: URL) -> NSImage? {
        if let cached = imageCache[path] { return cached }
        let candidates = [
            baseURL.appendingPathComponent(path),
            baseURL.appendingPathComponent((path as NSString).lastPathComponent)
        ]
        var image: NSImage?
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            image = NSImage(contentsOf: url)
            if image == nil, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
            if image != nil { break }
        }
        if image == nil {
            var detail = "cannot decode \(path)"
            let exists = candidates.contains { FileManager.default.fileExists(atPath: $0.path) }
            if !exists {
                detail += "; no file at \(candidates.map(\.path).joined(separator: " or "))"
            } else {
                detail += "; decoders failed"
            }
            lastErrorDescription = detail
            return nil
        }
        lastErrorDescription = nil
        imageCache[path] = image
        return image
    }

    /// Clears the manifest and image cache (test support + diagnostics).
    func reset() {
        manifest = nil
        imageCache.removeAll()
        lastErrorDescription = nil
        attemptedBaseURLs = []
        loadedBaseURL = nil
    }
}
