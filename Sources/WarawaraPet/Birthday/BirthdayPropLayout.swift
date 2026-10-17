import Foundation

/// Stable "birthday prop layout" relative to the main pet's resting
/// window frame. Props are delivered to these positions and then STAY
/// there (they never follow hop/float motion). Positions are pure and
/// deterministic so the choreography and tests share one definition.
struct BirthdayPropLayout {
    /// The pet's body footprint inside its window (bottom-left origin,
    /// conservative: the rig body ~115pt wide x 118pt tall resting on
    /// the established visual center).
    static func petBodyRect(petFrame: CGRect) -> CGRect {
        CGRect(
            x: petFrame.midX - 58,
            y: petFrame.minY + 54,
            width: 116,
            height: 118
        )
    }

    /// Cake resting in front of the pet on the desktop plane:
    /// front-left of the body, no overlap, painted art bottom slightly
    /// ABOVE the pet's feet line (visible, not too low).
    static func cakeOrigin(petFrame: CGRect, panelSize: CGSize) -> CGPoint {
        CGPoint(
            x: petFrame.midX - 58 - 12 - panelSize.width,
            y: petFrame.minY + 54 + 12 - panelSize.height + 32
        )
    }

    /// Envelope resting position: HELD in front of the pet's lower
    /// abdomen (like the pet is carrying it), bound to the pet frame.
    /// The panel center lands on the lower belly so the envelope art
    /// reads as held, not dropped beside the pet.
    static func envelopeOrigin(petFrame: CGRect, panelSize: CGSize) -> CGPoint {
        CGPoint(
            x: petFrame.midX + 20 - panelSize.width / 2,
            y: petFrame.minY + 82 - panelSize.height / 2
        )
    }

    /// Clamps a panel origin into the visible frame with a small margin.
    static func clamped(
        _ origin: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, visibleFrame.minX + 4), visibleFrame.maxX - panelSize.width - 4),
            y: min(max(origin.y, visibleFrame.minY + 4), visibleFrame.maxY - panelSize.height - 4)
        )
    }

    /// Delivery positions (already clamped): the single source of truth
    /// for where gifts rest after the event.
    static func deliveryOrigins(
        petFrame: CGRect,
        cakePanelSize: CGSize,
        envelopePanelSize: CGSize,
        visibleFrame: CGRect
    ) -> (cake: CGPoint, envelope: CGPoint) {
        (
            clamped(cakeOrigin(petFrame: petFrame, panelSize: cakePanelSize), panelSize: cakePanelSize, visibleFrame: visibleFrame),
            clamped(envelopeOrigin(petFrame: petFrame, panelSize: envelopePanelSize), panelSize: envelopePanelSize, visibleFrame: visibleFrame)
        )
    }
}
