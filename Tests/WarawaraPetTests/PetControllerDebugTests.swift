import XCTest
@testable import WarawaraPet

private final class DebugFakeIdleTimeProvider: SystemIdleTimeProviding {
    var idleSeconds: TimeInterval = 0
    func secondsSinceLastUserActivity() -> TimeInterval { idleSeconds }
}

final class PetControllerDebugTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var heldWindowController: PetWindowController?
    private let idle = DebugFakeIdleTimeProvider()

    override func setUp() {
        super.setUp()
        suiteName = "PetControllerDebugTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        heldWindowController = nil
        super.tearDown()
    }

    private func makeController() -> PetController {
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
        return controller
    }

    func testForceHopFromSleeping() {
        let controller = makeController()
        controller.forceSleeping()
        XCTAssertEqual(controller.state, .sleeping)

        controller.forceHop()
        XCTAssertEqual(controller.state, .hop)
    }

    func testForceFloatUsesProductionPathAndPreservesInterruption() {
        let controller = makeController()
        controller.forceSleeping()
        controller.forceFloat()
        XCTAssertEqual(controller.state, .float)

        // Click interruption semantics are intact for a forced float.
        controller.handleClick()
        XCTAssertEqual(controller.state, .clicked)
        controller.completeClickReaction()
        XCTAssertEqual(controller.state, .settling)
    }

    func testForceCuriousTracksThenExitsNormallyWhenPointerLeaves() {
        let controller = makeController()
        controller.mouseLocationProvider = { CGPoint(x: 10, y: 10) }
        controller.forceCurious()
        XCTAssertEqual(controller.state, .curious)

        // The tracker drives the pose while forced.
        controller.mouseLocationProvider = { CGPoint(x: 200, y: 10) }
        controller.curiosityTrackingTick(at: 100)
        controller.curiosityTrackingTick(at: 100.1)
        XCTAssertNotEqual(controller.curiosityPose, .neutral)

        // Normal exit rules still apply.
        controller.mouseLocationProvider = { CGPoint(x: 5000, y: 5000) }
        controller.awarenessTick(at: 100.2, evaluateSleepiness: false)
        XCTAssertEqual(controller.state, .idle)
    }

    func testForcedSleepPersistsUntilInteractionAndThenNaturalSleepinessResumes() {
        let controller = makeController()
        idle.idleSeconds = 10  // active user; natural sleepiness would not fire

        controller.forceSleepy()
        XCTAssertEqual(controller.state, .sleepy)
        controller.awarenessTick(at: 100)
        XCTAssertEqual(controller.state, .sleepy)  // override holds

        controller.forceSleeping()
        XCTAssertEqual(controller.state, .sleeping)
        controller.awarenessTick(at: 101)
        XCTAssertEqual(controller.state, .sleeping)

        // Interaction wakes and clears the debug override.
        controller.handleClick()
        XCTAssertEqual(controller.state, .clicked)
        controller.completeClickReaction()
        XCTAssertEqual(controller.state, .idle)

        // Natural sleepiness works again.
        idle.idleSeconds = 300
        controller.awarenessTick(at: 102)
        XCTAssertEqual(controller.state, .sleepy)
    }
}
