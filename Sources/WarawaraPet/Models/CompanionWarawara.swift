import Foundation

/// All Phase 3 group-sequence visual tuning in one place. These are
/// initial values; they will be tuned on a real Mac later.
struct GroupTuning {
    var companionCount: Int = 4
    var companionPanelSize: CGFloat = 96

    // Appearance
    var spawnMinRadius: CGFloat = 90
    var spawnMaxRadius: CGFloat = 170
    var spawnElevationRange: ClosedRange<CGFloat> = -20...70
    var appearStagger: TimeInterval = 0.35
    var appearFadeDuration: TimeInterval = 0.6
    var spawnMargin: CGFloat = 16

    // Gathering
    var gatherMinDuration: TimeInterval = 1.6
    var gatherDurationVariation: TimeInterval = 0.9
    var gatherOffsetMinRadius: CGFloat = 30
    var gatherOffsetMaxRadius: CGFloat = 70

    // Hover
    var hoverDuration: TimeInterval = 3.0
    var hoverBobAmplitude: CGFloat = 6
    var hoverBobPeriod: TimeInterval = 2.6
    var hoverDriftAmplitude: CGFloat = 10

    // Ascent
    var ascentDuration: TimeInterval = 4.0
    var ascentBaseSpeed: CGFloat = 60
    var ascentAcceleration: CGFloat = 22
    var ascentWanderAmplitude: CGFloat = 14

    // Fade
    var fadeOutDuration: TimeInterval = 0.4

    // Companion visual variety
    var companionScaleRange: ClosedRange<CGFloat> = 0.85...1.15

    // Developer trigger
    var triggerDelayRange: ClosedRange<TimeInterval> = 2...4

    static let `default` = GroupTuning()
}

/// Per-companion variation. All offsets are relative to the main pet's
/// center. Generated deterministically from a random source + index.
struct CompanionConfig: Equatable {
    let id: Int
    let spawnOffset: CGVector
    let gatherOffset: CGVector
    let appearDelay: TimeInterval
    let gatherDuration: TimeInterval
    let bobPhase: CGFloat
    let driftPhase: CGFloat
    let scale: CGFloat

    static func make(
        id: Int,
        using rng: inout some RandomSource,
        tuning: GroupTuning
    ) -> CompanionConfig {
        let goldenAngle: CGFloat = 2.399963229728653
        let spawnAngle = CGFloat(id) * goldenAngle
            + RandomBounds.randomCGFloat(in: -0.4...0.4, using: &rng)
        let spawnRadius = RandomBounds.randomCGFloat(
            in: tuning.spawnMinRadius...tuning.spawnMaxRadius, using: &rng
        )
        let spawnElevation = RandomBounds.randomCGFloat(
            in: tuning.spawnElevationRange, using: &rng
        )
        let spawnOffset = CGVector(
            dx: cos(spawnAngle) * spawnRadius,
            dy: sin(spawnAngle) * spawnRadius * 0.7 + spawnElevation
        )

        let gatherAngle = spawnAngle
            + .pi * (0.7 + CGFloat(id % 2) * 0.6)
            + RandomBounds.randomCGFloat(in: -0.3...0.3, using: &rng)
        let gatherRadius = RandomBounds.randomCGFloat(
            in: tuning.gatherOffsetMinRadius...tuning.gatherOffsetMaxRadius, using: &rng
        )
        let gatherOffset = CGVector(
            dx: cos(gatherAngle) * gatherRadius,
            dy: sin(gatherAngle) * gatherRadius * 0.6
                + RandomBounds.randomCGFloat(in: -12...18, using: &rng)
        )

        let appearDelay = TimeInterval(id) * tuning.appearStagger
            + RandomBounds.randomDelay(in: 0...0.15, using: &rng)
        let gatherDuration = tuning.gatherMinDuration
            + RandomBounds.randomDelay(in: 0...tuning.gatherDurationVariation, using: &rng)
        let bobPhase = RandomBounds.randomCGFloat(in: 0...(2 * .pi), using: &rng)
        let driftPhase = RandomBounds.randomCGFloat(in: 0...(2 * .pi), using: &rng)
        let scale = RandomBounds.randomCGFloat(in: tuning.companionScaleRange, using: &rng)

        return CompanionConfig(
            id: id,
            spawnOffset: spawnOffset,
            gatherOffset: gatherOffset,
            appearDelay: appearDelay,
            gatherDuration: gatherDuration,
            bobPhase: bobPhase,
            driftPhase: driftPhase,
            scale: scale
        )
    }
}

struct CompanionWarawara: Equatable {
    let config: CompanionConfig
}

/// Pure model for the group sequence: explicit phase machine plus the
/// companion set. The AppKit controller drives this model and maps
/// companions to panels; tests never need real windows.
struct GroupSequenceModel {
    private(set) var machine = GroupSequenceStateMachine()
    private(set) var companions: [CompanionWarawara] = []

    var state: GroupSequenceState { machine.state }

    @discardableResult
    mutating func begin(
        using rng: inout some RandomSource,
        tuning: GroupTuning
    ) -> Bool {
        guard machine.transition(to: .appearing) else { return false }
        companions = (0..<tuning.companionCount).map { id in
            CompanionWarawara(config: CompanionConfig.make(id: id, using: &rng, tuning: tuning))
        }
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
