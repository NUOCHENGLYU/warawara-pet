import Foundation

/// Single source of truth for pet geometry shared by rendering, hit
/// testing, and interaction. The window is sized so the maximum stretch
/// deformation envelope (including grab-anchor torque and lean) never
/// clips the body silhouette in EITHER direction, while the interaction
/// hit region stays tight. The blob's bottom offset is fixed, so saved
/// window origins keep restoring to the same apparent position.
enum PetMetrics {
    static let blobWidth: CGFloat = 96
    static let blobHeight: CGFloat = 118
    /// Resting bottom padding of the blob inside the window. Kept stable
    /// across geometry changes so persisted window origins stay visually
    /// identical.
    static let blobBottomPadding: CGFloat = 54

    /// The pet's drawing canvas. Bottom and top clearance both cover the
    /// worst-case deformation envelope.
    static let size = CGSize(width: 200, height: 226)
    static let topClearance = size.height - blobBottomPadding - blobHeight

    /// Extra transparent drawing room ABOVE the pet canvas. It absorbs the
    /// poof transition's hop + stretch + smoke without moving or resizing
    /// the character (the canvas stays bottom-anchored in this window).
    static let topDrawingMargin: CGFloat = 50
    static let windowSize = CGSize(width: size.width, height: size.height + topDrawingMargin)

    /// Visual center of the placeholder blob in pet space (bottom-left
    /// origin), matching EllipseHitRegion's default region.
    static let visualCenter = CGPoint(x: size.width / 2, y: blobBottomPadding + blobHeight / 2)

    /// Top-left Y (view coords) where the head top sits. The layered rig
    /// and the placeholder share this line by construction (body bounds
    /// and bottom padding agree), so the sleep "Z" is anchored to it.
    static var headTopY: CGFloat { size.height - blobBottomPadding - blobHeight }

    /// Base top-left Y for the sleep "Z": just above the head top.
    static var sleepZBaseY: CGFloat { headTopY - 14 }

    /// Clearance between the blob's resting bottom and the window edge.
    static var bottomClearance: CGFloat { blobBottomPadding }

    /// Worst-case vertical extension of the blob silhouette in either
    /// direction: full stretch about the farthest blob-internal anchor
    /// plus the lean rotation's vertical contribution.
    static func worstCaseVerticalExtension(maxStretch: CGFloat, maxLean: CGFloat) -> CGFloat {
        maxStretch * blobHeight + (blobWidth / 2) * sin(maxLean)
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
