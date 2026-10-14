import XCTest
@testable import WarawaraPet

/// State -> parameter mapping: continuous targets, never instant face
/// switches. All tests are pure and deterministic.
final class WarawaraExpressionMapperTests: XCTestCase {
    private func context(
        state: PetState = .idle,
        gaze: CGVector = .zero,
        drag: PetDeformation = .neutral,
        hop: CGFloat = 0,
        float: CGFloat = 0,
        breath: CGFloat = 0,
        floatPhase: CGFloat = 0,
        blink: CGFloat = 0
    ) -> WarawaraExpressionContext {
        WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(
                state: state,
                gaze: gaze,
                dragDeformation: drag,
                hopProgress: hop,
                floatProgress: float
            ),
            breathPhase: breath,
            floatPhase: floatPhase,
            blink: blink
        )
    }

    // MARK: - Idle

    func testIdleTargetsNeutralOpenFace() {
        let p = WarawaraExpressionMapper.targetParameters(for: context())
        XCTAssertEqual(p.eyeOpenness, 1, accuracy: 0.001)
        XCTAssertEqual(p.gazeX, 0, accuracy: 0.001)
        XCTAssertEqual(p.gazeY, 0, accuracy: 0.001)
        XCTAssertEqual(p.mouthStyle, .neutral)
        XCTAssertEqual(p.mouthOpenAmount, 0, accuracy: 0.001)
        XCTAssertEqual(p.drowsiness, 0, accuracy: 0.001)
        XCTAssertEqual(p.pressAmount, 0, accuracy: 0.001)
    }

    // MARK: - Curious

    func testCuriousGazeFollowsCursorDirectionAndClamps() {
        let p = WarawaraExpressionMapper.targetParameters(
            for: context(state: .curious, gaze: CGVector(dx: 0.6, dy: -0.4))
        )
        XCTAssertEqual(p.gazeX, 0.6, accuracy: 0.001)
        XCTAssertEqual(p.gazeY, -0.4, accuracy: 0.001)
        // Coordinated turn: body leans toward the gaze on top of the pose
        // pipeline, mouth softens slightly when focused.
        XCTAssertEqual(p.bodyTilt, 0.04 * 0.6, accuracy: 0.001)
        let focus = WarawaraExpressionMapper.focusAmount(gazeX: 0.6, gazeY: -0.4)
        XCTAssertEqual(p.mouthOpenAmount, 0.12 * focus, accuracy: 0.001)
        XCTAssertEqual(p.mouthStyle, .neutral)

        let clamped = WarawaraExpressionMapper.targetParameters(
            for: context(state: .curious, gaze: CGVector(dx: 2.5, dy: -2.0))
        )
        XCTAssertEqual(clamped.gazeX, 1, accuracy: 0.001)
        XCTAssertEqual(clamped.gazeY, -1, accuracy: 0.001)
    }

    func testCuriousGazeOffProducesNoTurnOrMouthResponse() {
        let p = WarawaraExpressionMapper.targetParameters(
            for: context(state: .curious, gaze: .zero)
        )
        XCTAssertEqual(p.gazeX, 0, accuracy: 0.001)
        XCTAssertEqual(p.bodyTilt, 0, accuracy: 0.001)
        XCTAssertEqual(p.mouthOpenAmount, 0, accuracy: 0.001)
    }

    // MARK: - Sleepy / sleeping

    func testSleepyDroopsEyesAndRaisesDrowsiness() {
        let p = WarawaraExpressionMapper.targetParameters(for: context(state: .sleepy))
        XCTAssertEqual(p.eyeOpenness, 0.5, accuracy: 0.001)
        XCTAssertEqual(p.drowsiness, 0.5, accuracy: 0.001)
        XCTAssertEqual(p.mouthStyle, .relaxed)
        XCTAssertEqual(p.bodySquashX, 1.02, accuracy: 0.001)
        XCTAssertEqual(p.bodySquashY, 0.98, accuracy: 0.001)
    }

    func testSleepingClosesEyesFully() {
        let p = WarawaraExpressionMapper.targetParameters(for: context(state: .sleeping))
        XCTAssertEqual(p.eyeOpenness, 0, accuracy: 0.001)
        XCTAssertEqual(p.drowsiness, 1, accuracy: 0.001)
        XCTAssertEqual(p.mouthStyle, .sleepy)
    }

    func testBlinkDoesNotAffectSleepingButMultipliesOpennessElsewhere() {
        let idle = WarawaraExpressionMapper.targetParameters(
            for: context(state: .idle, blink: 1)
        )
        // Full blink leaves the eye layer nearly at the closed artwork
        // (multiplier 0.95) so blinks are clearly readable.
        XCTAssertEqual(idle.eyeOpenness, 0.05, accuracy: 0.001)

        let sleeping = WarawaraExpressionMapper.targetParameters(
            for: context(state: .sleeping, blink: 1)
        )
        XCTAssertEqual(sleeping.eyeOpenness, 0, accuracy: 0.001)
    }

    // MARK: - Clicked / pressed

    func testClickedPressAndSquint() {
        let p = WarawaraExpressionMapper.targetParameters(for: context(state: .clicked))
        XCTAssertEqual(p.pressAmount, 1, accuracy: 0.001)
        XCTAssertEqual(p.eyeOpenness, 0.62, accuracy: 0.001)
        XCTAssertEqual(p.mouthStyle, .pressed)
    }

    // MARK: - Dragged

    func testDraggedFaceFollowsDragDirectionAndIntensity() {
        let deformation = PetDeformation(
            stretchAngle: 0,
            stretchScale: 1 + DeformationTuning.default.maxStretch,
            perpendicularScale: 1 / (1 + DeformationTuning.default.maxStretch),
            rotation: 0,
            anchor: CGVector(dx: DeformationTuning.default.grabAnchorLimit, dy: 0)
        )
        let p = WarawaraExpressionMapper.targetParameters(
            for: context(state: .dragged, drag: deformation)
        )
        XCTAssertEqual(p.dragAmount, 1, accuracy: 0.01)
        XCTAssertEqual(p.dragDirectionX, 1, accuracy: 0.01)
        XCTAssertEqual(p.dragDirectionY, 0, accuracy: 0.01)
        XCTAssertEqual(p.gazeX, 0.35, accuracy: 0.01)
        XCTAssertEqual(p.eyeOpenness, 1.0, accuracy: 0.01)
        XCTAssertEqual(p.mouthStyle, .open)
    }

    func testDragAnchorNormalizationClamps() {
        let direction = WarawaraExpressionMapper.normalizedDragDirection(
            CGVector(dx: 2.0, dy: -2.0)
        )
        XCTAssertEqual(direction.dx, 1, accuracy: 0.001)
        XCTAssertEqual(direction.dy, -1, accuracy: 0.001)
    }

    // MARK: - Hop / float / settling

    func testHopMouthOpensMidFlightOnly() {
        let mid = WarawaraExpressionMapper.targetParameters(
            for: context(state: .hop, hop: 0.5)
        )
        XCTAssertEqual(mid.mouthStyle, .open)
        XCTAssertEqual(mid.mouthOpenAmount, 0.5, accuracy: 0.01)

        let grounded = WarawaraExpressionMapper.targetParameters(
            for: context(state: .hop, hop: 0.05)
        )
        XCTAssertEqual(grounded.mouthStyle, .neutral)
        XCTAssertEqual(grounded.mouthOpenAmount, 0, accuracy: 0.001)
    }

    func testHopFlightAmountBounds() {
        XCTAssertEqual(WarawaraExpressionMapper.hopFlightAmount(0), 0, accuracy: 0.001)
        XCTAssertEqual(WarawaraExpressionMapper.hopFlightAmount(0.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(WarawaraExpressionMapper.hopFlightAmount(1), 0, accuracy: 0.001)
        XCTAssertEqual(WarawaraExpressionMapper.hopFlightAmount(-0.5), 0, accuracy: 0.001)
        XCTAssertEqual(WarawaraExpressionMapper.hopFlightAmount(1.5), 0, accuracy: 0.001)
    }

    func testFloatGazesGentlyAndPassesPhase() {
        let p = WarawaraExpressionMapper.targetParameters(
            for: context(state: .float, floatPhase: 0.25)
        )
        XCTAssertEqual(p.floatPhase, 0.25, accuracy: 0.001)
        XCTAssertEqual(p.gazeX, 0.25, accuracy: 0.01)
        XCTAssertEqual(p.gazeY, 0.15 * sin(2 * .pi * 0.25 + 1.2), accuracy: 0.01)
        XCTAssertEqual(p.mouthOpenAmount, 0.15, accuracy: 0.01)
    }

    func testSettlingLooksDazed() {
        let p = WarawaraExpressionMapper.targetParameters(for: context(state: .settling))
        XCTAssertEqual(p.eyeOpenness, 0.9, accuracy: 0.001)
        XCTAssertEqual(p.mouthStyle, .neutral)
    }

    // MARK: - Driver time helpers

    func testBreathPhaseLoops() {
        XCTAssertEqual(WarawaraExpressionDriver.breathPhase(at: 0), 0, accuracy: 0.001)
        XCTAssertEqual(WarawaraExpressionDriver.breathPhase(at: 2), 0.5, accuracy: 0.001)
        XCTAssertEqual(WarawaraExpressionDriver.breathPhase(at: 4), 0, accuracy: 0.001)
        XCTAssertEqual(WarawaraExpressionDriver.breathPhase(at: 4.5), 0.125, accuracy: 0.001)
    }

    func testBlinkIsBoundedAndMostlyZero() {
        var maxValue: CGFloat = 0
        var pulseCount = 0
        for t in stride(from: 0.0, through: 20.0, by: 0.02) {
            let v = WarawaraExpressionDriver.blink(at: t)
            XCTAssertTrue(v >= 0 && v <= 1)
            maxValue = max(maxValue, v)
            if v > 0.9 { pulseCount += 1 }
        }
        XCTAssertEqual(maxValue, 1, accuracy: 0.01)
        XCTAssertGreaterThan(pulseCount, 3, "expects several blinks over 20 s")
        XCTAssertLessThan(pulseCount, 60, "blinks must be brief, not constant")
    }

    func testBlinkPulseIsAsymmetricWithClosedHold() {
        // Close is faster than reopen, and the lid stays fully closed
        // for a readable hold, so the blink is visible to a human.
        let phase = 0.0
        let close = WarawaraExpressionDriver.blinkPulse(phase + 0.03, period: 10, phase: 0)
        let hold = WarawaraExpressionDriver.blinkPulse(phase + 0.08, period: 10, phase: 0)
        let reopening = WarawaraExpressionDriver.blinkPulse(phase + 0.14, period: 10, phase: 0)
        let after = WarawaraExpressionDriver.blinkPulse(phase + 0.4, period: 10, phase: 0)
        XCTAssertGreaterThan(close, 0.5, "closing must be underway at 0.03 s")
        XCTAssertEqual(hold, 1, accuracy: 0.001)
        XCTAssertTrue(reopening > 0 && reopening < 1, "reopen must be gradual")
        XCTAssertEqual(after, 0, accuracy: 0.001)
        // Asymmetry: at symmetric offsets around the hold the closing
        // value exceeds the reopening value (close faster than open).
        let closingEarly = WarawaraExpressionDriver.blinkPulse(phase + 0.02, period: 10, phase: 0)
        let reopeningLate = WarawaraExpressionDriver.blinkPulse(phase + 0.23, period: 10, phase: 0)
        XCTAssertGreaterThan(closingEarly, reopeningLate)
    }
}
