import AppKit
import Foundation

/// Loads and caches the sprite manifest and PNG frames. All decoding
/// happens once per image; animation frames reuse the cached instances.
/// Any missing or invalid asset produces `nil` and the caller falls back
/// to the procedural placeholder — never a crash.
final class WarawaraSpriteLoader {
    static let shared = WarawaraSpriteLoader()

    private(set) var manifest: WarawaraSpriteManifest?
    private var imageCache: [String: NSImage] = [:]

    /// Loads sprites.json from the given base URL (the bundle resource
    /// root). Returns true when a valid manifest was loaded.
    @discardableResult
    func loadManifest(from baseURL: URL) -> Bool {
        let manifestURL = baseURL.appendingPathComponent("sprites.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode(WarawaraSpriteManifest.self, from: data),
              let validated = WarawaraSpriteManifest.validated(decoded) else {
            manifest = nil
            return false
        }
        manifest = validated
        return true
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

    func animation(named key: String) -> WarawaraSpriteManifest.Animation? {
        manifest?.animations[key]
    }

    /// Cached image for a manifest frame path.
    func image(forRelativePath path: String, baseURL: URL) -> NSImage? {
        if let cached = imageCache[path] { return cached }
        let url = baseURL.appendingPathComponent(path)
        guard let image = NSImage(contentsOf: url) else { return nil }
        imageCache[path] = image
        return image
    }

    /// Clears the manifest and image cache (test support + diagnostics).
    func reset() {
        manifest = nil
        imageCache.removeAll()
    }
}
