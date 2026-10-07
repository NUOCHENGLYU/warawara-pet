import Foundation

enum AutonomousAction: Equatable {
    case hop
    case float
}

/// Pure, bounded autonomous scheduling.
///
/// The one-shot autonomous timer ALWAYS uses the short hop-range delay, so
/// a rare float never blocks hop activity for long periods. Floats are
/// gated instead by a cooldown: `floatEligibleSince` is the earliest time
/// a float may be chosen again, and each eligible fire has only a small
/// `floatChance` probability of producing a float.
enum AutonomousScheduler {
    static func nextAction(
        now: TimeInterval,
        floatEligibleSince: TimeInterval,
        using rng: inout some RandomSource,
        tuning: PersonalityTuning
    ) -> AutonomousAction {
        if now >= floatEligibleSince, rng.nextUnit() < tuning.floatChance {
            return .float
        }
        return .hop
    }

    static func nextDelay(
        using rng: inout some RandomSource,
        tuning: PersonalityTuning
    ) -> TimeInterval {
        RandomBounds.randomDelay(in: tuning.hopMinDelay...tuning.hopMaxDelay, using: &rng)
    }
}
