import XCTest
@testable import WarawaraPet

final class CuriosityPoseTests: XCTestCase {
    private var tuning: PersonalityTuning {
        var t = PersonalityTuning.default
        t.curiosityMaxRotation = 0.08
        t.curiosityMaxStretch = 0.05
        return t
    }

    func testDeadbandZeroesTinyDirections() {
        XCTAssertEqual(
            CuriosityPoseMath.deadbanded(CGVector(dx: 0.01, dy: 0), threshold: 0.02),
            .zero
        )
        XCTAssertEqual(
            CuriosityPoseMath.deadbanded(CGVector(dx: -0.015, dy: 0.01), threshold: 0.02),
            .zero
        )
        let kept = CuriosityPoseMath.deadbanded(CGVector(dx: 0.5, dy: 0), threshold: 0.02)
        XCTAssertEqual(kept.dx, 0.5, accuracy: 0.001)
        XCTAssertEqual(kept.dy, 0, accuracy: 0.001)
    }

    func testNeutralWhenNoDwellProgress() {
        let pose = CuriosityPoseMath.pose(
            direction: CGVector(dx: 1, dy: 0),
            dwellProgress: 0,
            tuning: tuning
        )
        XCTAssertEqual(pose, .neutral)
    }

    func testRightDirectionStretchesRightAndLeansTowardCursor() {
        let pose = CuriosityPoseMath.pose(
            direction: CGVector(dx: 1, dy: 0),
            dwellProgress: 1,
            tuning: tuning
        )
        XCTAssertEqual(pose.stretchAngle, 0, accuracy: 0.0001)
        XCTAssertEqual(pose.stretchScale, 1.05, accuracy: 0.0001)
        XCTAssertEqual(pose.perpendicularScale, 1 / 1.05, accuracy: 0.0001)
        XCTAssertEqual(pose.rotation, -0.08, accuracy: 0.0001)
    }

    func testLeftDirectionLeansOpposite() {
        let pose = CuriosityPoseMath.pose(
            direction: CGVector(dx: -1, dy: 0),
            dwellProgress: 1,
            tuning: tuning
        )
        XCTAssertEqual(pose.rotation, 0.08, accuracy: 0.0001)
    }

    func testUpDirectionHasNoRotationAndVerticalStretch() {
        let pose = CuriosityPoseMath.pose(
            direction: CGVector(dx: 0, dy: 1),
            dwellProgress: 1,
            tuning: tuning
        )
        XCTAssertEqual(pose.rotation, 0, accuracy: 0.0001)
        XCTAssertEqual(pose.stretchAngle, .pi / 2, accuracy: 0.0001)
    }

    func testRotationIsClampedForLargeMagnitudes() {        let pose = CuriosityPoseMath.pose(
            direction: CGVector(dx: 3, dy: 0),
            dwellProgress: 1,
            tuning: tuning
        )
        XCTAssertEqual(pose.rotation, -0.08, accuracy: 0.0001)
        XCTAssertEqual(pose.stretchScale, 1.05, accuracy: 0.0001)
    }

    func testVolumeIsPreserved() {
        let pose = CuriosityPoseMath.pose(
            direction: CGVector(dx: 0.6, dy: 0.8),
            dwellProgress: 1,
            tuning: tuning
        )
        XCTAssertEqual(pose.stretchScale * pose.perpendicularScale, 1, accuracy: 0.0001)
    }

    func testEstimatorSmoothsDirectionGradually() {
        var estimator = CuriosityPoseEstimator(tuning: tuning)
        estimator.update(direction: CGVector(dx: 1, dy: 0), dwellProgress: 1, at: 0)
        XCTAssertEqual(estimator.pose, .neutral)  // first update is a baseline

        estimator.update(direction: CGVector(dx: 1, dy: 0), dwellProgress: 1, at: 0.15)
        XCTAssertGreaterThan(abs(estimator.pose.rotation), 0)
        XCTAssertLessThan(abs(estimator.pose.rotation), 0.08)

        var t: TimeInterval = 0.15
        for _ in 0..<30 {
            t += 0.15
            estimator.update(direction: CGVector(dx: 1, dy: 0), dwellProgress: 1, at: t)
        }
        XCTAssertEqual(estimator.pose.rotation, -0.08, accuracy: 0.002)
    }

    func testEstimatorResetReturnsNeutral() {
        var estimator = CuriosityPoseEstimator(tuning: tuning)
        var t: TimeInterval = 0
        for _ in 0..<20 {
            t += 0.15
            estimator.update(direction: CGVector(dx: -1, dy: 0), dwellProgress: 1, at: t)
        }
        XCTAssertGreaterThan(abs(estimator.pose.rotation), 0.05)

        estimator.reset()
        XCTAssertEqual(estimator.pose, .neutral)
    }

    func testAbruptReversalDoesNotSnap() {
        var estimator = CuriosityPoseEstimator(tuning: tuning)
        var t: TimeInterval = 0
        for _ in 0..<40 {
            t += 0.033
            estimator.update(direction: CGVector(dx: 1, dy: 0), dwellProgress: 1, at: t)
        }
        XCTAssertEqual(estimator.pose.rotation, -0.08, accuracy: 0.005)

        var smallestMagnitude = abs(estimator.pose.rotation)
        for _ in 0..<40 {
            t += 0.033
            estimator.update(direction: CGVector(dx: -1, dy: 0), dwellProgress: 1, at: t)
            smallestMagnitude = min(smallestMagnitude, abs(estimator.pose.rotation))
            XCTAssertLessThanOrEqual(abs(estimator.pose.rotation), 0.08 + 0.0001)
        }
        // The pose passed continuously through (near) neutral: no discrete jump.
        XCTAssertLessThan(smallestMagnitude, 0.01)
        XCTAssertEqual(estimator.pose.rotation, 0.08, accuracy: 0.005)
    }

    func testLongGapDoesNotProduceSpikes() {
        var estimator = CuriosityPoseEstimator(tuning: tuning)
        estimator.update(direction: CGVector(dx: 1, dy: 0), dwellProgress: 1, at: 0)
        estimator.update(direction: CGVector(dx: 1, dy: 0), dwellProgress: 1, at: 0.033)
        // 5 s gap: the direction re-anchors but every pose value stays clamped.
        estimator.update(direction: CGVector(dx: 0, dy: 1), dwellProgress: 1, at: 5.033)
        XCTAssertLessThanOrEqual(abs(estimator.pose.rotation), 0.08 + 0.0001)
        XCTAssertLessThanOrEqual(estimator.pose.stretchScale, 1.05 + 0.0001)
    }

    func testTracksMovingTargetContinuously() {
        var estimator = CuriosityPoseEstimator(tuning: tuning)
        var t: TimeInterval = 0
        for k in 0...20 {
            t += 0.033
            let angle = CGFloat(Double(k) / 20) * .pi
            estimator.update(
                direction: CGVector(dx: cos(angle), dy: sin(angle)),
                dwellProgress: 1,
                at: t
            )
            XCTAssertLessThanOrEqual(abs(estimator.pose.rotation), 0.08 + 0.0001)
        }
        // The target ended on the left; after the smoothing time constant
        // elapses the pose converges toward the left lean (positive).
        for _ in 0..<40 {
            t += 0.033
            estimator.update(direction: CGVector(dx: -1, dy: 0), dwellProgress: 1, at: t)
        }
        XCTAssertGreaterThan(estimator.pose.rotation, 0.05)
    }
}
