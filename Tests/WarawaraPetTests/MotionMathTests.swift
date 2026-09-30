import XCTest
@testable import WarawaraPet

final class MotionMathTests: XCTestCase {
    func testHopOffsetYStartsAndEndsAtZero() {
        XCTAssertEqual(HopCurve.offsetY(at: 0, height: 100), 0, accuracy: 0.001)
        XCTAssertEqual(HopCurve.offsetY(at: 1, height: 100), 0, accuracy: 0.001)
    }

    func testHopOffsetYPeaksAtMidpoint() {
        XCTAssertEqual(HopCurve.offsetY(at: 0.5, height: 100), 100, accuracy: 0.001)
        XCTAssertGreaterThan(
            HopCurve.offsetY(at: 0.5, height: 100),
            HopCurve.offsetY(at: 0.3, height: 100)
        )
        XCTAssertGreaterThan(
            HopCurve.offsetY(at: 0.5, height: 100),
            HopCurve.offsetY(at: 0.7, height: 100)
        )
    }

    func testHopOffsetYIsSymmetric() {
        let t: CGFloat = 0.35
        XCTAssertEqual(
            HopCurve.offsetY(at: t, height: 80),
            HopCurve.offsetY(at: 1 - t, height: 80),
            accuracy: 0.001
        )
    }

    func testHopOffsetXIsLinearAndMonotonic() {
        let drift: CGFloat = -40
        XCTAssertEqual(HopCurve.offsetX(at: 0, drift: drift), 0, accuracy: 0.001)
        XCTAssertEqual(HopCurve.offsetX(at: 1, drift: drift), drift, accuracy: 0.001)
        XCTAssertEqual(HopCurve.offsetX(at: 0.5, drift: drift), drift / 2, accuracy: 0.001)
    }

    func testHopStretchFactorIsZeroAtApexAndOneAtEnds() {
        XCTAssertEqual(HopCurve.stretchFactor(at: 0), 1, accuracy: 0.001)
        XCTAssertEqual(HopCurve.stretchFactor(at: 0.5), 0, accuracy: 0.001)
        XCTAssertEqual(HopCurve.stretchFactor(at: 1), 1, accuracy: 0.001)
    }

    func testHopLandingSquashIsAPulseNearLanding() {
        XCTAssertEqual(HopCurve.squashAtLanding(at: 0), 0, accuracy: 0.001)
        XCTAssertEqual(HopCurve.squashAtLanding(at: 1), 0, accuracy: 0.001)
        XCTAssertGreaterThan(HopCurve.squashAtLanding(at: 0.85), 0.9)
        XCTAssertLessThanOrEqual(HopCurve.squashAtLanding(at: 0.85), 1.0)
    }

    func testSettleStartsAndEndsAtZero() {
        XCTAssertEqual(SettleCurve.offsetY(at: 0, amplitude: 18), 0, accuracy: 0.001)
        XCTAssertEqual(SettleCurve.offsetY(at: 1, amplitude: 18), 0, accuracy: 0.02)
    }

    func testSettleOffsetIsBoundedByEnvelope() {
        for i in 0...20 {
            let t = CGFloat(i) / 20
            XCTAssertLessThanOrEqual(
                abs(SettleCurve.offsetY(at: t, amplitude: 18)),
                SettleCurve.envelope(at: t, amplitude: 18) + 0.001
            )
        }
    }

    func testSettleEnvelopeDecaysMonotonically() {
        var previous = SettleCurve.envelope(at: 0, amplitude: 18)
        for i in 1...20 {
            let t = CGFloat(i) / 20
            let current = SettleCurve.envelope(at: t, amplitude: 18)
            XCTAssertLessThanOrEqual(current, previous)
            previous = current
        }
    }

    func testSettleSquashStartsSquashedAndRecovers() {
        XCTAssertEqual(SettleCurve.squashFactor(at: 0), 0.2, accuracy: 0.001)
        XCTAssertEqual(SettleCurve.squashFactor(at: 1), 0, accuracy: 0.001)
        XCTAssertLessThan(
            SettleCurve.squashFactor(at: 0.5),
            SettleCurve.squashFactor(at: 0)
        )
    }

    func testHopParametersStayWithinConfiguredBounds() {
        var rng = SeededRandomSource(seed: 42)
        for _ in 0..<200 {
            let parameters = HopParameters.random(using: &rng)
            XCTAssertTrue((60...120).contains(parameters.height))
            XCTAssertTrue((-40...40).contains(parameters.drift))
            XCTAssertTrue((0.9...1.4).contains(parameters.duration))
        }
    }
}
