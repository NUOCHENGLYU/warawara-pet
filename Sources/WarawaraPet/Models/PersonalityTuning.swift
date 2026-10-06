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

    // Float
    var floatChance: Double = 0.2
    var floatMinInterval: TimeInterval = 75
    var floatMaxInterval: TimeInterval = 210
    var floatMinHeight: CGFloat = 80
    var floatMaxHeight: CGFloat = 130
    var floatMinDrift: CGFloat = 30
    var floatMaxDrift: CGFloat = 70
    var floatMinDuration: TimeInterval = 4.5
    var floatMaxDuration: TimeInterval = 7.0
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
