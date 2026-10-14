import XCTest
@testable import WarawaraPet

/// Pure geometry of the layered renderer: face registration, gaze
/// bounds, focus/press blends, and numerical stability.
final class WarawaraLayeredGeometryTests: XCTestCase {
    private let renderSize = CGSize(width: 143.9, height: 143.9)
    private let bodyBounds = CGRect(x: 0.10, y: 0.09, width: 0.80, height: 0.82)

    func testGazeOffsetIsBoundedByGazeRange() {
        for gaze in [CGFloat(-2), -1, -0.5, 0, 0.5, 1, 2] {
            let offset = WarawaraLayeredGeometry.gazeOffset(
                axis: .x, gaze: gaze, range: 0.06, renderSize: renderSize
            )
            XCTAssertTrue(
                abs(offset) <= 0.06 * renderSize.width + 0.001,
                "gaze offset must stay inside the rig range"
            )
        }
    }

    func testGazeOffsetZeroForZeroRange() {
        XCTAssertEqual(
            WarawaraLayeredGeometry.gazeOffset(axis: .y, gaze: 1, range: 0, renderSize: renderSize),
            0
        )
    }

    func testFaceShiftIsBoundedAndSmall() {
        for gaze in [CGFloat(-2), -1, -0.5, 0, 0.5, 1, 2] {
            let shift = WarawaraLayeredGeometry.faceShiftOffset(
                axis: .x, gaze: gaze, renderSize: renderSize
            )
            XCTAssertTrue(shift.isFinite)
            XCTAssertTrue(
                abs(shift) <= 0.02 * renderSize.width + 0.001,
                "face shift must stay subtle"
            )
        }
        XCTAssertEqual(
            WarawaraLayeredGeometry.faceShiftOffset(axis: .x, gaze: 1, renderSize: renderSize),
            0.02 * renderSize.width,
            accuracy: 0.01
        )
        XCTAssertEqual(
            WarawaraLayeredGeometry.faceShiftOffset(axis: .y, gaze: 1, renderSize: renderSize),
            0.015 * renderSize.height,
            accuracy: 0.01
        )
    }

    func testBreathScaleIsContinuousAndBounded() {
        for phase in stride(from: 0.0, through: 2.0, by: 0.1) {
            for drowsiness in [CGFloat(0), 0.5, 1] {
                let scale = WarawaraLayeredGeometry.breathScale(
                    breathPhase: CGFloat(phase), drowsiness: drowsiness
                )
                XCTAssertTrue(scale.isFinite)
                XCTAssertGreaterThan(scale, 0.98)
                XCTAssertLessThan(scale, 1.02)
            }
        }
    }

    func testBreathingDeepensWithDrowsiness() {
        let peak = WarawaraLayeredGeometry.breathScale(breathPhase: 0.25, drowsiness: 0)
        let peakSleepy = WarawaraLayeredGeometry.breathScale(breathPhase: 0.25, drowsiness: 1)
        XCTAssertGreaterThan(peakSleepy, peak)
    }

    func testFocusBlendIsSmoothAndMonotonic() {
        var previous: CGFloat = -1
        for magnitude in stride(from: 0.0, through: 1.0, by: 0.05) {
            let focus = WarawaraLayeredGeometry.focusAmount(
                gazeX: CGFloat(magnitude), gazeY: 0
            )
            XCTAssertTrue(focus.isFinite)
            XCTAssertTrue(focus >= previous - 0.001, "focus must be monotonic")
            previous = focus
        }
        XCTAssertEqual(
            WarawaraLayeredGeometry.focusAmount(gazeX: 0.2, gazeY: 0.2), 0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WarawaraLayeredGeometry.focusAmount(gazeX: 0.9, gazeY: 0.9), 1,
            accuracy: 0.001
        )
    }

    func testPressBlendIsSmooth() {
        XCTAssertEqual(WarawaraLayeredGeometry.pressBlend(pressAmount: 0), 0, accuracy: 0.001)
        XCTAssertEqual(WarawaraLayeredGeometry.pressBlend(pressAmount: 1), 1, accuracy: 0.001)
        let mid = WarawaraLayeredGeometry.pressBlend(pressAmount: 0.42)
        XCTAssertTrue(mid > 0 && mid < 1)
    }

    func testMouthPivotFallsBackToAnchor() {
        let layer = WarawaraRigManifest.Layer(
            kind: .mouth,
            images: ["soft": "soft.png"],
            anchor: CGPoint(x: 0.4, y: 0.6),
            gazeRange: nil,
            pivot: nil
        )
        let unit = WarawaraLayeredGeometry.pivotUnit(layer: layer)
        XCTAssertEqual(unit.x, 0.4, accuracy: 0.001)
        XCTAssertEqual(unit.y, 0.6, accuracy: 0.001)

        let withPivot = WarawaraRigManifest.Layer(
            kind: .mouth,
            images: ["soft": "soft.png"],
            anchor: CGPoint(x: 0.5, y: 0.5),
            gazeRange: nil,
            pivot: CGPoint(x: 0.495, y: 0.51)
        )
        let unit2 = WarawaraLayeredGeometry.pivotUnit(layer: withPivot)
        XCTAssertEqual(unit2.x, 0.495, accuracy: 0.001)
        XCTAssertEqual(unit2.y, 0.51, accuracy: 0.001)
    }

    func testBodyCenterUnitMatchesBodyBoundsMid() {
        let unit = WarawaraLayeredGeometry.bodyCenterUnit(bodyBounds: bodyBounds)
        XCTAssertEqual(unit.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(unit.y, 0.5, accuracy: 0.001)
    }

    func testWakeReopeningIsContinuousAndSlowEnough() {
        // sleeping (drowsy) -> idle: eye openness must rise monotonically
        // without snapping; the drowsy response slows the reopen.
        var animator = WarawaraParameterAnimator()
        var sleeping = WarawaraPerformanceParameters.neutral
        sleeping.eyeOpenness = 0.05
        sleeping.drowsiness = 1
        animator.set(sleeping)
        var idle = WarawaraPerformanceParameters.neutral
        idle.eyeOpenness = 1
        idle.drowsiness = 0

        var previous = animator.parameters.eyeOpenness
        var smallestStep = CGFloat.greatestFiniteMagnitude
        for _ in 0..<120 {
            animator.step(toward: idle, dt: 1.0 / 30.0)
            let value = animator.parameters.eyeOpenness
            XCTAssertGreaterThanOrEqual(value, previous - 0.0001)
            smallestStep = min(smallestStep, value - previous)
            previous = value
        }
        XCTAssertGreaterThanOrEqual(previous, 0.9, "wake must finish reopening")
        XCTAssertLessThan(smallestStep, 0.05, "reopening must be gradual, not a snap")
    }

    func testParametersNeverBecomeNaN() {
        var animator = WarawaraParameterAnimator()
        var target = WarawaraPerformanceParameters.neutral
        target.gazeX = 1
        target.drowsiness = 1
        target.pressAmount = 1
        target.mouthOpenAmount = 1
        target.dragAmount = 1
        for _ in 0..<300 {
            animator.step(toward: target, dt: 0.033)
            let p = animator.parameters
            for value in [p.eyeOpenness, p.gazeX, p.gazeY, p.mouthOpenAmount,
                          p.drowsiness, p.pressAmount, p.dragAmount,
                          p.bodySquashX, p.bodySquashY, p.bodyTilt] {
                XCTAssertTrue(value.isFinite, "parameter must stay finite")
            }
        }
    }
}
