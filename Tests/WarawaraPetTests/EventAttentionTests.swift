import XCTest
@testable import WarawaraPet

/// Sustained event attention regression coverage: the pet must HOLD,
/// TRACK, and RELEASE event-driven attention across many frames without
/// the autonomous curiosity loop overriding it (the one-frame flicker).
final class EventAttentionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var heldWindowController: PetWindowController?
    private let idle = FakeIdleTimeProvider()

    override func setUp() {
        super.setUp()
        suiteName = "EventAttentionTests.\(UUID().uuidString)"
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
        // Default: mouse far away so autonomous curiosity disengages.
        controller.mouseLocationProvider = { CGPoint(x: 5000, y: 5000) }
        return controller
    }

    func testEventAttentionSurvivesRepeatedAwarenessTicks() {
        // Regression: the 150 ms awareness tick used to pull the pet out
        // of curious within one tick (~one frame) after event attention
        // acquisition.
        let controller = makeController()
        let direction = CGVector(dx: -0.5, dy: -0.2)

        controller.setEventAttention(direction)
        XCTAssertEqual(controller.state, .curious)
        XCTAssertEqual(controller.curiosityDirection, direction)

        // Many awareness ticks while the mouse stays far away: the event
        // must keep owning the gaze.
        for tick in 0..<40 {
            controller.awarenessTick(at: TimeInterval(tick))
            XCTAssertEqual(controller.state, .curious, "tick \(tick): attention must be sustained")
            XCTAssertEqual(controller.curiosityDirection, direction,
                           "tick \(tick): event gaze must not be zeroed")
            XCTAssertEqual(controller.eventAttentionDirection, direction)
        }
    }

    func testEventAttentionTracksMovingTargetAcrossFrames() {
        let controller = makeController()
        controller.setEventAttention(CGVector(dx: -0.8, dy: 0.1))

        var previous = CGVector(dx: -0.8, dy: 0.1)
        var target = previous
        for step in 1...30 {
            // Simulate a moving prop (e.g., paper airplane): direction
            // sweeps from left-down to right-up.
            let t = CGFloat(step) / 30.0
            target = CGVector(dx: -0.8 + 1.6 * t, dy: 0.1 + 0.5 * t)
            controller.updateEventAttention(target)
            XCTAssertEqual(controller.curiosityDirection, target,
                           "tracking step \(step): gaze must follow the prop")
            previous = target
        }
        XCTAssertEqual(previous, target)
        XCTAssertEqual(controller.state, .curious, "tracking must not exit curious")
    }

    func testAutonomousCuriosityNeverOverridesEventAttention() {
        let controller = makeController()
        // Mouse curiosity engages FIRST (close mouse + dwell elapsed).
        controller.mouseLocationProvider = { CGPoint(x: 60, y: 40) }
        for tick in 0..<12 {
            controller.awarenessTick(at: TimeInterval(tick) * 0.5, evaluateSleepiness: false)
        }
        XCTAssertEqual(controller.state, .curious, "mouse curiosity engaged first")

        // The event takes over ownership while the mouse is still close.
        let eventDirection = CGVector(dx: -0.45, dy: -0.1)
        controller.setEventAttention(eventDirection)

        // Keep ticking the autonomous loops with an engaged mouse: the
        // event gaze must win on every frame.
        for tick in 0..<20 {
            controller.awarenessTick(at: 6 + TimeInterval(tick) * 0.15, evaluateSleepiness: false)
            controller.curiosityTrackingTick(at: 6 + TimeInterval(tick) * 0.15)
            XCTAssertEqual(controller.curiosityDirection, eventDirection,
                           "tick \(tick): event gaze must win over mouse curiosity")
            XCTAssertEqual(controller.eventAttentionDirection, eventDirection)
        }
        XCTAssertEqual(controller.state, .curious)
    }

    func testReleaseReturnsToIdleAndClearsGaze() {
        let controller = makeController()
        controller.setEventAttention(CGVector(dx: 0.4, dy: 0.3))
        XCTAssertTrue(controller.isEventAttentionActive)

        controller.setEventAttention(nil)
        XCTAssertFalse(controller.isEventAttentionActive)
        XCTAssertNil(controller.eventAttentionDirection)
        XCTAssertEqual(controller.curiosityDirection, .zero)
        XCTAssertEqual(controller.state, .idle)
    }

    func testAcquisitionOverActiveMouseCuriosityThenRelease() {
        let controller = makeController()
        controller.mouseLocationProvider = { CGPoint(x: 60, y: 40) }
        for tick in 0..<12 {
            controller.awarenessTick(at: TimeInterval(tick) * 0.5, evaluateSleepiness: false)
        }
        XCTAssertEqual(controller.state, .curious, "mouse curiosity engaged first")

        // Event takes over ownership while already curious.
        let eventDirection = CGVector(dx: -0.6, dy: 0.2)
        controller.setEventAttention(eventDirection)
        XCTAssertEqual(controller.curiosityDirection, eventDirection)

        // Mouse leaves: with event ownership the state must NOT exit.
        controller.mouseLocationProvider = { CGPoint(x: 5000, y: 5000) }
        for tick in 0..<10 {
            controller.awarenessTick(at: 6 + TimeInterval(tick) * 0.2, evaluateSleepiness: false)
            XCTAssertEqual(controller.state, .curious)
        }

        controller.setEventAttention(nil)
        XCTAssertEqual(controller.state, .idle)
    }
}

private final class FakeIdleTimeProvider: SystemIdleTimeProviding {
    var idleSeconds: TimeInterval = 0
    func secondsSinceLastUserActivity() -> TimeInterval { idleSeconds }
}
