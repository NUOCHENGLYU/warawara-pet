import Foundation

/// Gentle, time-based float motion: slow lift, buoyant sway, soft return
/// to the exact launch position. Not a jump.
enum FloatCurve {
    /// Vertical offset: 0 at start and end, peak at t = 0.5 (soft hover).
    static func offsetY(at t: CGFloat, height: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return height * sin(.pi * clamped)
    }

    /// Horizontal sway, enveloped so it is 0 at start and end.
    static func offsetX(at t: CGFloat, drift: CGFloat, phase: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return drift * sin(.pi * clamped) * sin(2 * .pi * clamped + phase)
    }

    /// Buoyant vertical elongation while in motion: 1 at the ends (lifting
    /// or landing), 0 at the hover apex.
    static func liftStretch(at t: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return abs(cos(.pi * clamped))
    }
}
