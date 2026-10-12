import XCTest
@testable import WarawaraPet

final class GroupMotionMathTests: XCTestCase {
    private let tuning = GroupTuning.default
    private let physicalFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let visibleFrame = CGRect(x: 0, y: 60, width: 1000, height: 740)
    private let mainCenter = CGPoint(x: 500, y: 200)

    private func makeConfig(seed: UInt64, id: Int) -> CompanionConfig {
        var rng = SeededRandomSource(seed: seed)
        return CompanionConfig.make(
            id: id,
            mainCenter: mainCenter,
            physicalFrame: physicalFrame,
            visibleFrame: visibleFrame,
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
        XCTAssertGreaterThan(peakIndex, 3)
        XCTAssertLessThan(peakIndex, speeds.count - 5)
        XCTAssertEqual(kinematics.position.x, target.x, accuracy: 1.5)
        XCTAssertLessThan(kinematics.speed, 0.5)
    }

    func testKinematicsIsNotLinearTranslation() {
        var kinematics = CompanionKinematics(position: CGPoint(x: 0, y: 0), velocity: .zero)
        let target = CGPoint(x: 300, y: 0)
        kinematics.step(toward: target, dt: 1.0 / 60.0, springStrength: 8, damping: 5.5)
        XCTAssertLessThan(kinematics.position.x, 2)
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
        XCTAssertLessThan(maxX, target.x + 30)
        XCTAssertEqual(kinematics.position.x, target.x, accuracy: 1.5)
    }

    // MARK: - Entry from outside the physical screen

    func testEntryPositionsAreFullyOutsidePhysicalFrame() {
        for edge in [0, 1, 2] {
            var rng = SeededRandomSource(seed: 30)
            for _ in 0..<20 {
                let position = GroupMotionMath.entryPosition(
                    edge: edge,
                    mainCenter: mainCenter,
                    physicalFrame: physicalFrame,
                    panelSize: CompanionMetrics.size,
                    using: &rng,
                    tuning: tuning
                )
                XCTAssertTrue(
                    GroupMotionMath.isOutside(position, frame: physicalFrame),
                    "edge \(edge) entry must start outside the physical screen"
                )
            }
        }
    }

    func testEntryEdgesAreScreenAware() {
        var rng = SeededRandomSource(seed: 31)
        let nearLeft = CGPoint(x: 40, y: 200)
        for index in 0..<20 {
            let edge = GroupMotionMath.entryEdge(
                index: index, count: 4, mainCenter: nearLeft,
                physicalFrame: physicalFrame, using: &rng, tuning: tuning
            )
            XCTAssertNotEqual(edge, 0, "companions near the left edge must not enter from the left")
        }
        var rng2 = SeededRandomSource(seed: 32)
        let nearRight = CGPoint(x: 960, y: 200)
        for index in 0..<20 {
            let edge = GroupMotionMath.entryEdge(
                index: index, count: 4, mainCenter: nearRight,
                physicalFrame: physicalFrame, using: &rng2, tuning: tuning
            )
            XCTAssertNotEqual(edge, 1, "companions near the right edge must not enter from the right")
        }
    }

    func testEntryMotionCrossesBoundaryContinuously() {
        // A companion starting outside (left) springs toward an inside
        // target: it must cross the boundary in small steps (no teleport).
        var kinematics = CompanionKinematics(
            position: CGPoint(x: -80, y: 200),
            velocity: .zero
        )
        let target = CGPoint(x: 420, y: 200)
        var sawInside = false
        var previous = kinematics.position
        for _ in 0..<300 {
            kinematics.step(toward: target, dt: 1.0 / 60.0, springStrength: 8, damping: 5.5)
            let step = kinematics.distance(to: previous)
            XCTAssertLessThan(step, 30, "entry motion must be continuous")
            previous = kinematics.position
            if !GroupMotionMath.isOutside(kinematics.position, frame: physicalFrame) {
                sawInside = true
            }
        }
        XCTAssertTrue(sawInside, "entry must cross into the screen")
        XCTAssertEqual(kinematics.position.x, target.x, accuracy: 1.5)
    }

    // MARK: - Formation slots and spacing

    func testFormationTargetsKeepDistanceFromMainPet() {
        var rng = SeededRandomSource(seed: 7)
        let offsets = GroupMotionMath.formationOffsets(
            count: 4, mainCenter: mainCenter, visibleFrame: visibleFrame, using: &rng, tuning: tuning
        )
        for offset in offsets {
            let distance = hypot(offset.dx, offset.dy)
            XCTAssertGreaterThanOrEqual(distance, tuning.preferredMainPetRadius - 2)
        }
    }

    func testFormationTargetsMaintainMinimumSpacing() {
        var rng = SeededRandomSource(seed: 8)
        let offsets = GroupMotionMath.formationOffsets(
            count: 5, mainCenter: mainCenter, visibleFrame: visibleFrame, using: &rng, tuning: tuning
        )
        for i in 0..<offsets.count {
            for j in (i + 1)..<offsets.count {
                let a = offsets[i]
                let b = offsets[j]
                let distance = hypot(a.dx - b.dx, a.dy - b.dy)
                XCTAssertGreaterThanOrEqual(distance, tuning.companionMinSpacing - 2)
            }
        }
    }

    func testFormationStaysVisibleNearScreenEdges() {
        var rng = SeededRandomSource(seed: 9)
        let nearLeft = CGPoint(x: 30, y: 120)
        let offsets = GroupMotionMath.formationOffsets(
            count: 4, mainCenter: nearLeft, visibleFrame: visibleFrame, using: &rng, tuning: tuning
        )
        for offset in offsets {
            let target = CGPoint(x: nearLeft.x + offset.dx, y: nearLeft.y + offset.dy)
            XCTAssertGreaterThanOrEqual(target.x, visibleFrame.minX + tuning.formationMargin - 0.5)
            XCTAssertLessThanOrEqual(target.x, visibleFrame.maxX - tuning.formationMargin + 0.5)
            XCTAssertGreaterThanOrEqual(target.y, visibleFrame.minY + tuning.formationMargin - 0.5)
            XCTAssertLessThanOrEqual(target.y, visibleFrame.maxY - tuning.formationMargin + 0.5)
        }
    }

    func testSeparationAdjustmentPushesOverlappingCompanionsApart() {
        let positions = [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0)]
        let targets = [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0)]
        let adjusted = GroupMotionMath.separationAdjustedTargets(
            positions: positions, targets: targets, minSpacing: 88, strength: 0.5
        )
        let distance = hypot(adjusted[0].x - adjusted[1].x, adjusted[0].y - adjusted[1].y)
        XCTAssertGreaterThan(distance, 40)
    }

    // MARK: - Phase continuity

    func testHoverOffsetIsExactlyZeroAtTransition() {
        let config = makeConfig(seed: 10, id: 0)
        let offset = GroupMotionMath.hoverOffset(
            at: 0, rampInDuration: tuning.hoverRampInDuration, config: config, tuning: tuning
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
                at: elapsed, rampInDuration: tuning.hoverRampInDuration, config: config, tuning: tuning
            )
            let magnitude = hypot(offset.dx, offset.dy)
            XCTAssertLessThanOrEqual(
                magnitude, hypot(tuning.hoverBobAmplitude, tuning.hoverDriftAmplitude) + 0.001
            )
            if elapsed < tuning.hoverRampInDuration / 2 {
                XCTAssertGreaterThanOrEqual(magnitude, previousMagnitude - 0.001)
                previousMagnitude = magnitude
            }
        }
    }

    func testAscentSwayIsExactlyZeroAtTransition() {
        let config = makeConfig(seed: 12, id: 2)
        XCTAssertEqual(GroupMotionMath.ascentSway(at: 0, config: config, tuning: tuning), 0, accuracy: 0.000001)
        for i in 0...100 {
            let sway = GroupMotionMath.ascentSway(
                at: TimeInterval(i) / 100 * 6, config: config, tuning: tuning
            )
            XCTAssertLessThanOrEqual(abs(sway), tuning.ascentSwayAmplitude + 0.001)
        }
    }

    // MARK: - Fan-out and spatial exit

    func testFanOutProducesDistinctExitTrajectories() {
        var rng = SeededRandomSource(seed: 13)
        let configs = (0..<4).map {
            CompanionConfig.make(
                id: $0, mainCenter: mainCenter,
                physicalFrame: physicalFrame, visibleFrame: visibleFrame,
                using: &rng, tuning: tuning
            )
        }
        let exitXs = configs.map { mainCenter.x + $0.exitTargetOffset.dx }
        let spread = (exitXs.max() ?? 0) - (exitXs.min() ?? 0)
        XCTAssertGreaterThan(spread, 40)
        XCTAssertGreaterThan(Set(exitXs).count, 2)
        for config in configs {
            XCTAssertGreaterThan(config.exitTargetOffset.dy, 0)
        }
    }

    func testAscentSpreadIncreasesOverTime() {
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

    func testSpatialExitRequiresEntireBodyBeyondVisibleTopEdge() {
        let panelSize = CompanionMetrics.size
        let topY: CGFloat = 740  // visibleFrame.maxY of the test layout
        let onScreen = CGRect(x: 300, y: 600, width: panelSize, height: panelSize)
        XCTAssertFalse(
            GroupMotionMath.isFullyAboveTopEdge(
                panelFrame: onScreen, topY: topY, margin: tuning.exitTopMargin
            )
        )
        // Body crossing: still partially visible -> not recyclable.
        let crossing = CGRect(x: 300, y: 700, width: panelSize, height: panelSize)
        XCTAssertFalse(
            GroupMotionMath.isFullyAboveTopEdge(
                panelFrame: crossing, topY: topY, margin: tuning.exitTopMargin
            )
        )
        XCTAssertGreaterThan(
            GroupMotionMath.fractionAboveTopEdge(panelFrame: crossing, topY: topY), 0
        )
        XCTAssertLessThan(
            GroupMotionMath.fractionAboveTopEdge(panelFrame: crossing, topY: topY), 1
        )
        let gone = CGRect(x: 300, y: 900, width: panelSize, height: panelSize)
        XCTAssertTrue(
            GroupMotionMath.isFullyAboveTopEdge(
                panelFrame: gone, topY: topY, margin: tuning.exitTopMargin
            )
        )
        XCTAssertEqual(
            GroupMotionMath.fractionAboveTopEdge(panelFrame: gone, topY: topY),
            1,
            accuracy: 0.0001
        )
    }

    func testExitCompletionUsesVisibleTopNotPhysicalTop() {
        // A body fully past the VISIBLE top but still inside the menu-bar
        // band is invisible to the user and may be recycled.
        let panelSize = CompanionMetrics.size
        let topY: CGFloat = 740
        let inMenuBarBand = CGRect(x: 300, y: 780, width: panelSize, height: panelSize)
        XCTAssertTrue(
            GroupMotionMath.isFullyAboveTopEdge(
                panelFrame: inMenuBarBand, topY: topY, margin: tuning.exitTopMargin
            )
        )
    }

    func testExitSlowZonePredicate() {
        let topY: CGFloat = 740
        XCTAssertFalse(
            GroupMotionMath.isInExitSlowZone(bodyTopY: 500, topY: topY, zoneHeight: 120)
        )
        XCTAssertTrue(
            GroupMotionMath.isInExitSlowZone(bodyTopY: 660, topY: topY, zoneHeight: 120)
        )
        XCTAssertTrue(
            GroupMotionMath.isInExitSlowZone(bodyTopY: 810, topY: topY, zoneHeight: 120)
        )
    }

    func testStagedTopEdgeCrossingShowsPartialVisibility() {
        // Simulate the slow exit zone: the body rises at a constant slow
        // speed and must pass through a stage where only part of it is
        // visible before being parked.
        let topY: CGFloat = 740
        let panelSize = CompanionMetrics.size
        let slowSpeed: CGFloat = 40
        var centerY: CGFloat = 640
        var sawFullyVisible = false
        var sawPartiallyVisible = false
        var exited = false
        for _ in 0..<600 {
            centerY += slowSpeed / 60
            let panel = CGRect(
                x: 300,
                y: centerY - panelSize / 2,
                width: panelSize,
                height: panelSize
            )
            let fraction = GroupMotionMath.fractionAboveTopEdge(panelFrame: panel, topY: topY)
            if fraction <= 0 {
                sawFullyVisible = true
            }
            if fraction > 0 && fraction < 1 {
                sawPartiallyVisible = true
            }
            if GroupMotionMath.isFullyAboveTopEdge(
                panelFrame: panel, topY: topY, margin: 8
            ) {
                exited = true
                break
            }
        }
        XCTAssertTrue(sawFullyVisible)
        XCTAssertTrue(sawPartiallyVisible, "body must be partially visible while crossing the top edge")
        XCTAssertTrue(exited, "companion must exit after the slow staged crossing")
    }

    func testCompanionPhaseOffsetsProduceDifferentMotion() {
        var rng = SeededRandomSource(seed: 14)
        let a = CompanionConfig.make(
            id: 0, mainCenter: mainCenter, physicalFrame: physicalFrame,
            visibleFrame: visibleFrame, using: &rng, tuning: tuning
        )
        let b = CompanionConfig.make(
            id: 1, mainCenter: mainCenter, physicalFrame: physicalFrame,
            visibleFrame: visibleFrame, using: &rng, tuning: tuning
        )
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

    // MARK: - Cancellation fade

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

    func testReleasePhaseDurationUsesLastCompanion() {
        var rng = SeededRandomSource(seed: 15)
        let configs = (0..<4).map {
            CompanionConfig.make(
                id: $0, mainCenter: mainCenter, physicalFrame: physicalFrame,
                visibleFrame: visibleFrame, using: &rng, tuning: tuning
            )
        }
        let duration = GroupMotionMath.releasePhaseDuration(configs: configs)
        let maxDelay = configs.map(\.releaseDelay).max() ?? 0
        XCTAssertEqual(duration, maxDelay, accuracy: 0.0001)
    }
}
