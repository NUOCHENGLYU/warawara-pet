import Foundation

enum PetState: Equatable {
    case idle
    case hop
    case float
    case curious
    case clicked
    case dragged
    case settling
    case sleepy
    case sleeping
}

struct HopParameters: Equatable {
    let height: CGFloat
    let drift: CGFloat
    let duration: TimeInterval
}

extension HopParameters {
    static func random(using rng: inout some RandomSource) -> HopParameters {
        HopParameters(
            height: RandomBounds.randomCGFloat(in: 60...120, using: &rng),
            drift: RandomBounds.randomCGFloat(in: -40...40, using: &rng),
            duration: RandomBounds.randomDelay(in: 0.9...1.4, using: &rng)
        )
    }
}

struct FloatParameters: Equatable {
    let height: CGFloat
    let drift: CGFloat
    let duration: TimeInterval
    let swayPhase: CGFloat
}

extension FloatParameters {
    static func random(
        using rng: inout some RandomSource,
        tuning: PersonalityTuning
    ) -> FloatParameters {
        FloatParameters(
            height: RandomBounds.randomCGFloat(
                in: 0.8 * tuning.floatHeight...1.2 * tuning.floatHeight,
                using: &rng
            ),
            drift: RandomBounds.randomCGFloat(
                in: 0.6 * tuning.floatHorizontalDrift...1.3 * tuning.floatHorizontalDrift,
                using: &rng
            ),
            duration: RandomBounds.randomDelay(
                in: 0.85 * tuning.floatDuration...1.15 * tuning.floatDuration,
                using: &rng
            ),
            swayPhase: RandomBounds.randomCGFloat(in: 0...(2 * .pi), using: &rng)
        )
    }
}

struct PetStateMachine {
    private(set) var state: PetState = .idle

    static func canTransition(from: PetState, to: PetState) -> Bool {
        switch (from, to) {
        case (.idle, .hop), (.idle, .float), (.idle, .curious), (.idle, .sleepy),
             (.idle, .clicked), (.idle, .dragged):
            return true
        case (.hop, .idle), (.hop, .dragged):
            return true
        case (.float, .idle), (.float, .clicked), (.float, .dragged):
            return true
        case (.curious, .idle), (.curious, .clicked), (.curious, .dragged):
            return true
        case (.clicked, .idle), (.clicked, .clicked), (.clicked, .settling), (.clicked, .dragged):
            return true
        case (.dragged, .settling):
            return true
        case (.settling, .idle), (.settling, .dragged):
            return true
        case (.sleepy, .sleeping), (.sleepy, .idle), (.sleepy, .clicked), (.sleepy, .dragged):
            return true
        case (.sleeping, .clicked), (.sleeping, .dragged):
            return true
        default:
            return false
        }
    }

    @discardableResult
    mutating func transition(to newState: PetState) -> Bool {
        guard Self.canTransition(from: state, to: newState) else { return false }
        state = newState
        return true
    }

    /// Debug-only bypass of the transition table, used exclusively by the
    /// Force developer controls. Never used by normal runtime logic.
    mutating func forceTransition(to newState: PetState) {
        state = newState
    }
}
