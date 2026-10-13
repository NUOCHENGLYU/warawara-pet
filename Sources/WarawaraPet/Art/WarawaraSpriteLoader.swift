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

    /// Loads sprites.json from the given base URL (the bundle resource
    /// root). Returns true when a valid manifest was loaded.
    @discardableResult
    func loadManifest(from baseURL: URL) -> Bool {
        let manifestURL = baseURL.appendingPathComponent("sprites.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            lastErrorDescription = "cannot read \(manifestURL.path)"
            manifest = nil
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
            return false
        }
        guard let validated = WarawaraSpriteManifest.validated(decoded) else {
            lastErrorDescription = "invalid manifest at \(manifestURL.path)"
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

    /// Cached image for a manifest frame path. Decodes via NSImage first,
    /// then falls back to ImageIO (CGImageSource) for PNG variants that
    /// NSImage rejects.
    func image(forRelativePath path: String, baseURL: URL) -> NSImage? {
        if let cached = imageCache[path] { return cached }
        let url = baseURL.appendingPathComponent(path)
        var image = NSImage(contentsOf: url)
        if image == nil, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        if image == nil {
            var detail = "cannot decode \(path)"
            if !FileManager.default.fileExists(atPath: url.path) {
                detail += "; file missing at \(url.path)"
            } else if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
                detail += "; ImageIO opened source, props: \(String(describing: props))"
            } else {
                detail += "; ImageIO cannot open source at \(url.path)"
            }
            lastErrorDescription = detail
            return nil
        }
        imageCache[path] = image
        return image
    }

    /// Clears the manifest and image cache (test support + diagnostics).
    func reset() {
        manifest = nil
        imageCache.removeAll()
        lastErrorDescription = nil
    }
}
