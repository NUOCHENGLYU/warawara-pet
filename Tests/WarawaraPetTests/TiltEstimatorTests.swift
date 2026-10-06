import XCTest
@testable import WarawaraPet

final class TiltEstimatorTests: XCTestCase {
    func testTiltForVelocityClamps() {
        let estimator = TiltEstimator()
        XCTAssertEqual(estimator.tilt(forVelocityX: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(estimator.tilt(forVelocityX: 600), 0.15, accuracy: 0.0001)
        XCTAssertEqual(estimator.tilt(forVelocityX: 1200), 0.15, accuracy: 0.0001)
        XCTAssertEqual(estimator.tilt(forVelocityX: -600), -0.15, accuracy: 0.0001)
        XCTAssertEqual(estimator.tilt(forVelocityX: 300), 0.075, accuracy: 0.0001)
    }

    func testSlowDragYieldsSmallTiltFastDragSaturates() {
        var slow = TiltEstimator()
        var fast = TiltEstimator()
        var t: TimeInterval = 0
        for _ in 1...30 {
            t += 0.016
            slow.update(deltaX: 1.6, at: t)   // 100 pt/s
            fast.update(deltaX: 12.8, at: t)  // 800 pt/s
        }
        XCTAssertGreaterThan(slow.tilt, 0)
        XCTAssertLessThan(slow.tilt, 0.05)
        XCTAssertEqual(fast.tilt, 0.15, accuracy: 0.005)
    }

    func testTiltApproachesSaturationMonotonically() {
        var estimator = TiltEstimator()
        var t: TimeInterval = 0
        var previous = estimator.tilt
        for _ in 1...60 {
            t += 0.016
            estimator.update(deltaX: 12.8, at: t)  // 800 pt/s
            XCTAssertGreaterThanOrEqual(estimator.tilt, previous)
            previous = estimator.tilt
        }
        XCTAssertEqual(estimator.tilt, 0.15, accuracy: 0.001)
    }

    func testReversalPassesThroughNeutralSmoothly() {
        var estimator = TiltEstimator()
        var t: TimeInterval = 0
        for _ in 1...60 {
            t += 0.016
            estimator.update(deltaX: 9.6, at: t)  // right at 600 pt/s
        }
        XCTAssertEqual(estimator.tilt, 0.15, accuracy: 0.002)

        var smallestMagnitude = CGFloat.greatestFiniteMagnitude
        var wentNegative = false
        for _ in 1...60 {
            t += 0.016
            estimator.update(deltaX: -9.6, at: t)  // left at 600 pt/s
            smallestMagnitude = min(smallestMagnitude, abs(estimator.tilt))
            if estimator.tilt < 0 { wentNegative = true }
            XCTAssertLessThanOrEqual(estimator.tilt, 0.15 + 0.0001)
            XCTAssertGreaterThanOrEqual(estimator.tilt, -0.15 - 0.0001)
        }
        XCTAssertTrue(wentNegative)
        XCTAssertLessThan(smallestMagnitude, 0.05)
    }

    func testLongGapDecaysTiltInsteadOfFreezingOrSpiking() {
        var estimator = TiltEstimator()
        var t: TimeInterval = 0
        for _ in 1...60 {
            t += 0.016
            estimator.update(deltaX: 9.6, at: t)
        }
        XCTAssertEqual(estimator.tilt, 0.15, accuracy: 0.002)
        let beforeGap = estimator.tilt

        t += 5  // long pause; huge delta must not spike
        estimator.update(deltaX: 500, at: t)
        XCTAssertLessThan(estimator.tilt, beforeGap)
        XCTAssertGreaterThanOrEqual(estimator.tilt, -0.15)
        XCTAssertLessThanOrEqual(estimator.tilt, 0.15)
        XCTAssertEqual(estimator.tilt, 0, accuracy: 0.01)
    }

    func testZeroDtIsIgnored() {
        var estimator = TiltEstimator()
        estimator.update(deltaX: 10, at: 5)
        let before = estimator.tilt
        estimator.update(deltaX: 10, at: 5)
        XCTAssertEqual(estimator.tilt, before)
    }

    func testFirstUpdateOnlyRecordsTimestamp() {
        var estimator = TiltEstimator()
        estimator.update(deltaX: 100, at: 3)
        XCTAssertEqual(estimator.tilt, 0)
    }

    func testResetClearsState() {
        var estimator = TiltEstimator()
        var t: TimeInterval = 0
        for _ in 1...60 {
            t += 0.016
            estimator.update(deltaX: 9.6, at: t)
        }
        XCTAssertGreaterThan(abs(estimator.tilt), 0.1)

        estimator.reset()
        XCTAssertEqual(estimator.tilt, 0)

        t += 0.016
        estimator.update(deltaX: 9.6, at: t)
        XCTAssertEqual(estimator.tilt, 0)
    }

    func testParametersAreConfigurable() {
        var estimator = TiltEstimator(
            timeConstant: 0.5,
            maxTilt: 0.3,
            velocityAtMaxTilt: 300
        )
        XCTAssertEqual(estimator.tilt(forVelocityX: 300), 0.3, accuracy: 0.0001)
        XCTAssertEqual(estimator.tilt(forVelocityX: -300), -0.3, accuracy: 0.0001)
        XCTAssertEqual(estimator.tilt(forVelocityX: 900), 0.3, accuracy: 0.0001)

        var t: TimeInterval = 0
        for _ in 1...120 {
            t += 0.016
            estimator.update(deltaX: 8, at: t)  // 500 pt/s
        }
        XCTAssertEqual(estimator.tilt, 0.3, accuracy: 0.01)
    }
}
