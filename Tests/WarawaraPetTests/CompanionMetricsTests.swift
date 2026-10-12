import XCTest
@testable import WarawaraPet

final class CompanionMetricsTests: XCTestCase {
    func testPanelSizeContainsMaximumSilhouette() {
        let scaledHeight = CompanionMetrics.blobHeight
            * CompanionMetrics.maxScale * (1 + CompanionMetrics.maxStretch)
        let scaledWidth = CompanionMetrics.blobWidth
            * CompanionMetrics.maxScale * (1 + CompanionMetrics.maxStretch)
        let leanExtra = scaledHeight * sin(CompanionMetrics.maxLeanRadians) * 0.5

        XCTAssertLessThanOrEqual(
            scaledHeight + leanExtra,
            CompanionMetrics.size - 2 * CompanionMetrics.padding,
            "vertical silhouette must fit inside the canvas"
        )
        XCTAssertLessThanOrEqual(
            scaledWidth + leanExtra,
            CompanionMetrics.size - 2 * CompanionMetrics.padding,
            "horizontal silhouette must fit inside the canvas"
        )
    }

    func testPanelSizeIsEvenAndPositive() {
        XCTAssertGreaterThan(CompanionMetrics.size, 0)
        XCTAssertEqual(CompanionMetrics.size.truncatingRemainder(dividingBy: 2), 0)
    }

    func testBodyFrameIsPanelInsetByPadding() {
        let panel = CGRect(x: 100, y: 200, width: CompanionMetrics.size, height: CompanionMetrics.size)
        let body = CompanionMetrics.bodyFrame(panelFrame: panel)
        XCTAssertEqual(
            body,
            panel.insetBy(dx: CompanionMetrics.padding, dy: CompanionMetrics.padding)
        )
    }
}

final class CompanionPoseEstimatorTests: XCTestCase {
    private let tuning = GroupTuning.default

    func testZeroVelocityYieldsNeutralPose() {
        var estimator = CompanionPoseEstimator(tuning: tuning)
        estimator.update(velocity: .zero, at: 1)
        estimator.update(velocity: .zero, at: 1.1)
        XCTAssertEqual(estimator.pose.stretchScale, 1, accuracy: 0.0001)
        XCTAssertEqual(estimator.pose.rotation, 0, accuracy: 0.0001)
    }

    func testSustainedVelocityStretchesAlongDirection() {
        var estimator = CompanionPoseEstimator(tuning: tuning)
        var t: TimeInterval = 0
        for _ in 0..<60 {
            t += 0.033
            estimator.update(velocity: CGVector(dx: 300, dy: 0), at: t)
        }
        XCTAssertEqual(estimator.pose.stretchAngle, 0, accuracy: 0.001)
        XCTAssertEqual(estimator.pose.stretchScale, 1 + tuning.poseMaxStretch, accuracy: 0.01)
        XCTAssertEqual(
            estimator.pose.stretchScale * estimator.pose.perpendicularScale,
            1,
            accuracy: 0.0001
        )
    }

    func testDeformationIsWeakerThanMainPetDragMaximum() {
        XCTAssertLessThanOrEqual(
            tuning.poseMaxStretch,
            DeformationTuning.default.maxStretch,
            "companion deformation must stay below the main pet's drag maximum"
        )
    }

    func testLeanSignFlipsWithDirectionAndStaysBounded() {
        var right = CompanionPoseEstimator(tuning: tuning)
        var left = CompanionPoseEstimator(tuning: tuning)
        var t: TimeInterval = 0
        for _ in 0..<60 {
            t += 0.033
            right.update(velocity: CGVector(dx: 300, dy: 0), at: t)
            left.update(velocity: CGVector(dx: -300, dy: 0), at: t)
        }
        XCTAssertLessThan(right.pose.rotation, -0.03)
        XCTAssertGreaterThan(left.pose.rotation, 0.03)
        XCTAssertLessThanOrEqual(abs(left.pose.rotation), tuning.poseMaxLean + 0.001)
        XCTAssertLessThanOrEqual(abs(right.pose.rotation), tuning.poseMaxLean + 0.001)
    }

    func testReversalPassesNearNeutralContinuously() {
        var estimator = CompanionPoseEstimator(tuning: tuning)
        var t: TimeInterval = 0
        for _ in 0..<60 {
            t += 0.033
            estimator.update(velocity: CGVector(dx: 300, dy: 0), at: t)
        }
        XCTAssertGreaterThan(estimator.pose.stretchScale, 1.1)
        var smallestStretch = estimator.pose.stretchScale
        for _ in 0..<60 {
            t += 0.033
            estimator.update(velocity: CGVector(dx: -300, dy: 0), at: t)
            smallestStretch = min(smallestStretch, estimator.pose.stretchScale)
        }
        XCTAssertLessThan(smallestStretch, 1.03, "reversal must pass through neutral smoothly")
    }

    func testLongGapDecaysInsteadOfSpiking() {
        var estimator = CompanionPoseEstimator(tuning: tuning)
        var t: TimeInterval = 0
        for _ in 0..<60 {
            t += 0.033
            estimator.update(velocity: CGVector(dx: 300, dy: 0), at: t)
        }
        XCTAssertGreaterThan(estimator.pose.stretchScale, 1.1)
        t += 5
        estimator.update(velocity: CGVector(dx: 300, dy: 0), at: t)
        XCTAssertEqual(estimator.pose.stretchScale, 1, accuracy: 0.001)
        XCTAssertEqual(estimator.pose.rotation, 0, accuracy: 0.001)
    }

    func testResetReturnsNeutral() {
        var estimator = CompanionPoseEstimator(tuning: tuning)
        var t: TimeInterval = 0
        for _ in 0..<60 {
            t += 0.033
            estimator.update(velocity: CGVector(dx: 300, dy: 0), at: t)
        }
        XCTAssertGreaterThan(estimator.pose.stretchScale, 1.1)
        estimator.reset()
        XCTAssertEqual(estimator.pose, .neutral)
    }

    func testBreathingScaleStaysNearOne() {
        let config = makeConfig(seed: 60, id: 0)
        for i in 0...100 {
            let elapsed = TimeInterval(i) / 100 * 10
            let scale = CompanionPoseEstimator.breathingScale(
                at: elapsed, config: config, tuning: tuning
            )
            XCTAssertGreaterThanOrEqual(scale, 0.98 - 0.001)
            XCTAssertLessThanOrEqual(scale, 1.02 + 0.001)
        }
    }

    private func makeConfig(seed: UInt64, id: Int) -> CompanionConfig {
        var rng = SeededRandomSource(seed: seed)
        return CompanionConfig.make(
            id: id,
            mainCenter: CGPoint(x: 500, y: 200),
            physicalFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            visibleFrame: CGRect(x: 0, y: 60, width: 1000, height: 740),
            using: &rng,
            tuning: tuning
        )
    }
}
