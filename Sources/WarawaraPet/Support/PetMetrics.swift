import Foundation

/// Single source of truth for pet geometry shared by rendering, hit
/// testing, and interaction.
enum PetMetrics {
    static let size = CGSize(width: 160, height: 160)
    /// Visual center of the placeholder blob in pet space (bottom-left
    /// origin), matching EllipseHitRegion's default region.
    static let visualCenter = CGPoint(x: 80, y: 65)

    /// Normalized grab vector: offset from the visual center divided by
    /// half the window width and clamped to the unit square, so the result
    /// is independent of window size.
    static func normalizedGrabVector(grabPoint: CGPoint) -> CGVector {
        let half = size.width / 2
        let dx = min(max((grabPoint.x - visualCenter.x) / half, -1), 1)
        let dy = min(max((grabPoint.y - visualCenter.y) / half, -1), 1)
        return CGVector(dx: dx, dy: dy)
    }
}
