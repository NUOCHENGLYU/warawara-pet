import CoreGraphics
import Foundation

/// Semantic world anchors derived from the main pet's WINDOW frame in
/// AppKit screen coordinates (bottom-left origin). Every event prop is
/// placed through these anchors — never via a generic corner fallback.
struct EventAnchorSystem {
    let petFrame: CGRect

    init(petFrame: CGRect) {
        self.petFrame = petFrame
    }

    /// Character body footprint inside the pet window (shared with the
    /// birthday layout definition — one source of truth).
    var bodyRect: CGRect { BirthdayPropLayout.petBodyRect(petFrame: petFrame) }

    /// Front-center of the body, slightly above the resting baseline:
    /// the catch/hold point for held props (hongbao).
    var handFront: CGPoint {
        CGPoint(x: bodyRect.midX, y: bodyRect.minY + bodyRect.height * 0.52)
    }

    /// Head-center of the body (attention targets derive from here).
    var headCenter: CGPoint {
        CGPoint(x: bodyRect.midX, y: bodyRect.minY + bodyRect.height * 0.86)
    }

    /// Just above the head (entry point for falling props, umbrella
    /// canopy position).
    var aboveHead: CGPoint {
        CGPoint(x: bodyRect.midX, y: bodyRect.minY + bodyRect.height + 36)
    }

    /// Ground beside the body (right side, resting baseline): calendar,
    /// gift, umbrella reach target.
    var groundBesidePet: CGPoint {
        CGPoint(x: bodyRect.maxX + 24, y: bodyRect.minY + 8)
    }

    /// Left ground point (sprout).
    var nearLeftFoot: CGPoint {
        CGPoint(x: bodyRect.minX - 14, y: bodyRect.minY + 4)
    }

    /// Right ground point (cocoa).
    var nearRightFoot: CGPoint {
        CGPoint(x: bodyRect.maxX - 4, y: bodyRect.minY + 4)
    }

    /// Umbrella handle grip: slightly in front of the hand anchor.
    var umbrellaGrip: CGPoint {
        CGPoint(x: handFront.x + 16, y: handFront.y - 10)
    }
}
