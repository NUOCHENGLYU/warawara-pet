import XCTest
@testable import WarawaraPet

final class GroupMotionMathTests: XCTestCase {
    private let tuning = GroupTuning.default

    private func makeConfig(seed: UInt64, id: Int) -> CompanionConfig {
        var rng = SeededRandomSource(seed: seed)
        return CompanionConfig.make(id: id, using: &rng, tuning: tuning)
    }

    func testGatherInterpolationStartsAndEnds() {
        let spawn = CGPoint(x: 100, y: 50)
        let gather = CGPoint(x: 300, y: 250)
        let start = GroupMotionMath.gatherPosition(at: 0, from: spawn, to: gather)
        let end = GroupMotionMath.gatherPosition(at: 1, from: spawn, to: gather)
        XCTAssertEqual(start, spawn)
        XCTAssertEqual(end, gather)
    }

    func testGatherInterpolationIsMonotonicAndBounded() {
        let spawn = CGPoint(x: 400, y: 100)
        let gather = CGPoint(x: 40, y: 300)
        var previous = spawn
        for i in 1...100 {
            let point = GroupMotionMath.gatherPosition(
                at: CGFloat(i) / 100, from: spawn, to: gather
            )
            XCTAssertGreaterThanOrEqual(point.x, min(spawn.x, gather.x) - 0.001)
            XCTAssertLessThanOrEqual(point.x, max(spawn.x, gather.x) + 0.001)
            XCTAssertGreaterThanOrEqual(point.y, min(spawn.y, gather.y) - 0.001)
            XCTAssertLessThanOrEqual(point.y, max(spawn.y, gather.y) + 0.001)
            if spawn.x > gather.x {
                XCTAssertLessThanOrEqual(point.x, previous.x + 0.001)
            } else {
                XCTAssertGreaterThanOrEqual(point.x, previous.x)
            }
            if spawn.y > gather.y {
                XCTAssertLessThanOrEqual(point.y, previous.y + 0.001)
            } else {
                XCTAssertGreaterThanOrEqual(point.y, previous.y)
            }
            previous = point
        }
    }

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
            let alpha = GroupMotionMath.appearAlpha(
                at: elapsed, delay: 0.5, duration: 0.6
            )
            XCTAssertGreaterThanOrEqual(alpha, 0)
            XCTAssertLessThanOrEqual(alpha, 1)
        }
        XCTAssertEqual(GroupMotionMath.appearAlpha(at: 0.4, delay: 0.5, duration: 0.6), 0)
        XCTAssertEqual(GroupMotionMath.appearAlpha(at: 0.5, delay: 0.5, duration: 0.6), 0)
        XCTAssertEqual(GroupMotionMath.appearAlpha(at: 1.1, delay: 0.5, duration: 0.6), 1, accuracy: 0.0001)
        XCTAssertEqual(GroupMotionMath.appearAlpha(at: 0.8, delay: 0.5, duration: 0.6), 0.5, accuracy: 0.0001)
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

    func testAscentRisesWithAcceleration() {
        let config = makeConfig(seed: 1, id: 0)
        let at0 = GroupMotionMath.ascentOffset(at: 0, config: config, tuning: tuning)
        let at1 = GroupMotionMath.ascentOffset(at: 1, config: config, tuning: tuning)
        let at2 = GroupMotionMath.ascentOffset(at: 2, config: config, tuning: tuning)
        let at3 = GroupMotionMath.ascentOffset(at: 3, config: config, tuning: tuning)
        XCTAssertGreaterThan(at1.dy, at0.dy)
        XCTAssertGreaterThan(at2.dy, at1.dy)
        XCTAssertGreaterThan(at3.dy, at2.dy)
        // Acceleration: the second interval is faster than the first.
        let firstInterval = at1.dy - at0.dy
        let secondInterval = at2.dy - at1.dy
        XCTAssertGreaterThan(secondInterval, firstInterval)
        // Wander stays bounded.
        XCTAssertLessThanOrEqual(abs(at2.dx), tuning.ascentWanderAmplitude + 0.001)
    }

    func testHoverOffsetsStayWithinAmplitudes() {
        let config = makeConfig(seed: 2, id: 1)
        for i in 0...100 {
            let elapsed = TimeInterval(i) / 100 * 10
            let offset = GroupMotionMath.hoverOffset(at: elapsed, config: config, tuning: tuning)
            XCTAssertLessThanOrEqual(abs(offset.dy), tuning.hoverBobAmplitude + 0.001)
            XCTAssertLessThanOrEqual(abs(offset.dx), tuning.hoverDriftAmplitude + 0.001)
        }
    }

    func testCompanionPhaseOffsetsProduceDifferentMotion() {
        // Configs are drawn from ONE rng stream, like production.
        var rng = SeededRandomSource(seed: 3)
        let a = CompanionConfig.make(id: 0, using: &rng, tuning: tuning)
        let b = CompanionConfig.make(id: 1, using: &rng, tuning: tuning)
        XCTAssertNotEqual(a.bobPhase, b.bobPhase)
        var allIdentical = true
        for i in 0...100 {
            let elapsed = TimeInterval(i) / 100 * 5
            let offsetA = GroupMotionMath.hoverOffset(at: elapsed, config: a, tuning: tuning)
            let offsetB = GroupMotionMath.hoverOffset(at: elapsed, config: b, tuning: tuning)
            if offsetA != offsetB { allIdentical = false }
        }
        XCTAssertFalse(allIdentical, "companions must not move identically")
    }

    func testAppearPhaseDurationUsesLastCompanion() {
        var rng = SeededRandomSource(seed: 5)
        let configs = (0..<4).map { CompanionConfig.make(id: $0, using: &rng, tuning: tuning) }
        let duration = GroupMotionMath.appearPhaseDuration(
            configs: configs, fadeDuration: tuning.appearFadeDuration
        )
        let maxDelay = configs.map(\.appearDelay).max() ?? 0
        XCTAssertEqual(duration, maxDelay + tuning.appearFadeDuration, accuracy: 0.0001)
    }
}
