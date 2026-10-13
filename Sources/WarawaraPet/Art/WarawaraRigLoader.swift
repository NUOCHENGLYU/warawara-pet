import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// Loads the layered rig (Assets/WarawaraRig/manifest.json + layer PNGs).
/// The rig is the primary rendering direction; when it is absent the app
/// logs that clearly and continues with the single-sprite pipeline.
final class WarawaraRigLoader {
    static let shared = WarawaraRigLoader()

    private(set) var rig: WarawaraRigManifest?
    /// Rig root whose manifest.json loaded (layer paths resolve here).
    private(set) var loadedBaseURL: URL?
    private(set) var lastErrorDescription: String?
    /// True once the default-rig lookup has been attempted (diagnostics).
    private(set) var didAttemptDefaultLoad = false
    private var imageCache: [String: NSImage] = [:]

    var hasRig: Bool { rig != nil }

    /// Rig root candidates derived from the sprite bundle candidates.
    /// SwiftPM flattens resource subdirectories into the bundle root, so
    /// the rig can land at <root>/Assets/WarawaraRig (source/dev layout)
    /// or directly at <root> (packaged app): both are probed.
    static func candidateBaseURLs(spriteCandidates: [URL]? = nil) -> [URL] {
        let roots = spriteCandidates ?? WarawaraSpriteLoader.candidateBaseURLs()
        var urls: [URL] = []
        for root in roots {
            urls.append(root.appendingPathComponent("Assets/WarawaraRig"))
            urls.append(root)
        }
        return urls
    }

    /// Loads the default rig once. Idempotent; failures are recorded with
    /// the attempted paths and logged — missing rig is an expected,
    /// explicitly reported condition, not an error.
    @discardableResult
    func loadDefaultRig(candidates: [URL]? = nil) -> Bool {
        didAttemptDefaultLoad = true
        if hasRig { return true }
        let urls = candidates ?? Self.candidateBaseURLs()
        var failures: [String] = []
        for url in urls {
            if loadManifest(from: url) {
                lastErrorDescription = nil
                NSLog("[WarawaraPet] layered rig loaded: %@", url.path)
                return true
            }
            failures.append("\(url.path): \(lastErrorDescription ?? "unknown error")")
        }
        lastErrorDescription = failures.joined(separator: "; ")
        NSLog(
            "[WarawaraPet] layered rig not available; using single-sprite pipeline — %@",
            lastErrorDescription ?? "unknown error"
        )
        return false
    }

    @discardableResult
    func loadManifest(from baseURL: URL) -> Bool {
        let manifestURL = baseURL.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            lastErrorDescription = "cannot read \(manifestURL.path)"
            rig = nil
            loadedBaseURL = nil
            return false
        }
        guard let decoded: WarawaraRigManifest = {
            do { return try JSONDecoder().decode(WarawaraRigManifest.self, from: data) }
            catch {
                lastErrorDescription = "decode error: \(error)"
                return nil
            }
        }() else {
            rig = nil
            loadedBaseURL = nil
            return false
        }
        guard let validated = WarawaraRigManifest.validated(decoded) else {
            lastErrorDescription = "invalid rig manifest at \(manifestURL.path)"
            rig = nil
            loadedBaseURL = nil
            return false
        }
        rig = validated
        loadedBaseURL = baseURL
        return true
    }

    /// Cached layer image. Manifest image paths may contain subdirectories;
    /// the flat basename is also tried because SwiftPM flattens resource
    /// subdirectories into the bundle root (filenames must stay unique).
    func image(forLayer layer: WarawaraRigManifest.Layer, role: String) -> NSImage? {
        guard let path = layer.images[role], let baseURL = loadedBaseURL else {
            lastErrorDescription = "rig layer image '\(role)' not declared"
            return nil
        }
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
            lastErrorDescription = "cannot decode rig image \(path) under \(baseURL.path)"
            return nil
        }
        imageCache[path] = image
        return image
    }

    func reset() {
        rig = nil
        loadedBaseURL = nil
        lastErrorDescription = nil
        didAttemptDefaultLoad = false
        imageCache.removeAll()
    }
}
