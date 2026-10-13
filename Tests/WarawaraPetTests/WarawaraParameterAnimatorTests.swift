import XCTest
@testable import WarawaraPet

/// Continuous easing: monotonic convergence, no overshoot, asymmetric
/// press response, and time helpers stay deterministic.
final class WarawaraParameterAnimatorTests: XCTestCase {
    func testEyeOpennessEasesMonotonicallyWithoutOvershoot() {
        var animator = WarawaraParameterAnimator()
        animator.set(WarawaraPerformanceParameters.neutral) // openness 1
        var target = WarawaraPerformanceParameters.neutral
        target.eyeOpenness = 0.05

        var previous = animator.parameters.eyeOpenness
        for _ in 0..<80 {
            animator.step(toward: target, dt: 0.05)
            let value = animator.parameters.eyeOpenness
            XCTAssertLessThanOrEqual(value, previous + 0.0001, "must never rise toward a lower target")
            XCTAssertGreaterThanOrEqual(value, target.eyeOpenness - 0.0001, "must never overshoot")
            previous = value
        }
        XCTAssertEqual(animator.parameters.eyeOpenness, target.eyeOpenness, accuracy: 0.01)
    }

    func testGazeReachesTargetWithinA_fewResponseTimes() {
        var animator = WarawaraParameterAnimator()
        var target = WarawaraPerformanceParameters.neutral
        target.gazeX = 1
        for _ in 0..<60 {
            animator.step(toward: target, dt: 0.03)
        }
        XCTAssertEqual(animator.parameters.gazeX, 1, accuracy: 0.05)
    }

    func testDrowsinessChangesSlowly() {
        var animator = WarawaraParameterAnimator()
        var target = WarawaraPerformanceParameters.neutral
        target.drowsiness = 1
        for _ in 0..<20 {
            animator.step(toward: target, dt: 0.05) // 1.0 s total, tau 1.4 s
        }
        XCTAssertLessThan(animator.parameters.drowsiness, 0.6, "sleepy drift must not snap")
    }

    func testPressAttackIsFasterThanRelease() {
        var animator = WarawaraParameterAnimator()

        var pressTarget = WarawaraPerformanceParameters.neutral
        pressTarget.pressAmount = 1
        animator.step(toward: pressTarget, dt: 0.1)
        let attackValue = animator.parameters.pressAmount

        var releaseTarget = WarawaraPerformanceParameters.neutral
        releaseTarget.pressAmount = 0
        animator.step(toward: releaseTarget, dt: 0.1)
        let releaseValue = animator.parameters.pressAmount

        XCTAssertGreaterThan(attackValue, 0.8, "press attack is quick")
        XCTAssertGreaterThan(releaseValue, 0.5, "release rebounds slowly")
    }

    func testZeroDeltaTimeChangesNothing() {
        var animator = WarawaraParameterAnimator()
        var target = WarawaraPerformanceParameters.neutral
        target.gazeX = 1
        let before = animator.parameters
        animator.step(toward: target, dt: 0)
        XCTAssertEqual(animator.parameters, before)
    }

    func testParametersStayClamped() {
        var animator = WarawaraParameterAnimator()
        var target = WarawaraPerformanceParameters.neutral
        target.gazeX = 5
        target.eyeOpenness = -3
        target.drowsiness = 9
        for _ in 0..<200 {
            animator.step(toward: target, dt: 0.05)
        }
        let p = animator.parameters
        XCTAssertTrue(p.gazeX >= -1 && p.gazeX <= 1)
        XCTAssertTrue(p.eyeOpenness >= 0 && p.eyeOpenness <= 1)
        XCTAssertTrue(p.drowsiness >= 0 && p.drowsiness <= 1)
    }

    func testMouthOpenAmountAndSquashAlsoEase() {
        var animator = WarawaraParameterAnimator()
        var target = WarawaraPerformanceParameters.neutral
        target.mouthOpenAmount = 0.8
        target.bodySquashY = 0.9
        for _ in 0..<40 {
            animator.step(toward: target, dt: 0.05)
        }
        XCTAssertEqual(animator.parameters.mouthOpenAmount, 0.8, accuracy: 0.02)
        XCTAssertEqual(animator.parameters.bodySquashY, 0.9, accuracy: 0.02)
    }

    func testDistanceToNeutralDecreasesOverTime() {
        var animator = WarawaraParameterAnimator()
        var target = WarawaraPerformanceParameters.neutral
        target.eyeOpenness = 0.1
        target.drowsiness = 1
        target.gazeX = -0.7
        target.mouthStyle = .sleepy

        var previousDistance = animator.parameters.distance(to: target)
        for _ in 0..<120 {
            animator.step(toward: target, dt: 0.05)
            let distance = animator.parameters.distance(to: target)
            XCTAssertLessThanOrEqual(distance, previousDistance + 0.0001)
            previousDistance = distance
        }
        XCTAssertLessThan(previousDistance, 0.05)
    }
}
