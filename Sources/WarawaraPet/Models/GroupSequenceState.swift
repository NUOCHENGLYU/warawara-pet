import Foundation

enum GroupSequenceState: Equatable {
    case inactive
    case appearing
    case gathering
    case hovering
    case ascending
    case finishing
    case cancelled
}

/// Explicit state machine for the companion group sequence. Only one
/// sequence may run at a time: the only way out of `inactive` is
/// `appearing`, and every active phase can be cancelled.
struct GroupSequenceStateMachine {
    private(set) var state: GroupSequenceState = .inactive

    static func canTransition(from: GroupSequenceState, to: GroupSequenceState) -> Bool {
        switch (from, to) {
        case (.inactive, .appearing):
            return true
        case (.appearing, .gathering), (.appearing, .cancelled):
            return true
        case (.gathering, .hovering), (.gathering, .cancelled):
            return true
        case (.hovering, .ascending), (.hovering, .cancelled):
            return true
        case (.ascending, .finishing), (.ascending, .cancelled):
            return true
        case (.finishing, .inactive):
            return true
        case (.cancelled, .inactive):
            return true
        default:
            return false
        }
    }

    @discardableResult
    mutating func transition(to newState: GroupSequenceState) -> Bool {
        guard Self.canTransition(from: state, to: newState) else { return false }
        state = newState
        return true
    }

    var isActive: Bool { state != .inactive }
}
