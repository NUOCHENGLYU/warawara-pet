import AppKit
import XCTest
@testable import WarawaraPet

private final class BottleModeIdleProvider: SystemIdleTimeProviding {
    var seconds: TimeInterval
    init(_ seconds: TimeInterval) { self.seconds = seconds }
    func secondsSinceLastUserActivity() -> TimeInterval { seconds }
}

/// Phase 8C acceptance: while the pet is a bottle it is NOT a pet.
/// No hop, no float, no curiosity, no sleep, no click squash, no drag
/// deformation, no new autonomous timers — and a single scheduler
/// resumes when the bottle form ends.
final class PetBottleModeTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PetBottleModeTests.\(UUID().uuidString)"
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
        let controller = PetController(
            windowController: windowController,
            motionController: motion,
            positionStore: store
        )
        controller.idleTimeProvider = BottleModeIdleProvider(3600)
        controller.mouseLocationProvider = {
            // Mouse far away: curiosity would otherwise engage.
            CGPoint(x: 2000, y: 2000)
        }
        return controller
    }

    func testBottleModeFreezesEveryAutonomousDriverForMinutes() {
        let controller = makeController()
        controller.startAutonomousBehavior()
        XCTAssertTrue(controller.isAutonomousScheduled)

        controller.setBottleModeActive(true)
        XCTAssertFalse(controller.isAutonomousScheduled,
                       "the autonomous hop/float timer is cancelled on entry")

        // Simulate MANY minutes of ticks: nothing may ever happen.
        var t: TimeInterval = 1000
        for _ in 0..<1200 {
            t += 0.15
            controller.awarenessTick(at: t, evaluateSleepiness: true)
            controller.curiosityTrackingTick(at: t)
        }
        XCTAssertEqual(controller.state, .idle, "no hop/float/curious/sleepy/sleeping")
        XCTAssertEqual(controller.curiosityDirection, .zero)
        XCTAssertFalse(controller.isAutonomousScheduled,
                       "no new autonomous timer may be scheduled in bottle mode")
    }

    func testBottleModeBlocksReschedulingFromEveryEntry() {
        let controller = makeController()
        controller.setBottleModeActive(true)
        // Every scheduling entry point is guarded — even direct calls.
        controller.startAutonomousBehavior()
        XCTAssertFalse(controller.isAutonomousScheduled)
        controller.beginFloat()
        XCTAssertEqual(controller.state, .idle, "float never begins in bottle mode")
        controller.performBirthdayHop()
        XCTAssertEqual(controller.state, .idle)
        controller.performCelebrationHop()
        XCTAssertEqual(controller.state, .idle)
        controller.setEventAttention(CGVector(dx: -1, dy: 0))
        XCTAssertEqual(controller.state, .idle, "no event attention in bottle mode")
        controller.wakeGentlyForEvent()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(controller.sleepSuppressionActive)
    }

    func testClickProducesNoSquashInBottleMode() {
        let controller = makeController()
        controller.setBottleModeActive(true)
        controller.handleClick()
        XCTAssertEqual(controller.state, .idle, "no click squash in bottle mode")
        controller.completeClickReaction()
        XCTAssertEqual(controller.state, .idle)
    }

    func testDragMovesWithoutDeformationInBottleMode() {
        let controller = makeController()
        controller.setBottleModeActive(true)
        controller.handleDragBegan(grabVector: CGVector(dx: 0, dy: 1))
        XCTAssertEqual(controller.state, .dragged)
        var t: TimeInterval = 1000
        for _ in 0..<30 {
            t += 0.016
            controller.handleDragMoved(deltaX: 20, deltaY: 0, at: t)
            controller.dragTick(at: t)
        }
        XCTAssertEqual(controller.dragDeformation, .neutral,
                       "dragging a bottle must not deform it")
        controller.handleDragEnded()
        XCTAssertEqual(controller.state, .idle,
                       "the bottle rests directly where it was dropped")
        XCTAssertEqual(controller.dragDeformation, .neutral)
    }

    func testExitingBottleModeRestoresExactlyOneScheduler() {
        let controller = makeController()
        controller.startAutonomousBehavior()
        controller.setBottleModeActive(true)
        XCTAssertFalse(controller.isAutonomousScheduled)
        controller.setBottleModeActive(false)
        XCTAssertTrue(controller.isAutonomousScheduled,
                      "the single autonomous scheduler resumes")
        // Re-entering and re-exiting never duplicates it: the scheduler
        // is one cancellable one-shot timer.
        controller.setBottleModeActive(true)
        controller.setBottleModeActive(false)
        XCTAssertTrue(controller.isAutonomousScheduled)
        // The sleep/curiosity machinery is restored too: with a long
        // idle time the pet legitimately drifts sleepy again — proof
        // the evaluator resumed.
        controller.awarenessTick(at: 2000, evaluateSleepiness: true)
        XCTAssertEqual(controller.state, .sleepy,
                       "the sleep evaluator resumes after the bottle form ends")
    }

    func testSleepinessNeverAdvancesInBottleMode() {
        let controller = makeController()
        controller.setBottleModeActive(true)
        controller.idleTimeProvider = BottleModeIdleProvider(9999)
        var t: TimeInterval = 1000
        for _ in 0..<200 {
            t += 0.15
            controller.awarenessTick(at: t, evaluateSleepiness: true)
        }
        XCTAssertEqual(controller.state, .idle,
                       "no sleepy/sleeping while the bottle form is up")
    }
}
