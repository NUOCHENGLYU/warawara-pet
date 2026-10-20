import AppKit
import XCTest
@testable import WarawaraPet

/// The daily 22:17 meteor's gentle wake: a FORMAL state-machine
/// transition (sleepy/sleeping -> idle), sleep-evaluator suppression for
/// the event, and a natural drift back to sleep afterwards. Normal
/// system wakes never touch this path.
final class PetEventWakeTests: XCTestCase {
    private final class FixedIdle: SystemIdleTimeProviding {
        var idleSeconds: TimeInterval = 0
        func secondsSinceLastUserActivity() -> TimeInterval { idleSeconds }
    }

    private let idle = FixedIdle()

    private func makeController() -> PetController {
        let windowController = PetWindowController()
        windowController.configureForTesting(frame: CGRect(x: 400, y: 300, width: 200, height: 226))
        let motion = PetMotionController(windowController: windowController)
        let controller = PetController(
            windowController: windowController,
            motionController: motion,
            positionStore: PetPositionStore()
        )
        controller.idleTimeProvider = idle
        controller.mouseLocationProvider = { CGPoint(x: 5000, y: 5000) }
        return controller
    }

    private func putToSleep(_ controller: PetController) {
        idle.idleSeconds = 600
        controller.awarenessTick(at: 0)
        controller.awarenessTick(at: 1)
        XCTAssertEqual(controller.state, .sleeping)
    }

    func testWakeGentlyTransitionsSleepingToIdleThroughTheStateMachine() {
        let controller = makeController()
        putToSleep(controller)
        controller.wakeGentlyForEvent()
        XCTAssertEqual(controller.state, .idle,
                       "the gentle wake goes through the formal transition")
        XCTAssertTrue(controller.sleepSuppressionActive,
                      "the event wake suppresses the sleep evaluator")
    }

    func testWakeGentlyTransitionsSleepyToIdle() {
        let controller = makeController()
        idle.idleSeconds = 300
        controller.awarenessTick(at: 0)
        XCTAssertEqual(controller.state, .sleepy)
        controller.wakeGentlyForEvent()
        XCTAssertEqual(controller.state, .idle)
    }

    func testWakeGentlyIsInertForAwakeStatesButStillSuppresses() {
        let controller = makeController()
        XCTAssertEqual(controller.state, .idle)
        controller.wakeGentlyForEvent()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(controller.sleepSuppressionActive)
    }

    func testSuppressionKeepsThePetAwakeForTheWholePerformance() {
        let controller = makeController()
        putToSleep(controller)
        controller.wakeGentlyForEvent()
        XCTAssertEqual(controller.state, .idle)

        // The user is still away (huge system idle): without the
        // suppression the pet would fall asleep again immediately.
        idle.idleSeconds = 3600
        for tick in 0..<40 {
            controller.awarenessTick(at: TimeInterval(tick) * 0.5)
        }
        XCTAssertEqual(controller.state, .idle,
                       "the pet stays awake for the meteor performance")
    }

    func testEndEventWakeReleasesAndThePetDriftsBackToSleep() {
        let controller = makeController()
        putToSleep(controller)
        controller.wakeGentlyForEvent()
        controller.endEventWake()
        XCTAssertFalse(controller.sleepSuppressionActive)

        idle.idleSeconds = 3600
        controller.awarenessTick(at: 100)
        XCTAssertEqual(controller.state, .sleepy,
                       "once the event ends the pet drifts back toward sleep naturally")
    }

    func testNormalSleepPathStillRequiresTheGentleWake() {
        // Regression guard: a normal wake path must NOT silently wake the
        // pet — sleeping is only exited via the formal event wake, click
        // or drag.
        let controller = makeController()
        putToSleep(controller)
        controller.awarenessTick(at: 200)
        XCTAssertEqual(controller.state, .sleeping)
        XCTAssertFalse(controller.sleepSuppressionActive)
    }
}
