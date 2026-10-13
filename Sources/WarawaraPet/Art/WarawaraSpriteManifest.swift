import Foundation

/// JSON manifest describing the sprite asset set. Hand-corrected assets
/// can be added later without source changes: drop PNGs + edit sprites.json.
struct WarawaraSpriteManifest: Codable, Equatable {
    struct Layout: Codable, Equatable {
        /// Logical canvas size (points) shared by all frames.
        var canvas: CGSize
        /// Character anchor inside the canvas, normalized 0...1,
        /// top-left origin. This point maps onto the window's center.
        var anchor: CGPoint
        /// Rendered body bounds inside the canvas, normalized 0...1.
        /// Used for deformation envelopes and clipping checks.
        var bodyBounds: CGRect
    }

    struct Animation: Codable, Equatable {
        /// Frame file paths relative to the bundle root.
        var frames: [String]
        var frameDuration: TimeInterval
        var loop: Bool
    }

    var version: Int
    var layout: Layout
    var animations: [String: Animation]

    static let currentVersion = 1

    /// Returns the manifest when structurally valid, nil otherwise.
    /// Validation is strict: unknown/oversized geometry falls back to the
    /// placeholder rather than rendering garbage.
    static func validated(_ manifest: WarawaraSpriteManifest) -> WarawaraSpriteManifest? {
        guard manifest.version == currentVersion else { return nil }
        guard manifest.layout.canvas.width > 0, manifest.layout.canvas.height > 0 else { return nil }
        guard isValidNormalizedPoint(manifest.layout.anchor) else { return nil }
        guard isValidNormalizedRect(manifest.layout.bodyBounds) else { return nil }
        guard !manifest.animations.isEmpty else { return nil }
        for (_, animation) in manifest.animations {
            guard !animation.frames.isEmpty else { return nil }
            guard animation.frameDuration > 0 else { return nil }
        }
        return manifest
    }

    private static func isValidNormalizedPoint(_ point: CGPoint) -> Bool {
        point.x >= 0 && point.x <= 1 && point.y >= 0 && point.y <= 1
    }

    private static func isValidNormalizedRect(_ rect: CGRect) -> Bool {
        rect.minX >= 0 && rect.minY >= 0 && rect.maxX <= 1 && rect.maxY <= 1
            && rect.width > 0 && rect.height > 0
    }
}
