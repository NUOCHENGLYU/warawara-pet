import Foundation

/// Single source of truth for pet geometry shared by rendering, hit
/// testing, and interaction. The window is sized so the maximum stretch
/// deformation envelope (including grab-anchor torque) never clips the
/// body silhouette, while the interaction hit region stays tight.
enum PetMetrics {
    static let size = CGSize(width: 200, height: 200)

    /// Resting bottom padding of the blob inside the window.
    static let blobBottomPadding: CGFloat = 54
    static let blobHeight: CGFloat = 118

    /// Visual center of the placeholder blob in pet space (bottom-left
    /// origin), matching EllipseHitRegion's default region.
    static let visualCenter = CGPoint(x: size.width / 2, y: blobBottomPadding + blobHeight / 2)

    /// Clearance between the blob's resting bottom and the window edge.
    static var bottomClearance: CGFloat { blobBottomPadding }

    /// Worst-case downward extension of the blob's bottom when stretched
    /// by `maxStretch` about the highest possible grab anchor (anchored at
    /// `grabAnchorLimit`). This must stay within `bottomClearance` so fast
    /// drags never visually clip the body.
    static func worstCaseDownwardExtension(
        maxStretch: CGFloat,
        grabAnchorLimit: CGFloat
    ) -> CGFloat {
        let anchorUnitY = 0.5 - 0.5 * grabAnchorLimit
        let anchorTop = size.height * (1 - anchorUnitY)
        return maxStretch * (anchorTop - blobBottomPadding)
    }

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
