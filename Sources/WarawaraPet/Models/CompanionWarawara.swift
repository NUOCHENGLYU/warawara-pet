import Foundation

/// All Phase 3 group-sequence visual tuning in one place. These are
/// initial values; they will be tuned on a real Mac later.
struct GroupTuning {
    var companionCount: Int = 4
    var companionPanelSize: CGFloat = 96

    // Appearance: companions enter from outside the physical screen
    var entryMargin: CGFloat = 24
    var entryJitterRange: ClosedRange<CGFloat> = 0...80
    var releaseStagger: TimeInterval = 0.35
    var releaseDelayJitter: TimeInterval = 0.15

    // Inertial gathering (second-order spring/damper motion)
    var gatherSpringStrength: CGFloat = 8
    var gatherSpringVariation: CGFloat = 1.5
    var gatherDamping: CGFloat = 5.5
    var gatherDampingVariation: CGFloat = 1.0
    var gatherSettleSpeed: CGFloat = 6
    var gatherSettleDistance: CGFloat = 6
    var gatherMaxDuration: TimeInterval = 4.5

    // Loose formation slots (spacing / separation)
    var formationRadius: CGFloat = 115
    var formationRadiusVariation: CGFloat = 12
    var preferredMainPetRadius: CGFloat = 90
    var companionMinSpacing: CGFloat = 88
    var separationStrength: CGFloat = 0.6
    var formationMargin: CGFloat = 24

    // Hover (position-continuous with gathering)
    var hoverDuration: TimeInterval = 2.8
    var hoverRampInDuration: TimeInterval = 0.7
    var hoverBobAmplitude: CGFloat = 6
    var hoverBobPeriod: TimeInterval = 2.6
    var hoverDriftAmplitude: CGFloat = 10

    // Ascent fan-out (per-companion exit trajectories)
    var ascentRiseHeightMin: CGFloat = 700
    var ascentRiseHeightMax: CGFloat = 1100
    var ascentSpringStrength: CGFloat = 1.1
    var ascentDamping: CGFloat = 2.1
    var ascentSwayAmplitude: CGFloat = 10
    var ascentSwayPeriod: TimeInterval = 2.8
    var fanSpreadRange: ClosedRange<CGFloat> = 130...280
    var fanAngleJitter: CGFloat = 0.25
    var exitStaggerRange: ClosedRange<TimeInterval> = 0...0.5
    /// Emergency fallback only: a companion still on screen after this
    /// long is parked off-screen. Normal exits happen spatially first.
    var ascentMaxDuration: TimeInterval = 10
    var exitTopMargin: CGFloat = 24
    var exitSideMargin: CGFloat = 60

    // Fade (cancellation)
    var fadeOutDuration: TimeInterval = 0.4

    // Companion visual variety
    var companionScaleRange: ClosedRange<CGFloat> = 0.85...1.15

    // Developer trigger
    var triggerDelayRange: ClosedRange<TimeInterval> = 2...4

    static let `default` = GroupTuning()
}

/// Per-companion variation, generated once per sequence. Entry points are
/// absolute positions fully outside the physical screen frame; exit
/// targets are offsets from the companion's ascent start. Everything stays
/// stable for the whole sequence (never re-randomized at phase boundaries).
struct CompanionConfig: Equatable {
    let id: Int
    let entryPoint: CGPoint
    let releaseDelay: TimeInterval
    let bobPhase: CGFloat
    let driftPhase: CGFloat
    let scale: CGFloat
    let springStrength: CGFloat
    let damping: CGFloat
    /// Persistent fan-out trajectory for the ascent: horizontal direction
    /// and magnitude plus vertical rise (with per-companion speed
    /// variation baked into the rise height).
    let exitTargetOffset: CGVector
    let exitStagger: TimeInterval

    static func make(
        id: Int,
        mainCenter: CGPoint,
        physicalFrame: CGRect,
        visibleFrame: CGRect,
        using rng: inout some RandomSource,
        tuning: GroupTuning
    ) -> CompanionConfig {
        let edge = GroupMotionMath.entryEdge(
            index: id,
            count: tuning.companionCount,
            mainCenter: mainCenter,
            physicalFrame: physicalFrame,
            using: &rng,
            tuning: tuning
        )
        let entryPoint = GroupMotionMath.entryPosition(
            edge: edge,
            mainCenter: mainCenter,
            physicalFrame: physicalFrame,
            panelSize: tuning.companionPanelSize,
            using: &rng,
            tuning: tuning
        )

        let releaseDelay = TimeInterval(id) * tuning.releaseStagger
            + RandomBounds.randomDelay(in: 0...tuning.releaseDelayJitter, using: &rng)
        let bobPhase = RandomBounds.randomCGFloat(in: 0...(2 * .pi), using: &rng)
        let driftPhase = RandomBounds.randomCGFloat(in: 0...(2 * .pi), using: &rng)
        let scale = RandomBounds.randomCGFloat(in: tuning.companionScaleRange, using: &rng)
        let springStrength = tuning.gatherSpringStrength
            + RandomBounds.randomCGFloat(in: -tuning.gatherSpringVariation...tuning.gatherSpringVariation, using: &rng)
        let damping = tuning.gatherDamping
            + RandomBounds.randomCGFloat(in: -tuning.gatherDampingVariation...tuning.gatherDampingVariation, using: &rng)

        // Fan-out direction across the group: upper-left ... upper-right,
        // jittered, with per-companion spread and rise variation.
        let count = max(tuning.companionCount, 2)
        let fanAngle = .pi * (0.15 + 0.7 * CGFloat(id) / CGFloat(count - 1))
            + RandomBounds.randomCGFloat(in: -tuning.fanAngleJitter...tuning.fanAngleJitter, using: &rng)
        let spread = RandomBounds.randomCGFloat(in: tuning.fanSpreadRange, using: &rng)
        let rise = RandomBounds.randomCGFloat(
            in: tuning.ascentRiseHeightMin...tuning.ascentRiseHeightMax, using: &rng
        )
        let exitStagger = RandomBounds.randomDelay(
            in: tuning.exitStaggerRange, using: &rng
        )
        let rawExit = CGVector(dx: cos(fanAngle) * spread, dy: rise)
        let exitTargetOffset = GroupMotionMath.clampExitOffset(
            mainCenter: mainCenter,
            offset: rawExit,
            visibleFrame: physicalFrame,
            sideMargin: tuning.exitSideMargin
        )

        return CompanionConfig(
            id: id,
            entryPoint: entryPoint,
            releaseDelay: releaseDelay,
            bobPhase: bobPhase,
            driftPhase: driftPhase,
            scale: scale,
            springStrength: max(springStrength, 0.5),
            damping: max(damping, 0.1),
            exitTargetOffset: exitTargetOffset,
            exitStagger: exitStagger
        )
    }
}

struct CompanionWarawara: Equatable {
    let config: CompanionConfig
}

/// Pure model for the group sequence: explicit phase machine plus the
/// companion set and the stable loose-formation targets generated once at
/// sequence start. The AppKit controller drives this model and maps
/// companions to panels; tests never need real windows.
struct GroupSequenceModel {
    private(set) var machine = GroupSequenceStateMachine()
    private(set) var companions: [CompanionWarawara] = []
    /// Stable formation offsets from the main pet's center, one per
    /// companion, generated once for the whole sequence.
    private(set) var formationOffsets: [CGVector] = []

    var state: GroupSequenceState { machine.state }

    @discardableResult
    mutating func begin(
        mainCenter: CGPoint,
        physicalFrame: CGRect,
        visibleFrame: CGRect,
        using rng: inout some RandomSource,
        tuning: GroupTuning
    ) -> Bool {
        guard machine.transition(to: .appearing) else { return false }
        companions = (0..<tuning.companionCount).map { id in
            CompanionWarawara(
                config: CompanionConfig.make(
                    id: id,
                    mainCenter: mainCenter,
                    physicalFrame: physicalFrame,
                    visibleFrame: visibleFrame,
                    using: &rng,
                    tuning: tuning
                )
            )
        }
        formationOffsets = GroupMotionMath.formationOffsets(
            count: tuning.companionCount,
            mainCenter: mainCenter,
            visibleFrame: visibleFrame,
            using: &rng,
            tuning: tuning
        )
        return true
    }

    @discardableResult
    mutating func advance(to newState: GroupSequenceState) -> Bool {
        machine.transition(to: newState)
    }

    mutating func removeAllCompanions() {
        companions.removeAll()
    }
}
