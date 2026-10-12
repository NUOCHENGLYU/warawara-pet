import XCTest
@testable import WarawaraPet

final class GroupSequenceModelTests: XCTestCase {
    private let tuning = GroupTuning.default
    private let mainCenter = CGPoint(x: 500, y: 300)
    private let physicalFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let visibleFrame = CGRect(x: 0, y: 60, width: 1000, height: 740)

    func testBeginFromInactiveCreatesCompanionsAndFormation() {
        var model = GroupSequenceModel()
        var rng = SeededRandomSource(seed: 11)
        XCTAssertTrue(
            model.begin(
                mainCenter: mainCenter,
                physicalFrame: physicalFrame,
                visibleFrame: visibleFrame,
                using: &rng,
                tuning: tuning
            )
        )
        XCTAssertEqual(model.state, .appearing)
        XCTAssertEqual(model.companions.count, tuning.companionCount)
        XCTAssertEqual(model.formationOffsets.count, tuning.companionCount)
    }

    func testEntryPointsAreFullyOutsidePhysicalScreen() {
        var model = GroupSequenceModel()
        var rng = SeededRandomSource(seed: 40)
        XCTAssertTrue(
            model.begin(
                mainCenter: mainCenter,
                physicalFrame: physicalFrame,
                visibleFrame: visibleFrame,
                using: &rng,
                tuning: tuning
            )
        )
        for companion in model.companions {
            XCTAssertTrue(
                GroupMotionMath.isOutside(companion.config.entryPoint, frame: physicalFrame),
                "every companion must start fully outside the physical screen"
            )
        }
    }

    func testSecondSequenceIsRejectedWhileActive() {
        var model = GroupSequenceModel()
        var rng = SeededRandomSource(seed: 12)
        XCTAssertTrue(
            model.begin(
                mainCenter: mainCenter,
                physicalFrame: physicalFrame,
                visibleFrame: visibleFrame,
                using: &rng,
                tuning: tuning
            )
        )
        XCTAssertFalse(
            model.begin(
                mainCenter: mainCenter,
                physicalFrame: physicalFrame,
                visibleFrame: visibleFrame,
                using: &rng,
                tuning: tuning
            )
        )
        XCTAssertEqual(model.companions.count, tuning.companionCount)
    }

    func testCompletionLeavesZeroCompanions() {
        var model = GroupSequenceModel()
        var rng = SeededRandomSource(seed: 13)
        XCTAssertTrue(
            model.begin(
                mainCenter: mainCenter,
                physicalFrame: physicalFrame,
                visibleFrame: visibleFrame,
                using: &rng,
                tuning: tuning
            )
        )
        XCTAssertTrue(model.advance(to: .gathering))
        XCTAssertTrue(model.advance(to: .hovering))
        XCTAssertTrue(model.advance(to: .ascending))
        XCTAssertTrue(model.advance(to: .finishing))
        model.removeAllCompanions()
        XCTAssertTrue(model.advance(to: .inactive))
        XCTAssertEqual(model.companions.count, 0)
        XCTAssertEqual(model.state, .inactive)
    }

    func testCancellationLeavesZeroCompanions() {
        for phase in [GroupSequenceState.appearing, .gathering, .hovering, .ascending] {
            var model = GroupSequenceModel()
            var rng = SeededRandomSource(seed: 14)
            XCTAssertTrue(
                model.begin(
                    mainCenter: mainCenter,
                    physicalFrame: physicalFrame,
                    visibleFrame: visibleFrame,
                    using: &rng,
                    tuning: tuning
                )
            )
            if phase != .appearing {
                if phase == .gathering {
                    XCTAssertTrue(model.advance(to: .gathering))
                } else if phase == .hovering {
                    XCTAssertTrue(model.advance(to: .gathering))
                    XCTAssertTrue(model.advance(to: .hovering))
                } else {
                    XCTAssertTrue(model.advance(to: .gathering))
                    XCTAssertTrue(model.advance(to: .hovering))
                    XCTAssertTrue(model.advance(to: .ascending))
                }
            }
            XCTAssertTrue(model.advance(to: .cancelled))
            model.removeAllCompanions()
            XCTAssertTrue(model.advance(to: .inactive))
            XCTAssertEqual(model.companions.count, 0)
            XCTAssertEqual(model.state, .inactive)
        }
    }

    func testRepeatedCompletionAndCancellationAreHarmless() {
        var model = GroupSequenceModel()
        var rng = SeededRandomSource(seed: 41)
        XCTAssertTrue(
            model.begin(
                mainCenter: mainCenter,
                physicalFrame: physicalFrame,
                visibleFrame: visibleFrame,
                using: &rng,
                tuning: tuning
            )
        )
        XCTAssertTrue(model.advance(to: .gathering))
        XCTAssertTrue(model.advance(to: .cancelled))
        XCTAssertTrue(model.advance(to: .inactive))
        // Repeated end-of-sequence bookkeeping is a no-op.
        model.removeAllCompanions()
        XCTAssertFalse(model.advance(to: .inactive))
        XCTAssertFalse(model.advance(to: .cancelled))
        XCTAssertEqual(model.companions.count, 0)
        XCTAssertEqual(model.state, .inactive)
        // And a new sequence can start cleanly afterwards.
        XCTAssertTrue(
            model.begin(
                mainCenter: mainCenter,
                physicalFrame: physicalFrame,
                visibleFrame: visibleFrame,
                using: &rng,
                tuning: tuning
            )
        )
        XCTAssertEqual(model.state, .appearing)
    }

    func testCompanionConfigsAreDeterministicAndVaried() {
        var a = SeededRandomSource(seed: 20)
        var b = SeededRandomSource(seed: 20)
        let configsA = (0..<4).map {
            CompanionConfig.make(
                id: $0, mainCenter: mainCenter,
                physicalFrame: physicalFrame, visibleFrame: visibleFrame,
                using: &a, tuning: tuning
            )
        }
        let configsB = (0..<4).map {
            CompanionConfig.make(
                id: $0, mainCenter: mainCenter,
                physicalFrame: physicalFrame, visibleFrame: visibleFrame,
                using: &b, tuning: tuning
            )
        }
        XCTAssertEqual(configsA, configsB)

        let scales = Set(configsA.map(\.scale))
        XCTAssertGreaterThan(scales.count, 1)
        let entryX = Set(configsA.map { $0.entryPoint.x })
        XCTAssertGreaterThan(entryX.count, 1, "entry points should differ")
        let springs = Set(configsA.map(\.springStrength))
        XCTAssertGreaterThan(springs.count, 1)
    }

    func testConfigBoundsAreRespected() {
        var rng = SeededRandomSource(seed: 21)
        for id in 0..<20 {
            let config = CompanionConfig.make(
                id: id, mainCenter: mainCenter,
                physicalFrame: physicalFrame, visibleFrame: visibleFrame,
                using: &rng, tuning: tuning
            )
            XCTAssertTrue(tuning.companionScaleRange.contains(config.scale))
            XCTAssertGreaterThanOrEqual(config.releaseDelay, TimeInterval(id) * tuning.releaseStagger)
            XCTAssertGreaterThan(config.springStrength, 0)
            XCTAssertGreaterThan(config.damping, 0)
            XCTAssertTrue(tuning.exitStaggerRange.contains(config.exitStagger))
            XCTAssertGreaterThan(config.exitTargetOffset.dy, 0)
        }
    }

    func testFormationOffsetsAreStableAcrossPhases() {
        var model = GroupSequenceModel()
        var rng = SeededRandomSource(seed: 22)
        XCTAssertTrue(
            model.begin(
                mainCenter: mainCenter,
                physicalFrame: physicalFrame,
                visibleFrame: visibleFrame,
                using: &rng,
                tuning: tuning
            )
        )
        let before = model.formationOffsets
        XCTAssertTrue(model.advance(to: .gathering))
        XCTAssertTrue(model.advance(to: .hovering))
        XCTAssertEqual(model.formationOffsets, before)
    }
}

final class GroupLaunchTriggerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "GroupLaunchTriggerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFlagIsConsumedExactlyOnce() {
        defaults.set(true, forKey: GroupLaunchTrigger.defaultsKey)
        XCTAssertTrue(GroupLaunchTrigger.consumeOnceFlag(defaults: defaults))
        XCTAssertFalse(defaults.bool(forKey: GroupLaunchTrigger.defaultsKey))
        XCTAssertFalse(GroupLaunchTrigger.consumeOnceFlag(defaults: defaults))
    }

    func testAbsentFlagDoesNothing() {
        XCTAssertFalse(GroupLaunchTrigger.consumeOnceFlag(defaults: defaults))
    }
}
