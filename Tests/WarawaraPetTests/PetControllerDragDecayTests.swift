import XCTest
@testable import WarawaraPet

final class PetControllerDragDecayTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PetControllerDragDecayTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeController() -> PetController {
        let windowController = PetWindowController()
        let motion = PetMotionController(windowController: windowController)
        let store = PetPositionStore(defaults: defaults)
        return PetController(
            windowController: windowController,
            motionController: motion,
            positionStore: store
        )
    }

    func testHeldStillDragRelaxesThroughTicksAndResumesOnMovement() {
        let controller = makeController()
        controller.handleDragBegan(grabVector: CGVector(dx: 0, dy: 1))
        XCTAssertEqual(controller.state, .dragged)

        var t: TimeInterval = 1000
        for _ in 0..<60 {
            t += 0.016
            controller.handleDragMoved(deltaX: 9.6, deltaY: 0, at: t)
        }
        let saturated = controller.dragDeformation
        XCTAssertGreaterThan(saturated.stretchScale, 1.3)

        // A tick within the decay start delay changes nothing.
        controller.dragTick(at: t + 0.03)
        XCTAssertEqual(controller.dragDeformation, saturated)

        // Ticks during the pause: monotonic relaxation toward neutral with
        // the grab anchor staying fixed.
        var previous = controller.dragDeformation
        for k in 1...12 {
            controller.dragTick(at: t + 0.1 * Double(k))
            let current = controller.dragDeformation
            XCTAssertLessThanOrEqual(current.stretchScale, previous.stretchScale)
            XCTAssertLessThanOrEqual(abs(current.rotation), abs(previous.rotation))
            XCTAssertEqual(current.anchor.dy, 0.84, accuracy: 0.0001)
            previous = current
        }
        XCTAssertEqual(controller.dragDeformation.stretchScale, 1, accuracy: 0.001)
        XCTAssertEqual(controller.dragDeformation.rotation, 0, accuracy: 0.001)

        // Movement resumes: deformation responds and saturates again.
        var maxObserved = controller.dragDeformation.stretchScale
        for _ in 0..<60 {
            t += 0.016
            controller.handleDragMoved(deltaX: 9.6, deltaY: 0, at: t)
            maxObserved = max(maxObserved, controller.dragDeformation.stretchScale)
        }
        XCTAssertLessThanOrEqual(maxObserved, 1 + DeformationTuning.default.maxStretch + 0.001)
        XCTAssertGreaterThan(controller.dragDeformation.stretchScale, 1.3)
    }

    func testDragEndStopsTheDecayTick() {
        let controller = makeController()
        controller.handleDragBegan(grabVector: CGVector(dx: 0, dy: 1))
        XCTAssertEqual(controller.state, .dragged)

        var t: TimeInterval = 1000
        for _ in 0..<60 {
            t += 0.016
            controller.handleDragMoved(deltaX: 9.6, deltaY: 0, at: t)
        }
        XCTAssertGreaterThan(controller.dragDeformation.stretchScale, 1.3)

        controller.handleDragEnded()
        XCTAssertEqual(controller.state, .settling)
        XCTAssertEqual(controller.dragDeformation, .neutral)

        // The tick is inert once dragging has ended.
        controller.dragTick(at: t + 5)
        XCTAssertEqual(controller.dragDeformation, .neutral)
    }
}
