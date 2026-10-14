import XCTest
@testable import WarawaraPet

/// The production expression driver model: single-step-per-date ticking
/// and stable gaze holding under a stationary cursor.
final class WarawaraExpressionDriverModelTests: XCTestCase {
    private func date(at time: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: time)
    }

    func testTickIsIdempotentPerDate() {
        let model = WarawaraExpressionDriverModel()
        let inputs = WarawaraExpressionInputs(state: .idle)

        model.tick(at: date(at: 1000), inputs: inputs)
        let first = model.parameters

        model.tick(at: date(at: 1000), inputs: inputs)
        XCTAssertEqual(model.parameters, first, "same-date ticks must not advance the animator")
    }

    func testTicksAdvanceOncePerNewDate() {
        let model = WarawaraExpressionDriverModel()
        var inputs = WarawaraExpressionInputs(state: .sleepy)

        model.tick(at: date(at: 1000), inputs: inputs)
        var previous = model.parameters.eyeOpenness
        var steps = 0
        for frame in 1...30 {
            model.tick(at: date(at: 1000 + Double(frame) / 30.0), inputs: inputs)
            let current = model.parameters.eyeOpenness
            XCTAssertLessThan(current, previous + 0.0001, "must be monotonic toward closure")
            if abs(current - previous) > 0.0001 { steps += 1 }
            previous = current
        }
        XCTAssertGreaterThan(steps, 5, "eye openness must progress across ticks")
    }

    func testStationaryGazeHoldsStable() {
        // A fixed off-center cursor: after convergence the gaze must stay
        // constant (no drift back toward neutral, no jitter).
        let model = WarawaraExpressionDriverModel()
        let inputs = WarawaraExpressionInputs(
            state: .curious,
            gaze: CGVector(dx: 0.6, dy: 0.2)
        )
        let start = 1000.0
        for frame in 0..<90 {
            model.tick(at: date(at: start + Double(frame) / 30.0), inputs: inputs)
        }
        let converged = model.parameters.gazeX
        XCTAssertEqual(converged, 0.6, accuracy: 0.05, "gaze must reach the target")

        // Hold for another three seconds with an identical cursor.
        var minObserved = converged
        var maxObserved = converged
        for frame in 90..<180 {
            model.tick(at: date(at: start + Double(frame) / 30.0), inputs: inputs)
            let g = model.parameters.gazeX
            minObserved = min(minObserved, g)
            maxObserved = max(maxObserved, g)
        }
        XCTAssertEqual(minObserved, converged, accuracy: 0.005, "gaze must not drift back toward neutral")
        XCTAssertEqual(maxObserved, converged, accuracy: 0.005)
    }

    func testStationaryGazeThroughEstimatorStaysStable() {
        // The 30 Hz curiosity tracker with an identical cursor direction
        // must converge and hold (no reset from repeated samples).
        var estimator = CuriosityPoseEstimator(tuning: .default)
        let direction = CGVector(dx: 0.7, dy: 0.1)
        for frame in 0..<90 {
            estimator.update(direction: direction, dwellProgress: 1, at: Double(frame) / 30.0)
        }
        let converged = estimator.direction
        XCTAssertEqual(converged.dx, 0.7, accuracy: 0.05)

        for frame in 90..<180 {
            estimator.update(direction: direction, dwellProgress: 1, at: Double(frame) / 30.0)
        }
        XCTAssertEqual(estimator.direction.dx, converged.dx, accuracy: 0.005)
        XCTAssertEqual(estimator.direction.dy, converged.dy, accuracy: 0.005)
    }

    func testBlinkChannelPassesThroughUnsmoothing() {
        var animator = WarawaraParameterAnimator()
        var target = WarawaraPerformanceParameters.neutral
        target.blinkAmount = 1
        animator.step(toward: target, dt: 0.033)
        XCTAssertEqual(animator.parameters.blinkAmount, 1, accuracy: 0.001)
        XCTAssertEqual(animator.parameters.eyeOpenness, 1, accuracy: 0.001, "state channel untouched by blink")

        target.blinkAmount = 0
        animator.step(toward: target, dt: 0.033)
        XCTAssertEqual(animator.parameters.blinkAmount, 0, accuracy: 0.001)
    }

    func testTurnEasesInHoldsAndReturnsSmoothly() {
        let model = WarawaraExpressionDriverModel()
        let curious = WarawaraExpressionInputs(state: .curious, gaze: CGVector(dx: 0.6, dy: 0.2))
        let start = 7000.0
        // Ease in.
        var previous: CGFloat = 0
        var eased = false
        for frame in 0..<90 {
            model.tick(at: Date(timeIntervalSinceReferenceDate: start + Double(frame) / 30.0), inputs: curious)
            let yaw = model.parameters.yawDegrees
            XCTAssertGreaterThanOrEqual(yaw, previous - 0.0001, "yaw must approach monotonically")
            if yaw > 12 { eased = true }
            previous = yaw
        }
        XCTAssertTrue(eased, "yaw must settle into the turned pose")
        XCTAssertEqual(model.parameters.yawDegrees, 15, accuracy: 0.5)
        XCTAssertEqual(model.parameters.pitchDegrees, 2, accuracy: 0.5)

        // Hold while the cursor stays still.
        let held = model.parameters.yawDegrees
        for frame in 90..<180 {
            model.tick(at: Date(timeIntervalSinceReferenceDate: start + Double(frame) / 30.0), inputs: curious)
        }
        XCTAssertEqual(model.parameters.yawDegrees, held, accuracy: 0.005)

        // Curious exits: smooth monotonic return to neutral.
        let idle = WarawaraExpressionInputs(state: .idle)
        previous = model.parameters.yawDegrees
        var steps = 0
        for frame in 180..<270 {
            model.tick(at: Date(timeIntervalSinceReferenceDate: start + Double(frame) / 30.0), inputs: idle)
            let yaw = model.parameters.yawDegrees
            XCTAssertLessThanOrEqual(yaw, previous + 0.0001, "return must be monotonic")
            if yaw < previous - 0.0001 { steps += 1 }
            previous = yaw
        }
        XCTAssertGreaterThan(steps, 5, "return must be gradual")
        XCTAssertEqual(model.parameters.yawDegrees, 0, accuracy: 0.1)
        XCTAssertEqual(model.parameters.pitchDegrees, 0, accuracy: 0.05)
    }

    func testFullBlinkReachesVisiblyClosedInProductionPipeline() {
        // Drive the REAL driver model through one blink window; the final
        // effective openness must reach the closed range.
        let model = WarawaraExpressionDriverModel()
        let inputs = WarawaraExpressionInputs(state: .idle)
        // The blink waveform peaks at ~0.3s into its period (phase 0.3):
        // first period starts at -0.3, so the hold is around t = 3.8k+0.3.
        var minEffective: CGFloat = 1
        for frame in 0..<180 {
            let t = 2000 + Double(frame) / 60.0
            model.tick(at: date(at: t), inputs: inputs)
            let effective = WarawaraLayeredGeometry.effectiveEyeOpenness(
                base: model.parameters.eyeOpenness,
                blink: model.parameters.blinkAmount
            )
            minEffective = min(minEffective, effective)
        }
        XCTAssertLessThanOrEqual(minEffective, 0.1, "a blink must reach a visibly closed state")
    }
}
