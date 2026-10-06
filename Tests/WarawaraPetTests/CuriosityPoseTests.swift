import XCTest
@testable import WarawaraPet

final class CuriosityPoseTests: XCTestCase {
    private var tuning: PersonalityTuning {
        var t = PersonalityTuning.default
        t.curiosityMaxRotation = 0.08
        t.curiosityMaxStretch = 0.05
        return t
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

    func testRotationIsClampedForLargeMagnitudes() {
        let pose = CuriosityPoseMath.pose(
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
}
