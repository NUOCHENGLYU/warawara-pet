import Foundation

enum HopCurve {
    static func offsetY(at t: CGFloat, height: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return 4 * height * clamped * (1 - clamped)
    }

    static func offsetX(at t: CGFloat, drift: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return drift * clamped
    }

    static func stretchFactor(at t: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return abs(1 - 2 * clamped)
    }

    static func squashAtLanding(at t: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        let centered = (clamped - 0.85) / 0.15
        guard abs(centered) <= 1 else { return 0 }
        return 1 - centered * centered
    }
}

enum SettleCurve {
    static let lambda: CGFloat = 5
    static let bounceCycles: CGFloat = 2

    static func offsetY(at t: CGFloat, amplitude: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return -amplitude * sin(.pi * bounceCycles * clamped) * exp(-lambda * clamped)
    }

    static func envelope(at t: CGFloat, amplitude: CGFloat) -> CGFloat {
        amplitude * exp(-lambda * min(max(t, 0), 1))
    }

    static func squashFactor(at t: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return 0.2 * (1 - clamped)
    }
}

/// Smoothstep interpolation used for the gentle post-float descent.
enum DescentCurve {
    static func interpolate(at t: CGFloat, from: CGFloat, to: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        let eased = clamped * clamped * (3 - 2 * clamped)
        return to + (from - to) * (1 - eased)
    }
}
