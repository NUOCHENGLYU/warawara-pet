import Foundation

/// All Phase 2 personality tuning constants in one place. Defaults are
/// quiet production values; they are tuned on the M1 MacBook Air.
struct PersonalityTuning {
    // Curiosity
    var curiosityEnterRadius: CGFloat = 110
    var curiosityExitRadius: CGFloat = 170
    var curiosityDwellTime: TimeInterval = 1.2
    var curiosityMaxRotation: CGFloat = 0.08
    var curiosityMaxStretch: CGFloat = 0.05
    var curiositySmoothingTimeConstant: TimeInterval = 0.25
    /// Cadence of the visual-tracking loop, active only while curious.
    /// State detection stays on `awarenessTickInterval`; 30 Hz is the
    /// initial target and can be raised to 60 Hz for smoother tracking.
    var curiosityTrackingInterval: TimeInterval = 1.0 / 30.0

    // Float — sustained drifting, clearly distinct from hop.
    // NOTE: floatChance and the cooldown range below are TEMPORARY high-
    // frequency values for M1 Air tuning; revisit before the final build.
    var floatChance: Double = 0.75
    /// Minimum/maximum time between floats. The scheduler keeps hopping
    /// normally; floats only become eligible again after this cooldown,
    /// which is drawn randomly from the range at each float start.
    var floatCooldownMin: TimeInterval = 20
    var floatCooldownMax: TimeInterval = 35
    var floatDuration: TimeInterval = 6.5
    var floatLiftFraction: CGFloat = 0.29
    var floatHoverFraction: CGFloat = 0.43
    var floatDescentFraction: CGFloat = 0.25
    var floatHeight: CGFloat = 145
    var floatBobAmplitude: CGFloat = 16
    var floatBobPeriod: TimeInterval = 2.2
    var floatSwayAmplitude: CGFloat = 45
    var floatSwayPeriod: TimeInterval = 3.5
    var floatHorizontalDrift: CGFloat = 25
    var floatBodyStretch: CGFloat = 0.06
    var floatSwayLean: CGFloat = 0.03
    /// Descent duration used when a click interrupts a float and the pet
    /// sinks back to the float base.
    var floatDescentDuration: TimeInterval = 0.45

    // Hop scheduling (moved from PetController)
    var hopMinDelay: TimeInterval = 6
    var hopMaxDelay: TimeInterval = 14

    // Sleep (quiet production defaults; use 15/30 for quick real-Mac tests)
    var sleepyTimeout: TimeInterval = 240
    var sleepTimeout: TimeInterval = 480
    var breathingPeriod: TimeInterval = 4.0
    var wakeTransitionDuration: TimeInterval = 0.3

    // Awareness loop
    var awarenessTickInterval: TimeInterval = 0.15
    var sleepinessCheckInterval: Int = 6

    static let `default` = PersonalityTuning()
}
