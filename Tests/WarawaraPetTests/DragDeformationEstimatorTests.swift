import XCTest
@testable import WarawaraPet

final class DragDeformationEstimatorTests: XCTestCase {
    private let tuning = DeformationTuning.default

    private func dragRight(_ estimator: inout DragDeformationEstimator, samples: Int, speed: CGFloat = 600) {
        var t: TimeInterval = 0
        for _ in 0..<samples {
            t += 0.016
            estimator.update(deltaX: speed * 0.016, deltaY: 0, at: t)
        }
    }

    func testFirstUpdateOnlyRecordsTimestamp() {
        var estimator = DragDeformationEstimator()
        estimator.beginDrag(grabVector: CGVector(dx: 0, dy: 1))
        estimator.update(deltaX: 100, deltaY: 0, at: 3)
        XCTAssertEqual(estimator.deformation.stretchScale, 1, accuracy: 0.0001)
        XCTAssertEqual(estimator.deformation.rotation, 0, accuracy: 0.0001)
    }

    func testZeroDtIsIgnored() {
        var estimator = DragDeformationEstimator()
        estimator.beginDrag(grabVector: CGVector(dx: 0, dy: 1))
        estimator.update(deltaX: 10, deltaY: 0, at: 5)
        estimator.update(deltaX: 10, deltaY: 0, at: 5)
        XCTAssertEqual(estimator.deformation.stretchScale, 1, accuracy: 0.0001)
    }

    func testConstantVelocityApproachesSteadyStateMonotonically() {
        var estimator = DragDeformationEstimator()
        estimator.beginDrag(grabVector: CGVector(dx: 0, dy: 1))
        var previousStretch = estimator.deformation.stretchScale
        var previousRotationMagnitude = abs(estimator.deformation.rotation)
        var t: TimeInterval = 0
        for _ in 0..<60 {
            t += 0.016
            estimator.update(deltaX: 9.6, deltaY: 0, at: t)
            XCTAssertGreaterThanOrEqual(estimator.deformation.stretchScale, previousStretch)
            XCTAssertGreaterThanOrEqual(
                abs(estimator.deformation.rotation), previousRotationMagnitude
            )
            previousStretch = estimator.deformation.stretchScale
            previousRotationMagnitude = abs(estimator.deformation.rotation)
        }
        XCTAssertEqual(estimator.deformation.stretchScale, 1 + tuning.maxStretch, accuracy: 0.01)
        XCTAssertEqual(estimator.deformation.rotation, -tuning.maxRotation, accuracy: 0.01)
    }

    func testSlowDragDeformsLittleFastDragSaturates() {
        var slow = DragDeformationEstimator()
        slow.beginDrag(grabVector: .zero)
        dragRight(&slow, samples: 60, speed: 100)
        XCTAssertLessThan(slow.deformation.stretchScale, 1.1)

        var fast = DragDeformationEstimator()
        fast.beginDrag(grabVector: .zero)
        dragRight(&fast, samples: 60, speed: 800)
        XCTAssertEqual(fast.deformation.stretchScale, 1 + tuning.maxStretch, accuracy: 0.01)
    }

    func testDirectionReversalPassesNearNeutralContinuously() {
        var estimator = DragDeformationEstimator()
        estimator.beginDrag(grabVector: CGVector(dx: 0, dy: 1))
        dragRight(&estimator, samples: 60, speed: 600)
        XCTAssertGreaterThan(estimator.deformation.stretchScale, 1.3)

        var smallestStretch = estimator.deformation.stretchScale
        var smallestRotation = abs(estimator.deformation.rotation)
        var t: TimeInterval = 60 * 0.016
        for _ in 0..<60 {
            t += 0.016
            estimator.update(deltaX: -9.6, deltaY: 0, at: t)
            smallestStretch = min(smallestStretch, estimator.deformation.stretchScale)
            smallestRotation = min(smallestRotation, abs(estimator.deformation.rotation))
        }
        XCTAssertLessThan(smallestStretch, 1.05)
        XCTAssertLessThan(smallestRotation, 0.01)
        // Now dragging left with the grab above center: torque flips sign.
        XCTAssertGreaterThan(estimator.deformation.rotation, 0)
    }

    func testLongGapDecaysTowardNeutralInsteadOfSpikingOrFreezing() {
        var estimator = DragDeformationEstimator()
        estimator.beginDrag(grabVector: CGVector(dx: 0, dy: 1))
        dragRight(&estimator, samples: 60, speed: 600)
        XCTAssertGreaterThan(estimator.deformation.stretchScale, 1.3)

        var t: TimeInterval = 60 * 0.016
        t += 5
        estimator.update(deltaX: 500, deltaY: 0, at: t)
        XCTAssertEqual(estimator.deformation.stretchScale, 1, accuracy: 0.001)
        XCTAssertEqual(estimator.deformation.rotation, 0, accuracy: 0.001)
    }

    func testSingleSpikeSampleDoesNotProduceFullDeformation() {
        // Rotation/stretch derive from the SMOOTHED velocity, so a single
        // high-speed sample must lag well behind its raw value.
        var estimator = DragDeformationEstimator()
        estimator.beginDrag(grabVector: CGVector(dx: 0, dy: 1))
        estimator.update(deltaX: 9.6, deltaY: 0, at: 0)
        estimator.update(deltaX: 19.2, deltaY: 0, at: 0.016)  // raw 1200 pt/s spike
        XCTAssertLessThan(abs(estimator.deformation.rotation), tuning.maxRotation)
        XCTAssertLessThan(estimator.deformation.stretchScale, 1 + tuning.maxStretch)
    }

    func testGrabVectorDrivesRotationSign() {
        var rightUp = DragDeformationEstimator()
        rightUp.beginDrag(grabVector: CGVector(dx: 0, dy: 1))
        dragRight(&rightUp, samples: 60, speed: 100)
        XCTAssertLessThan(rightUp.deformation.rotation, 0)

        var rightDown = DragDeformationEstimator()
        rightDown.beginDrag(grabVector: CGVector(dx: 0, dy: -1))
        dragRight(&rightDown, samples: 60, speed: 100)
        XCTAssertGreaterThan(rightDown.deformation.rotation, 0)
        XCTAssertEqual(
            rightUp.deformation.rotation,
            -rightDown.deformation.rotation,
            accuracy: 0.003
        )
    }

    func testGrabAnchorIsClampedToInteriorInDeformationOutput() {
        var estimator = DragDeformationEstimator()
        estimator.beginDrag(grabVector: CGVector(dx: 0, dy: 5))
        dragRight(&estimator, samples: 60, speed: 100)
        XCTAssertEqual(
            estimator.deformation.anchor.dy,
            tuning.grabAnchorLimit,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            estimator.deformation.rotation,
            -tuning.grabAnchorLimit * 100 * tuning.rotationGain,
            accuracy: 0.003
        )
    }

    func testResetReturnsToNeutral() {
        var estimator = DragDeformationEstimator()
        estimator.beginDrag(grabVector: CGVector(dx: 0, dy: 1))
        dragRight(&estimator, samples: 60, speed: 600)
        XCTAssertGreaterThan(estimator.deformation.stretchScale, 1.3)

        estimator.reset()
        XCTAssertEqual(estimator.deformation, .neutral)
    }

    func testCustomTuningIsRespected() {
        let custom = DeformationTuning(
            velocityTimeConstant: 0.05,
            velocityAtMaxStretch: 400,
            maxStretch: 0.2,
            maxRotation: 0.05,
            grabAnchorLimit: 0.5
        )
        var estimator = DragDeformationEstimator(tuning: custom)
        estimator.beginDrag(grabVector: CGVector(dx: 0, dy: 1))
        dragRight(&estimator, samples: 90, speed: 400)
        XCTAssertEqual(estimator.deformation.stretchScale, 1.2, accuracy: 0.01)
        XCTAssertEqual(estimator.deformation.anchor.dy, 0.5, accuracy: 0.0001)
        // torque = -0.5 * 400 -> rotation = -200 * gain = -0.1, capped at -0.05
        XCTAssertEqual(estimator.deformation.rotation, -0.05, accuracy: 0.005)
    }
}
