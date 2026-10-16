import Foundation

/// Explicit event-specific attention targets for the birthday
/// choreography. The main pet orients toward these in turn — never the
/// generic ambient mouse-curiosity.
enum BirthdayAttentionTarget: Equatable {
    /// Looking toward the lead carrying companion (during entry).
    case leadCompanion
    /// Looking toward the cake delivery point (during delivery).
    case cakeDelivery
    /// Looking toward the envelope delivery point (during the reveal).
    case envelopeDelivery
    /// Looking at the celebration center (companions + cake together).
    case celebrationCenter
    /// Attention released (pet returns to its normal life).
    case none

    /// Which target the coordinator expects for each phase.
    static func expected(for phase: BirthdayPhase) -> BirthdayAttentionTarget {
        switch phase {
        case .idle, .cancelled:
            return .none
        case .noticing:
            return .leadCompanion
        case .gathering:
            return .leadCompanion
        case .celebrating:
            return .cakeDelivery
        case .awaitingLetter, .completed:
            return .envelopeDelivery
        }
    }
}

/// Pure math for event attention: a normalized, deadbanded direction
/// from the pet's center toward a target point, in the canonical
/// UP-POSITIVE screen coordinate convention (reused by the existing
/// 2.5D gaze pipeline).
enum EventAttentionMath {
    /// Direction from `petCenter` to `target`. Tiny movements are
    /// deadbanded so the gaze never jitters when carriers settle.
    static func direction(from petCenter: CGPoint, to target: CGPoint) -> CGVector {
        let dx = target.x - petCenter.x
        let dy = target.y - petCenter.y
        let distance = hypot(dx, dy)
        guard distance > 2 else { return .zero }
        let vector = CGVector(dx: dx / distance, dy: dy / distance)
        guard hypot(vector.dx, vector.dy) > 0.05 else { return .zero }
        return CGVector(
            dx: min(max(vector.dx, -1), 1),
            dy: min(max(vector.dy, -1), 1)
        )
    }

    /// Whether two directions differ enough to justify an update
    /// (prevents per-tick republishing of nearly identical gaze).
    static func differs(_ a: CGVector, _ b: CGVector, threshold: CGFloat = 0.15) -> Bool {
        hypot(a.dx - b.dx, a.dy - b.dy) > threshold
    }
}
