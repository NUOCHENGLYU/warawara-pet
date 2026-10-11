import XCTest
@testable import WarawaraPet

final class GroupMotionMathTests: XCTestCase {
    private let tuning = GroupTuning.default

    private func makeConfig(seed: UInt64, id: Int) -> CompanionConfig {
        var rng = SeededRandomSource(seed: seed)
        return CompanionConfig.make(
            id: id,
            mainCenter: CGPoint(x: 500, y: 200),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            using: &rng,
            tuning: tuning
        )
    }

    // MARK: - Inertial kinematics

    func testKinematicsAcceleratesAndSettlesSoftly() {
        var kinematics = CompanionKinematics(position: CGPoint(x: 0, y: 0), velocity: .zero)
        let target = CGPoint(x: 120, y: 0)
        var speeds: [CGFloat] = []
        var peakIndex = 0
        for i in 0..<300 {
            kinematics.step(toward: target, dt: 1.0 / 60.0, springStrength: 8, damping: 5.5)
            speeds.append(kinematics.speed)
            if speeds[i] > speeds[peakIndex] { peakIndex = i }
        }
        // Acceleration phase then deceleration: peak speed occurs strictly
        // inside the travel (not at the very start), proving inertia.
        XCTAssertGreaterThan(peakIndex, 3)
        XCTAssertLessThan(peakIndex, speeds.count - 5)
        // Soft settle near the target.
        XCTAssertEqual(kinematics.position.x, target.x, accuracy: 1.5)
        XCTAssertLessThan(kinematics.speed, 0.5)
    }

    func testKinematicsIsNotLinearTranslation() {
        var kinematics = CompanionKinematics(position: CGPoint(x: 0, y: 0), velocity: .zero)
        let target = CGPoint(x: 300, y: 0)
        let firstTick: CGFloat
        kinematics.step(toward: target, dt: 1.0 / 60.0, springStrength: 8, damping: 5.5)
        firstTick = kinematics.position.x
        // A linear mover with the same total travel would move much more in
        // the first tick; the spring starts nearly from rest.
        XCTAssertLessThan(firstTick, 2)
        // Middle of the journey is much faster than the start.
        for _ in 0..<40 {
            kinematics.step(toward: target, dt: 1.0 / 60.0, springStrength: 8, damping: 5.5)
        }
        XCTAssertGreaterThan(kinematics.position.x, 80)
    }

    func testKinematicsRemainsFiniteUnderVariedDt() {
        for dt in [1.0 / 60.0, 1.0 / 15.0, 1.0 / 600.0, 0.5] {
            var kinematics = CompanionKinematics(position: .zero, velocity: .zero)
            for _ in 0..<600 {
                kinematics.step(toward: CGPoint(x: 10000, y: 10000), dt: dt, springStrength: 8, damping: 5.5)
                XCTAssertTrue(kinematics.position.x.isFinite)
                XCTAssertTrue(kinematics.position.y.isFinite)
                XCTAssertTrue(kinematics.velocity.dx.isFinite)
                XCTAssertTrue(kinematics.velocity.dy.isFinite)
            }
        }
    }

    func testKinematicsOvershootIsControlled() {
        var kinematics = CompanionKinematics(position: .zero, velocity: .zero)
        let target = CGPoint(x: 100, y: 0)
        var maxX = kinematics.position.x
        for _ in 0..<600 {
            kinematics.step(toward: target, dt: 1.0 / 60.0, springStrength: 8, damping: 3.2)
            maxX = max(maxX, kinematics.position.x)
        }
        // Mild overshoot is allowed but must stay bounded and settle.
        XCTAssertLessThan(maxX, target.x + 30)
        XCTAssertEqual(kinematics.position.x, target.x, accuracy: 1.5)
    }

    // MARK: - Formation slots and spacing

    func testFormationTargetsKeepDistanceFromMainPet() {
        var rng = SeededRandomSource(seed: 7)
        let mainCenter = CGPoint(x: 500, y: 300)
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let offsets = GroupMotionMath.formationOffsets(
            count: 4, mainCenter: mainCenter, visibleFrame: frame, using: &rng, tuning: tuning
        )
        for offset in offsets {
            let distance = hypot(offset.dx, offset.dy)
            XCTAssertGreaterThanOrEqual(
                distance,
                tuning.preferredMainPetRadius - 2,
                "companions must not sit on the main pet"
            )
        }
    }

    func testFormationTargetsMaintainMinimumSpacing() {
        var rng = SeededRandomSource(seed: 8)
        let mainCenter = CGPoint(x: 500, y: 300)
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let offsets = GroupMotionMath.formationOffsets(
            count: 5, mainCenter: mainCenter, visibleFrame: frame, using: &rng, tuning: tuning
        )
        for i in 0..<offsets.count {
            for j in (i + 1)..<offsets.count {
                let a = offsets[i]
                let b = offsets[j]
                let distance = hypot(a.dx - b.dx, a.dy - b.dy)
                XCTAssertGreaterThanOrEqual(
                    distance,
                    tuning.companionMinSpacing - 2,
                    "formation bodies overlap too much"
                )
            }
        }
    }

    func testFormationStaysVisibleNearScreenEdges() {
        var rng = SeededRandomSource(seed: 9)
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let nearLeft = CGPoint(x: 30, y: 120)
        let offsets = GroupMotionMath.formationOffsets(
            count: 4, mainCenter: nearLeft, visibleFrame: frame, using: &rng, tuning: tuning
        )
        for offset in offsets {
            let target = CGPoint(x: nearLeft.x + offset.dx, y: nearLeft.y + offset.dy)
            XCTAssertGreaterThanOrEqual(target.x, frame.minX + tuning.formationMargin - 0.5)
            XCTAssertLessThanOrEqual(target.x, frame.maxX - tuning.formationMargin + 0.5)
            XCTAssertGreaterThanOrEqual(target.y, frame.minY + tuning.formationMargin - 0.5)
            XCTAssertLessThanOrEqual(target.y, frame.maxY - tuning.formationMargin + 0.5)
        }
    }

    func testSeparationAdjustmentPushesOverlappingCompanionsApart() {
        let positions = [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0)]
        let targets = [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0)]
        let adjusted = GroupMotionMath.separationAdjustedTargets(
            positions: positions,
            targets: targets,
            minSpacing: 88,
            strength: 0.5
        )
        let distance = hypot(adjusted[0].x - adjusted[1].x, adjusted[0].y - adjusted[1].y)
        XCTAssertGreaterThan(distance, 40)
    }

    // MARK: - Phase continuity

    func testHoverOffsetIsExactlyZeroAtTransition() {
        let config = makeConfig(seed: 10, id: 0)
        let offset = GroupMotionMath.hoverOffset(
            at: 0,
            rampInDuration: tuning.hoverRampInDuration,
            config: config,
            tuning: tuning
        )
        XCTAssertEqual(offset.dx, 0, accuracy: 0.000001)
        XCTAssertEqual(offset.dy, 0, accuracy: 0.000001)
    }

    func testHoverOffsetStaysBoundedAndRampsIn() {
        let config = makeConfig(seed: 11, id: 1)
        var previousMagnitude: CGFloat = 0
        for i in 0...100 {
            let elapsed = TimeInterval(i) / 100 * 3
            let offset = GroupMotionMath.hoverOffset(
                at: elapsed,
                rampInDuration: tuning.hoverRampInDuration,
                config: config,
                tuning: tuning
            )
            let magnitude = hypot(offset.dx, offset.dy)
            XCTAssertLessThanOrEqual(
                magnitude,
                hypot(tuning.hoverBobAmplitude, tuning.hoverDriftAmplitude) + 0.001
            )
            if elapsed < tuning.hoverRampInDuration / 2 {
                XCTAssertGreaterThanOrEqual(magnitude, previousMagnitude - 0.001)
                previousMagnitude = magnitude
            }
        }
    }

    func testAscentSwayIsExactlyZeroAtTransition() {
        let config = makeConfig(seed: 12, id: 2)
        XCTAssertEqual(
            GroupMotionMath.ascentSway(at: 0, config: config, tuning: tuning),
            0,
            accuracy: 0.000001
        )
        for i in 0...100 {
            let sway = GroupMotionMath.ascentSway(
                at: TimeInterval(i) / 100 * 6, config: config, tuning: tuning
            )
            XCTAssertLessThanOrEqual(abs(sway), tuning.ascentSwayAmplitude + 0.001)
        }
    }

    // MARK: - Fan-out

    func testFanOutProducesDistinctExitTrajectories() {
        var rng = SeededRandomSource(seed: 13)
        let mainCenter = CGPoint(x: 500, y: 200)
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let configs = (0..<4).map {
            CompanionConfig.make(
                id: $0, mainCenter: mainCenter, visibleFrame: frame, using: &rng, tuning: tuning
            )
        }
        let exitXs = configs.map { mainCenter.x + $0.exitTargetOffset.dx }
        let spread = (exitXs.max() ?? 0) - (exitXs.min() ?? 0)
        XCTAssertGreaterThan(spread, 40, "fan-out must spread companions apart")
        XCTAssertGreaterThan(Set(exitXs).count, 2, "exit directions must differ")
        // All exits are upward.
        for config in configs {
            XCTAssertGreaterThan(config.exitTargetOffset.dy, 0)
        }
    }

    func testAscentSpreadIncreasesOverTime() {
        // Two kinematic companions with far-apart targets diverge over
        // time: spread grows monotonically toward the target separation.
        var a = CompanionKinematics(position: CGPoint(x: 0, y: 0), velocity: .zero)
        var b = CompanionKinematics(position: CGPoint(x: 0, y: 0), velocity: .zero)
        let targetA = CGPoint(x: -150, y: 900)
        let targetB = CGPoint(x: 150, y: 900)
        var previousSpread: CGFloat = 0
        for _ in 0..<240 {
            a.step(toward: targetA, dt: 1.0 / 60.0, springStrength: 1.1, damping: 2.1)
            b.step(toward: targetB, dt: 1.0 / 60.0, springStrength: 1.1, damping: 2.1)
            let spread = abs(a.position.x - b.position.x)
            XCTAssertGreaterThanOrEqual(spread, previousSpread - 0.001)
            previousSpread = spread
        }
        XCTAssertGreaterThan(previousSpread, 100)
    }

    // MARK: - Individual exit

    func testExitPredicatesAllowIndividualExit() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertFalse(
            GroupMotionMath.isAboveExitFadeZone(panelTopY: 500, visibleFrame: frame, margin: 60)
        )
        XCTAssertTrue(
            GroupMotionMath.isAboveExitFadeZone(panelTopY: 780, visibleFrame: frame, margin: 60)
        )
        XCTAssertTrue(
            GroupMotionMath.isFullyAboveScreen(panelTopY: 900, visibleFrame: frame, margin: 40)
        )
    }

    func testCompanionPhaseOffsetsProduceDifferentMotion() {
        // Configs are drawn from ONE rng stream, like production.
        var rng = SeededRandomSource(seed: 14)
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let center = CGPoint(x: 500, y: 200)
        let a = CompanionConfig.make(id: 0, mainCenter: center, visibleFrame: frame, using: &rng, tuning: tuning)
        let b = CompanionConfig.make(id: 1, mainCenter: center, visibleFrame: frame, using: &rng, tuning: tuning)
        XCTAssertNotEqual(a.bobPhase, b.bobPhase)
        var allIdentical = true
        for i in 0...100 {
            let elapsed = TimeInterval(i) / 100 * 5
            let offsetA = GroupMotionMath.hoverOffset(
                at: elapsed, rampInDuration: tuning.hoverRampInDuration, config: a, tuning: tuning
            )
            let offsetB = GroupMotionMath.hoverOffset(
                at: elapsed, rampInDuration: tuning.hoverRampInDuration, config: b, tuning: tuning
            )
            if offsetA != offsetB { allIdentical = false }
        }
        XCTAssertFalse(allIdentical, "companions must not move identically")
    }

    // MARK: - Appearance / fade / spawn

    func testSpawnPositionIsClampedIntoVisibleFrame() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let farAway = CGVector(dx: 5000, dy: -5000)
        let near = CGVector(dx: 10, dy: 10)
        let center = CGPoint(x: 500, y: 400)
        let clamped = GroupMotionMath.spawnPosition(
            mainCenter: center, offset: farAway, visibleFrame: frame, margin: 16
        )
        XCTAssertGreaterThanOrEqual(clamped.x, frame.minX + 16)
        XCTAssertLessThanOrEqual(clamped.x, frame.maxX - 16)
        XCTAssertGreaterThanOrEqual(clamped.y, frame.minY + 16)
        XCTAssertLessThanOrEqual(clamped.y, frame.maxY - 16)
        XCTAssertEqual(
            GroupMotionMath.spawnPosition(
                mainCenter: center, offset: near, visibleFrame: frame, margin: 16
            ),
            CGPoint(x: 510, y: 410)
        )
    }

    func testAppearAlphaRampsWithinValidRange() {
        for i in 0...100 {
            let elapsed = TimeInterval(i) / 100 * 3
            let alpha = GroupMotionMath.appearAlpha(at: elapsed, delay: 0.5, duration: 0.6)
            XCTAssertGreaterThanOrEqual(alpha, 0)
            XCTAssertLessThanOrEqual(alpha, 1)
        }
        XCTAssertEqual(GroupMotionMath.appearAlpha(at: 0.4, delay: 0.5, duration: 0.6), 0)
        XCTAssertEqual(GroupMotionMath.appearAlpha(at: 0.5, delay: 0.5, duration: 0.6), 0)
        XCTAssertEqual(GroupMotionMath.appearAlpha(at: 1.1, delay: 0.5, duration: 0.6), 1, accuracy: 0.0001)
    }

    func testFadeAlphaDecreasesMonotonicallyToZero() {
        var previous = CGFloat.greatestFiniteMagnitude
        for i in 0...100 {
            let alpha = GroupMotionMath.fadeAlpha(
                at: TimeInterval(i) / 100 * 0.5, duration: 0.4
            )
            XCTAssertGreaterThanOrEqual(alpha, 0)
            XCTAssertLessThanOrEqual(alpha, 1)
            XCTAssertLessThanOrEqual(alpha, previous + 0.0001)
            previous = alpha
        }
        XCTAssertEqual(GroupMotionMath.fadeAlpha(at: 0, duration: 0.4), 1, accuracy: 0.0001)
        XCTAssertEqual(GroupMotionMath.fadeAlpha(at: 0.4, duration: 0.4), 0, accuracy: 0.0001)
    }

    func testAppearPhaseDurationUsesLastCompanion() {
        var rng = SeededRandomSource(seed: 15)
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let center = CGPoint(x: 500, y: 200)
        let configs = (0..<4).map {
            CompanionConfig.make(id: $0, mainCenter: center, visibleFrame: frame, using: &rng, tuning: tuning)
        }
        let duration = GroupMotionMath.appearPhaseDuration(
            configs: configs, fadeDuration: tuning.appearFadeDuration
        )
        let maxDelay = configs.map(\.appearDelay).max() ?? 0
        XCTAssertEqual(duration, maxDelay + tuning.appearFadeDuration, accuracy: 0.0001)
    }
}
