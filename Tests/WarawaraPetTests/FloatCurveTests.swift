import XCTest
@testable import WarawaraPet

final class FloatCurveTests: XCTestCase {
    func testOffsetYStartsAndEndsAtZeroAndPeaksAtHalf() {
        XCTAssertEqual(FloatCurve.offsetY(at: 0, height: 100), 0, accuracy: 0.0001)
        XCTAssertEqual(FloatCurve.offsetY(at: 1, height: 100), 0, accuracy: 0.0001)
        XCTAssertEqual(FloatCurve.offsetY(at: 0.5, height: 100), 100, accuracy: 0.0001)
    }

    func testOffsetYStaysWithinHeight() {
        for i in 0...100 {
            let t = CGFloat(i) / 100
            let y = FloatCurve.offsetY(at: t, height: 100)
            XCTAssertGreaterThanOrEqual(y, -0.0001)
            XCTAssertLessThanOrEqual(y, 100.0001)
        }
    }

    func testAscentAndDescentAreMonotonic() {
        var previous: CGFloat = -1
        for i in 0...50 {
            let y = FloatCurve.offsetY(at: CGFloat(i) / 100, height: 100)
            XCTAssertGreaterThanOrEqual(y, previous)
            previous = y
        }
        for i in 50...100 {
            let y = FloatCurve.offsetY(at: CGFloat(i) / 100, height: 100)
            XCTAssertLessThanOrEqual(y, previous + 0.0001)
            previous = y
        }
    }

    func testOffsetXReturnsHomeAndStaysWithinDrift() {
        let phases: [CGFloat] = [0, .pi / 2, 2.3]
        for phase in phases {
            XCTAssertEqual(FloatCurve.offsetX(at: 0, drift: 60, phase: phase), 0, accuracy: 0.0001)
            XCTAssertEqual(FloatCurve.offsetX(at: 1, drift: 60, phase: phase), 0, accuracy: 0.0001)
            for i in 0...100 {
                let x = FloatCurve.offsetX(at: CGFloat(i) / 100, drift: 60, phase: phase)
                XCTAssertLessThanOrEqual(abs(x), 60.0001)
            }
        }
    }

    func testLiftStretchPeaksAtEndsAndIsZeroAtApex() {
        XCTAssertEqual(FloatCurve.liftStretch(at: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(FloatCurve.liftStretch(at: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(FloatCurve.liftStretch(at: 0.5), 0, accuracy: 0.0001)
        XCTAssertEqual(FloatCurve.liftStretch(at: 0.25), FloatCurve.liftStretch(at: 0.75), accuracy: 0.0001)
    }

    func testFloatParametersStayWithinConfiguredBounds() {
        var rng = SeededRandomSource(seed: 13)
        let tuning = PersonalityTuning.default
        for _ in 0..<200 {
            let p = FloatParameters.random(using: &rng, tuning: tuning)
            XCTAssertTrue((tuning.floatMinHeight...tuning.floatMaxHeight).contains(p.height))
            XCTAssertTrue((tuning.floatMinDrift...tuning.floatMaxDrift).contains(p.drift))
            XCTAssertTrue((tuning.floatMinDuration...tuning.floatMaxDuration).contains(p.duration))
            XCTAssertTrue((0...(2 * .pi)).contains(p.swayPhase))
        }
    }
}
