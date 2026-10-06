import XCTest
@testable import WarawaraPet

private final class FakeIdleTimeProvider: SystemIdleTimeProviding {
    var idleSeconds: TimeInterval = 0
    func secondsSinceLastUserActivity() -> TimeInterval { idleSeconds }
}

final class PetControllerPersonalityTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var heldWindowController: PetWindowController?
    private let idle = FakeIdleTimeProvider()

    override func setUp() {
        super.setUp()
        suiteName = "PetControllerPersonalityTests.\(UUID().uuidString)"
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
        heldWindowController = windowController  // PetController holds it weakly
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

    func testSystemInactivityLeadsToSleepyThenSleeping() {
        let controller = makeController()
        XCTAssertEqual(controller.state, .idle)

        idle.idleSeconds = 300
        controller.awarenessTick(at: 10)
        XCTAssertEqual(controller.state, .sleepy)

        idle.idleSeconds = 479
        controller.awarenessTick(at: 11)
        XCTAssertEqual(controller.state, .sleepy)

        idle.idleSeconds = 600
        controller.awarenessTick(at: 12)
        XCTAssertEqual(controller.state, .sleeping)
    }

    func testActivityResumesFromSleepy() {
        let controller = makeController()
        idle.idleSeconds = 300
        controller.awarenessTick(at: 10)
        XCTAssertEqual(controller.state, .sleepy)

        idle.idleSeconds = 30
        controller.awarenessTick(at: 11)
        XCTAssertEqual(controller.state, .idle)
    }

    func testClickWakesSleepingPet() {
        let controller = makeController()
        idle.idleSeconds = 600
        controller.awarenessTick(at: 10)
        controller.awarenessTick(at: 11)
        XCTAssertEqual(controller.state, .sleeping)

        controller.handleClick()
        XCTAssertEqual(controller.state, .clicked)

        controller.completeClickReaction()
        XCTAssertEqual(controller.state, .idle)
    }

    func testDragWakesSleepingPet() {
        let controller = makeController()
        idle.idleSeconds = 600
        controller.awarenessTick(at: 10)
        controller.awarenessTick(at: 11)
        XCTAssertEqual(controller.state, .sleeping)

        controller.handleDragBegan(grabVector: .zero)
        XCTAssertEqual(controller.state, .dragged)
    }

    func testCuriosityEngagesAfterDwellAndExitsWhenPointerLeaves() {
        let controller = makeController()
        // currentFrame is .zero (no panel), so the pet center is (0, 0).
        controller.mouseLocationProvider = { CGPoint(x: 10, y: 10) }

        var t: TimeInterval = 100
        for _ in 0..<10 {
            t += 0.15
            controller.awarenessTick(at: t, evaluateSleepiness: false)
        }
        XCTAssertEqual(controller.state, .curious)

        controller.mouseLocationProvider = { CGPoint(x: 5000, y: 5000) }
        t += 0.15
        controller.awarenessTick(at: t, evaluateSleepiness: false)
        XCTAssertEqual(controller.state, .idle)
    }

    func testCuriosityDwellSuppressesAutonomousScheduling() {
        let controller = makeController()
        controller.startAutonomousBehavior()
        XCTAssertTrue(controller.isAutonomousScheduled)

        // Pointer enters: dwell phase begins, autonomy is suppressed.
        controller.mouseLocationProvider = { CGPoint(x: 10, y: 10) }
        controller.awarenessTick(at: 100, evaluateSleepiness: false)
        XCTAssertFalse(controller.isAutonomousScheduled)

        // Pointer leaves again without engaging: scheduling resumes.
        controller.mouseLocationProvider = { CGPoint(x: 5000, y: 5000) }
        controller.awarenessTick(at: 100.15, evaluateSleepiness: false)
        XCTAssertTrue(controller.isAutonomousScheduled)
    }

    func testClickDuringFloatDescendsToBaseAfterReaction() {
        let controller = makeController()
        controller.beginFloat()
        XCTAssertEqual(controller.state, .float)

        controller.handleClick()
        XCTAssertEqual(controller.state, .clicked)

        controller.completeClickReaction()
        XCTAssertEqual(controller.state, .settling)
    }

    func testNormalClickRoundTripStillWorks() {
        let controller = makeController()
        controller.handleClick()
        XCTAssertEqual(controller.state, .clicked)
        controller.completeClickReaction()
        XCTAssertEqual(controller.state, .idle)
    }
}
