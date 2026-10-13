import Foundation

/// Layered character rig manifest (Assets/WarawaraRig/manifest.json).
/// The rig replaces the single-sprite pipeline when present; every layer
/// shares one canvas coordinate system so the renderer can compose them
/// around a common anchor/bodyBounds geometry.
struct WarawaraRigManifest: Codable, Equatable {
    enum LayerKind: String, Codable, Equatable, CaseIterable {
        case body
        case eyes
        case mouth
        case limbs
    }

    struct Layer: Codable, Equatable {
        /// Kind of the layer. The dictionary key must equal this value.
        var kind: LayerKind
        /// Image roles for the layer: e.g. body -> ["base"], eyes ->
        /// ["open", "closed"], mouth -> one entry per WarawaraMouthStyle.
        var images: [String: String]
        /// Layer pivot in canvas units, normalized 0...1 (top-left origin).
        var anchor: CGPoint
        /// Eyes only: maximum gaze offset in canvas width/height fractions.
        /// Absent = no gaze offset for the layer.
        var gazeRange: CGSize?
        /// Optional transform pivot (e.g. mouth scaling center) in
        /// normalized canvas units. Falls back to `anchor` when absent.
        var pivot: CGPoint? = nil
    }

    var version: Int
    var canvas: CGSize
    /// Canvas anchor mapped onto the character slot center (as in the
    /// sprite manifest).
    var anchor: CGPoint
    /// Opaque body bounds in canvas units, normalized 0...1.
    var bodyBounds: CGRect
    var layers: [String: Layer]
    /// Reserved layer kinds the renderer tolerates but does not require
    /// (e.g. ["limbs"]).
    var optionalLayers: [String] = []

    static let currentVersion = 1

    var bodyLayer: Layer? { layers[LayerKind.body.rawValue] }
    var eyesLayer: Layer? { layers[LayerKind.eyes.rawValue] }
    var mouthLayer: Layer? { layers[LayerKind.mouth.rawValue] }

    /// Strict validation: any invalid geometry falls back to the
    /// single-sprite pipeline instead of rendering garbage.
    static func validated(_ manifest: WarawaraRigManifest) -> WarawaraRigManifest? {
        guard manifest.version == currentVersion else { return nil }
        guard manifest.canvas.width > 0, manifest.canvas.height > 0 else { return nil }
        guard isValidNormalizedPoint(manifest.anchor) else { return nil }
        guard isValidNormalizedRect(manifest.bodyBounds) else { return nil }
        guard let body = manifest.bodyLayer else { return nil }
        guard isValidLayer(body) else { return nil }
        for (key, layer) in manifest.layers {
            guard key == layer.kind.rawValue else { return nil }
            guard isValidLayer(layer) else { return nil }
        }
        return manifest
    }

    private static func isValidLayer(_ layer: Layer) -> Bool {
        guard !layer.images.isEmpty else { return false }
        guard isValidNormalizedPoint(layer.anchor) else { return false }
        if let gaze = layer.gazeRange {
            guard gaze.width >= 0, gaze.height >= 0 else { return false }
        }
        if let pivot = layer.pivot {
            guard isValidNormalizedPoint(pivot) else { return false }
        }
        return true
    }

    private static func isValidNormalizedPoint(_ point: CGPoint) -> Bool {
        point.x >= 0 && point.x <= 1 && point.y >= 0 && point.y <= 1
    }

    private static func isValidNormalizedRect(_ rect: CGRect) -> Bool {
        rect.minX >= 0 && rect.minY >= 0 && rect.maxX <= 1 && rect.maxY <= 1
            && rect.width > 0 && rect.height > 0
    }
}
