import Foundation

enum CuriosityPhase: Equatable {
    case away
    case watching
    case engaged
}

/// Pure hysteresis + dwell detector for cursor proximity.
/// - enters only after the pointer stays inside `curiosityEnterRadius`
///   for `curiosityDwellTime` (transient passes never engage)
/// - exits only beyond `curiosityExitRadius` (band is sticky: no flicker)
struct CuriosityDetector {
    var tuning: PersonalityTuning

    private(set) var phase: CuriosityPhase = .away
    private(set) var dwellProgress: CGFloat = 0
    private var insideSince: TimeInterval?

    init(tuning: PersonalityTuning = .default) {
        self.tuning = tuning
    }

    mutating func update(distance: CGFloat, at timestamp: TimeInterval) {
        switch phase {
        case .away:
            guard distance < tuning.curiosityEnterRadius else {
                insideSince = nil
                dwellProgress = 0
                return
            }
            let since = insideSince ?? timestamp
            insideSince = since
            let dwell = timestamp - since
            dwellProgress = min(max(CGFloat(dwell / tuning.curiosityDwellTime), 0), 1)
            phase = dwell >= tuning.curiosityDwellTime ? .engaged : .watching
        case .watching:
            guard distance < tuning.curiosityEnterRadius else {
                phase = .away
                insideSince = nil
                dwellProgress = 0
                return
            }
            let since = insideSince ?? timestamp
            insideSince = since
            let dwell = timestamp - since
            dwellProgress = min(max(CGFloat(dwell / tuning.curiosityDwellTime), 0), 1)
            if dwell >= tuning.curiosityDwellTime {
                phase = .engaged
                dwellProgress = 1
            }
        case .engaged:
            if distance > tuning.curiosityExitRadius {
                phase = .away
                insideSince = nil
                dwellProgress = 0
            }
            // Inside the band between enter and exit radius the detector
            // stays engaged: distance hysteresis.
        }
    }

    var isWatching: Bool { phase == .watching }
    var isEngaged: Bool { phase == .engaged }

    /// Debug hook (Force Curious developer control): enters the engaged
    /// phase immediately. Normal exit rules still apply.
    mutating func forceEngage() {
        phase = .engaged
        dwellProgress = 1
        insideSince = nil
    }
}
