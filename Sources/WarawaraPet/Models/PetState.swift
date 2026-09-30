import Foundation

enum PetState: Equatable {
    case idle
    case hop
    case clicked
    case dragged
    case settling
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

struct PetStateMachine {
    private(set) var state: PetState = .idle

    static func canTransition(from: PetState, to: PetState) -> Bool {
        switch (from, to) {
        case (.idle, .hop), (.idle, .clicked), (.idle, .dragged):
            return true
        case (.hop, .idle), (.hop, .dragged):
            return true
        case (.clicked, .idle), (.clicked, .clicked), (.clicked, .dragged):
            return true
        case (.dragged, .settling):
            return true
        case (.settling, .idle), (.settling, .dragged):
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
}
