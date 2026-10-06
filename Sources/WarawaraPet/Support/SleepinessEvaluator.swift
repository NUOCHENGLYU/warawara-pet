import Foundation

enum SleepinessTransition: Equatable {
    case enterSleepy
    case enterSleeping
    case returnToIdle
}

/// Pure sleepiness decisions based on system idle time.
enum SleepinessEvaluator {
    static func decision(
        state: PetState,
        idleSeconds: TimeInterval,
        tuning: PersonalityTuning
    ) -> SleepinessTransition? {
        switch state {
        case .idle:
            return idleSeconds >= tuning.sleepyTimeout ? .enterSleepy : nil
        case .sleepy:
            if idleSeconds >= tuning.sleepTimeout { return .enterSleeping }
            if idleSeconds < tuning.sleepyTimeout { return .returnToIdle }
            return nil
        default:
            return nil
        }
    }
}
