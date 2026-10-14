import Foundation

/// Visual deformation of the pet, computed from smoothed drag velocity and
/// the grab point. General enough to be reused later by hop/float/sleep
/// poses (those behaviors are not implemented yet).
struct PetDeformation: Equatable {
    /// Undirected stretch axis in radians, canonicalized to [0, .pi).
    /// Angles differing by .pi are the same axis: scaling along a line is
    /// symmetric, so 0 and .pi are equivalent.
    var stretchAngle: CGFloat = 0
    /// Scale along the stretch axis, >= 1.
    var stretchScale: CGFloat = 1
    /// Scale perpendicular to the stretch axis, <= 1. The product with
    /// `stretchScale` is 1, so volume is preserved.
    var perpendicularScale: CGFloat = 1
    /// Signed torque rotation in radians, CCW positive, capped by tuning.
    var rotation: CGFloat = 0
    /// Normalized grab anchor in pet space (x right, y up), clamped to an
    /// interior range by tuning. Rendering anchor and torque share this
    /// exact value so they can never disagree.
    var anchor: CGVector = .zero

    static let neutral = PetDeformation()
}

/// All Phase 1.6 tuning constants in one place. These values are the
/// defaults; they will be tuned manually on the M1 MacBook Air.
struct DeformationTuning {
    /// Exponential smoothing time constant for drag velocity (seconds).
    var velocityTimeConstant: TimeInterval = 0.12
    /// Gaps longer than this decay velocity toward zero (no spikes/freeze).
    var maxGapDuration: TimeInterval = 1.0
    /// Velocity (points/second) that produces exactly `maxStretch`.
    var velocityAtMaxStretch: CGFloat = 800
    /// Speeds at or below this produce no deformation (noise gate).
    var minimumSpeed: CGFloat = 20
    /// Maximum stretch amount: scaleAlong = 1 + maxStretch. Kept modest
    /// so drags feel soft-but-firm rather than gooey.
    var maxStretch: CGFloat = 0.24
    /// Hard cap for torque rotation in radians.
    var maxRotation: CGFloat = 0.12
    /// Radians per (grab-vector-unit * pt/s) of 2D torque.
    var rotationGain: CGFloat = 0.0005
    /// Clamp for each axis of the normalized grab anchor, e.g. 0.84 maps
    /// to UnitPoint range 0.08...0.92 so the pivot never sits on the edge.
    var grabAnchorLimit: CGFloat = 0.84
    /// Pause after the last movement sample before held-still decay kicks
    /// in. Keeps normal movement (fast successive events) unaffected.
    var decayStartDelay: TimeInterval = 0.05
    /// Spring used to return deformation to neutral after release.
    /// Slightly firmer than the pre-polish values: release settles
    /// quicker with less wobble.
    var releaseSpringResponse: Double = 0.25
    var releaseSpringDamping: Double = 0.5

    static let `default` = DeformationTuning()
}
