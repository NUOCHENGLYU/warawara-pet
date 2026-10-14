import XCTest
@testable import WarawaraPet

private final class GazeFakeIdleTimeProvider: SystemIdleTimeProviding {
    var idleSeconds: TimeInterval = 0
    func secondsSinceLastUserActivity() -> TimeInterval { idleSeconds }
}

/// End-to-end curious gaze direction: from simulated on-screen cursor
/// positions through the controller's direction math, the expression
/// mapper, and the renderer's offset geometry. The canonical convention
/// is documented in WarawaraLayeredGeometry: gaze parameters are
/// UP-POSITIVE Y (NSEvent screen space); SwiftUI offsets are
/// DOWN-POSITIVE Y, converted exactly once.
final class CuriousGazeDirectionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var heldWindowController: PetWindowController?
    private let idle = GazeFakeIdleTimeProvider()

    override func setUp() {
        super.setUp()
        suiteName = "CuriousGazeDirectionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// Engages curiosity with the window at the origin (empty panel:
    /// frame == .zero, so the pet center is the screen origin).
    private func engagedController() -> PetController {
        let windowController = PetWindowController()
        heldWindowController = windowController
        let motion = PetMotionController(windowController: windowController)
        let store = PetPositionStore(defaults: defaults)
        let controller = PetController(
            windowController: windowController,
            motionController: motion,
            positionStore: store
        )
        controller.idleTimeProvider = idle
        controller.mouseLocationProvider = { CGPoint(x: 10, y: 10) }
        var t: TimeInterval = 100
        for _ in 0..<10 {
            t += 0.15
            controller.awarenessTick(at: t, evaluateSleepiness: false)
        }
        XCTAssertEqual(controller.state, .curious)
        return controller
    }

    private func settleGaze(_ controller: PetController, cursor: CGPoint) -> CGVector {
        controller.mouseLocationProvider = { cursor }
        var t: TimeInterval = 200
        for _ in 0..<60 {
            t += 0.033
            controller.curiosityTrackingTick(at: t)
        }
        return controller.curiosityDirection
    }

    // MARK: - On-screen cursor directions through the whole chain

    func testCursorAboveProducesUpwardRenderedMotion() {
        let controller = engagedController()
        let gaze = settleGaze(controller, cursor: CGPoint(x: 0, y: 100))
        XCTAssertGreaterThan(gaze.dy, 0.5, "cursor above must yield up-positive gazeY")

        let params = WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(state: .curious, gaze: gaze)
        ))
        XCTAssertGreaterThan(params.gazeY, 0.5)

        let renderSize = CGSize(width: 143.9, height: 143.9)
        let eyeY = WarawaraLayeredGeometry.gazeOffset(
            axis: .y, gaze: params.gazeY, range: 0.012, renderSize: renderSize
        )
        let face = WarawaraTurnGeometry.faceTransform(
            yawDegrees: params.yawDegrees, pitchDegrees: params.pitchDegrees
        )
        XCTAssertLessThan(eyeY, 0, "eyes must move UP (negative SwiftUI y)")
        XCTAssertLessThan(face.offsetYFrac, 0, "face must move UP")
        XCTAssertGreaterThan(params.pitchDegrees, 0, "cursor above must pitch up")
    }

    func testCursorBelowProducesDownwardRenderedMotion() {
        let controller = engagedController()
        let gaze = settleGaze(controller, cursor: CGPoint(x: 0, y: -100))
        XCTAssertLessThan(gaze.dy, -0.5, "cursor below must yield down-positive gazeY")

        let params = WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(state: .curious, gaze: gaze)
        ))
        XCTAssertLessThan(params.pitchDegrees, 0, "cursor below must pitch down")
        let renderSize = CGSize(width: 143.9, height: 143.9)
        let eyeY = WarawaraLayeredGeometry.gazeOffset(
            axis: .y, gaze: params.gazeY, range: 0.012, renderSize: renderSize
        )
        XCTAssertGreaterThan(eyeY, 0, "eyes must move DOWN (positive SwiftUI y)")
    }

    func testCursorLeftAndRightProduceCorrectHorizontalMotion() {
        let controller = engagedController()

        let leftGaze = settleGaze(controller, cursor: CGPoint(x: -100, y: 0))
        XCTAssertLessThan(leftGaze.dx, -0.5)
        let leftParams = WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(state: .curious, gaze: leftGaze)
        ))
        XCTAssertLessThan(leftParams.yawDegrees, 0, "cursor left must yaw left")
        let leftFace = WarawaraTurnGeometry.faceTransform(
            yawDegrees: leftParams.yawDegrees, pitchDegrees: 0
        )
        XCTAssertLessThan(leftFace.offsetXFrac, 0, "face rides left")

        let rightGaze = settleGaze(controller, cursor: CGPoint(x: 100, y: 0))
        XCTAssertGreaterThan(rightGaze.dx, 0.5)
        let rightParams = WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(state: .curious, gaze: rightGaze)
        ))
        XCTAssertGreaterThan(rightParams.yawDegrees, 0, "cursor right must yaw right")
        let rightFace = WarawaraTurnGeometry.faceTransform(
            yawDegrees: rightParams.yawDegrees, pitchDegrees: 0
        )
        XCTAssertGreaterThan(rightFace.offsetXFrac, 0, "face rides right")
        // Mirror symmetry of the shared facial remap.
        XCTAssertEqual(leftFace.offsetXFrac, -rightFace.offsetXFrac, accuracy: 0.0001)
        XCTAssertEqual(leftFace.scaleX, rightFace.scaleX, accuracy: 0.0001)
    }

    // MARK: - Face/body hierarchy

    func testFaceRidesNearSideBeyondEyeLocalGaze() {
        let renderSize = CGSize(width: 143.9, height: 143.9)
        let face = WarawaraTurnGeometry.faceTransform(yawDegrees: 25, pitchDegrees: 0)
        let faceX = face.offsetXFrac * renderSize.width
        let eyeX = WarawaraLayeredGeometry.gazeOffset(axis: .x, gaze: 1, range: 0.012, renderSize: renderSize)
        XCTAssertGreaterThan(faceX, eyeX, "shared face motion must exceed eye-local gaze")
        XCTAssertGreaterThan(eyeX, 0)
    }

    func testFaceAndBodyWarpShareTheYawDirection() {
        let canvas = CGSize(width: 143.9, height: 143.9)
        let bounds = CGRect(x: 0.10, y: 0.09, width: 0.80, height: 0.82)
        for yaw in [CGFloat(-25), -10, 10, 25] {
            let face = WarawaraTurnGeometry.faceTransform(yawDegrees: yaw, pitchDegrees: 0)
            let strips = WarawaraTurnGeometry.strips(
                count: 14, canvasSize: canvas, bodyBounds: bounds,
                yawDegrees: yaw, pitchDegrees: 0
            )
            // Face offset and silhouette redistribution must agree on the
            // turn direction.
            XCTAssertEqual(face.offsetXFrac * yaw >= 0, true, "face must ride the near side")
            XCTAssertGreaterThan(
                strips.last!.destination.width - strips.first!.destination.width,
                yaw > 0 ? 0 : -100,
                "silhouette must redistribute toward the turn"
            )
            if yaw < 0 {
                XCTAssertLessThan(strips.last!.destination.width, strips.first!.destination.width)
            }
        }
    }

    func testHeldGazeStaysStableThroughDriver() {
        let model = WarawaraExpressionDriverModel()
        let inputs = WarawaraExpressionInputs(state: .curious, gaze: CGVector(dx: 0, dy: 0.7))
        let start = 5000.0
        for frame in 0..<90 {
            model.tick(at: Date(timeIntervalSinceReferenceDate: start + Double(frame) / 30.0), inputs: inputs)
        }
        let converged = model.parameters
        XCTAssertEqual(converged.gazeY, 0.7, accuracy: 0.05)
        XCTAssertEqual(converged.gazeX, 0, accuracy: 0.05)
        for frame in 90..<180 {
            model.tick(at: Date(timeIntervalSinceReferenceDate: start + Double(frame) / 30.0), inputs: inputs)
        }
        XCTAssertEqual(model.parameters.gazeY, converged.gazeY, accuracy: 0.005)
        XCTAssertEqual(model.parameters.bodyTilt, converged.bodyTilt, accuracy: 0.005)
    }

    func testCuriousExitReturnsSmoothlyToNeutral() {
        let model = WarawaraExpressionDriverModel()
        let curious = WarawaraExpressionInputs(state: .curious, gaze: CGVector(dx: 0.7, dy: 0.3))
        let start = 5000.0
        for frame in 0..<90 {
            model.tick(at: Date(timeIntervalSinceReferenceDate: start + Double(frame) / 30.0), inputs: curious)
        }
        XCTAssertGreaterThan(model.parameters.gazeX, 0.5, "gaze must be engaged before exit")

        let idle = WarawaraExpressionInputs(state: .idle)
        var previous = abs(model.parameters.gazeX)
        var steps = 0
        for frame in 90..<180 {
            model.tick(at: Date(timeIntervalSinceReferenceDate: start + Double(frame) / 30.0), inputs: idle)
            let current = abs(model.parameters.gazeX)
            XCTAssertLessThanOrEqual(current, previous + 0.0001, "return must be monotonic")
            if current < previous - 0.0001 { steps += 1 }
            previous = current
        }
        XCTAssertGreaterThan(steps, 5, "return must be gradual, not a snap")
        XCTAssertEqual(model.parameters.gazeX, 0, accuracy: 0.02)
        XCTAssertEqual(model.parameters.bodyTilt, 0, accuracy: 0.005)
        XCTAssertEqual(model.parameters.bodySquashX, 1, accuracy: 0.005)
    }
}


