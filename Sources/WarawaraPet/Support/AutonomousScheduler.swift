import Foundation

enum AutonomousAction: Equatable {
    case hop
    case float
}

/// Pure, bounded autonomous-action scheduling: rolls a rare float or a hop
/// with a randomized delay, driven by the injected random source.
enum AutonomousScheduler {
    static func nextDecision(
        using rng: inout some RandomSource,
        tuning: PersonalityTuning
    ) -> (action: AutonomousAction, delay: TimeInterval) {
        if rng.nextUnit() < tuning.floatChance {
            let delay = RandomBounds.randomDelay(
                in: tuning.floatMinInterval...tuning.floatMaxInterval,
                using: &rng
            )
            return (.float, delay)
        }
        let delay = RandomBounds.randomDelay(
            in: tuning.hopMinDelay...tuning.hopMaxDelay,
            using: &rng
        )
        return (.hop, delay)
    }
}
