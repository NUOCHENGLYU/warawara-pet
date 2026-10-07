import XCTest
@testable import WarawaraPet

final class FloatCurveTests: XCTestCase {
    private let tuning = PersonalityTuning.default

    func testOffsetYStartsAtGroundWithNoSharpLaunch() {
        XCTAssertEqual(FloatCurve.offsetY(at: 0, height: 100, tuning: tuning), 0, accuracy: 0.0001)
        // After 1% of the float the pet is still low: no launch jump.
        XCTAssertLessThan(FloatCurve.offsetY(at: 0.01, height: 100, tuning: tuning), 5)
    }

    func testOffsetYHoversNearPeakHeight() {
        // Samples across the middle of the hover phase stay within the bob
        // amplitude of the peak height: a clearly visible plateau.
        let start = FloatCurve.liftEnd(tuning) + 0.05
        let end = FloatCurve.hoverEnd(tuning) - 0.05
        for i in 0...20 {
            let t = start + (end - start) * CGFloat(i) / 20
            let y = FloatCurve.offsetY(at: t, height: 100, tuning: tuning)
            XCTAssertGreaterThanOrEqual(y, 100 - tuning.floatBobAmplitude - 0.01)
            XCTAssertLessThanOrEqual(y, 100 + tuning.floatBobAmplitude + 0.01)
            XCTAssertGreaterThan(y, 0.7 * 100)
        }
    }

    func testLiftIsMonotonic() {
        var previous: CGFloat = -1
        let lift = FloatCurve.liftEnd(tuning)
        for i in 0...30 {
            let y = FloatCurve.offsetY(at: lift * CGFloat(i) / 30, height: 100, tuning: tuning)
            XCTAssertGreaterThanOrEqual(y, previous)
            previous = y
        }
    }

    func testDescentAndSettleAreMonotonicAndEndAtGround() {
        let descentStart = FloatCurve.descentEnd(tuning)
        var previous = FloatCurve.offsetY(at: descentStart, height: 100, tuning: tuning)
        for i in 0...100 {
            let t = descentStart + (1 - descentStart) * CGFloat(i) / 100
            let y = FloatCurve.offsetY(at: t, height: 100, tuning: tuning)
            XCTAssertLessThanOrEqual(y, previous + 0.0001)
            previous = y
        }
        XCTAssertEqual(FloatCurve.offsetY(at: 1, height: 100, tuning: tuning), 0, accuracy: 0.0001)
    }

    func testOffsetXReturnsHomeAndStaysWithinBounds() {
        let swayCycles = FloatCurve.swayCycles(duration: 6.5, tuning: tuning)
        let phases: [CGFloat] = [0, .pi / 2, 2.3]
        for phase in phases {
            XCTAssertEqual(
                FloatCurve.offsetX(at: 0, drift: 25, swayAmplitude: 45, swayCycles: swayCycles, swayPhase: phase),
                0,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                FloatCurve.offsetX(at: 1, drift: 25, swayAmplitude: 45, swayCycles: swayCycles, swayPhase: phase),
                0,
                accuracy: 0.0001
            )
            for i in 0...100 {
                let x = FloatCurve.offsetX(
                    at: CGFloat(i) / 100, drift: 25, swayAmplitude: 45,
                    swayCycles: swayCycles, swayPhase: phase
                )
                XCTAssertLessThanOrEqual(abs(x), 25 + 45 + 0.0001)
            }
        }
    }

    func testFloatParametersStayWithinConfiguredBounds() {
        var rng = SeededRandomSource(seed: 13)
        for _ in 0..<200 {
            let p = FloatParameters.random(using: &rng, tuning: tuning)
            XCTAssertTrue((0.8 * tuning.floatHeight...1.2 * tuning.floatHeight).contains(p.height))
            XCTAssertTrue((0.6 * tuning.floatHorizontalDrift...1.3 * tuning.floatHorizontalDrift).contains(p.drift))
            XCTAssertTrue((0.85 * tuning.floatDuration...1.15 * tuning.floatDuration).contains(p.duration))
            XCTAssertTrue((0...(2 * .pi)).contains(p.swayPhase))
        }
    }

    func testFloatPoseIsLowAmplitudeVolumePreservingAndVertical() {
        let params = FloatParameters(height: 145, drift: 25, duration: 6.5, swayPhase: 0)
        for i in 0...100 {
            let t = CGFloat(i) / 100
            let pose = FloatPoseMath.pose(at: t, parameters: params, tuning: tuning)
            XCTAssertGreaterThanOrEqual(pose.stretchScale, 1 - 0.0001)
            XCTAssertLessThanOrEqual(pose.stretchScale, 1 + tuning.floatBodyStretch + 0.0001)
            XCTAssertEqual(pose.stretchScale * pose.perpendicularScale, 1, accuracy: 0.0001)
            XCTAssertLessThanOrEqual(abs(pose.rotation), tuning.floatSwayLean + 0.0001)
            XCTAssertEqual(pose.stretchAngle, .pi / 2, accuracy: 0.0001)
            XCTAssertEqual(pose.anchor.dx, 0, accuracy: 0.0001)
            XCTAssertEqual(pose.anchor.dy, -1, accuracy: 0.0001)
        }
    }

    func testFloatPoseIsNeutralAtRest() {
        let params = FloatParameters(height: 145, drift: 25, duration: 6.5, swayPhase: 0)
        for t in [CGFloat(0), 1] {
            let pose = FloatPoseMath.pose(at: t, parameters: params, tuning: tuning)
            XCTAssertEqual(pose.stretchScale, 1, accuracy: 0.0001)
            XCTAssertEqual(pose.rotation, 0, accuracy: 0.0001)
        }
    }

    func testPhaseFractionsSumToLessThanOne() {
        let total = tuning.floatLiftFraction + tuning.floatHoverFraction + tuning.floatDescentFraction
        XCTAssertLessThan(total, 1)
        // Settle fraction is the remainder and stays in the soft range.
        let settle = 1 - total
        XCTAssertTrue((0.005...0.1).contains(settle))
    }
}
