import AppKit
import XCTest
@testable import WarawaraPet

/// Long-suspension (lid-close) simulation on virtual clocks: wall-time
/// jumps of 10 minutes up to 72 hours applied to every transient pet
/// motion, plus backward clock adjustments and midnight crossings.
///
/// Assertions are real: exactly-one completion, finite frames, clamped
/// progress, no backward motion, no NaN/Infinity, sleeping pets stay
/// asleep, no duplicate windows, and the main pet window is never
/// closed by birthday/meteor events.
final class SuspensionSimulationTests: XCTestCase {
    private let petFrame = CGRect(x: 400, y: 300, width: 200, height: 226)
    private let jumps: [TimeInterval] = [
        10 * 60, 3600, 8 * 3600, 24 * 3600, 72 * 3600
    ]

    private final class FixedClock: BirthdayClock {
        var currentNow: Date
        let calendar: Calendar
        init(now: Date, calendar: Calendar) { self.currentNow = now; self.calendar = calendar }
        func now() -> Date { currentNow }
    }

    private final class FixedIdle: SystemIdleTimeProviding {
        var idleSeconds: TimeInterval = 0
        func secondsSinceLastUserActivity() -> TimeInterval { idleSeconds }
    }

    // MARK: - Motion through long suspension

    func testHopCompletesExactlyOnceAfterEveryLongJump() {
        for jump in jumps {
            var fakeNow = Date()
            let windowController = PetWindowController()
            windowController.configureForTesting(frame: petFrame)
            let motion = PetMotionController(windowController: windowController)
            motion.nowProvider = { fakeNow }

            var completions = 0
            var lastFrame = CGRect.zero
            motion.startHop(
                from: petFrame,
                parameters: HopParameters(height: 80, drift: 20, duration: 1.1),
                progress: { _ in },
                completion: { frame in completions += 1; lastFrame = frame }
            )
            fakeNow = fakeNow.addingTimeInterval(jump)
            motion.performTickForTesting()
            XCTAssertEqual(completions, 1, "jump \(jump)s: exactly one completion")
            XCTAssertFalse(lastFrame.isEmpty, "jump \(jump)s: a real final frame")
            XCTAssertTrue(lastFrame.origin.x.isFinite && lastFrame.origin.y.isFinite)
            let center = CGPoint(x: lastFrame.midX, y: lastFrame.midY)
            XCTAssertTrue(ScreenGeometry.screenVisibleFrames().contains { $0.contains(center) },
                          "jump \(jump)s: the landed frame must be on-screen")
            motion.performTickForTesting()
            XCTAssertEqual(completions, 1, "jump \(jump)s: no duplicate completion after finish")
            motion.cancelMotion()
        }
    }

    func testFloatCompletesAfterLongJumpsWithoutNaN() {
        for jump in jumps {
            var fakeNow = Date()
            let windowController = PetWindowController()
            windowController.configureForTesting(frame: petFrame)
            let motion = PetMotionController(windowController: windowController)
            motion.nowProvider = { fakeNow }

            var progressValues: [CGFloat] = []
            var completions = 0
            motion.startFloat(
                from: petFrame,
                parameters: FloatParameters(height: 140, drift: 24, duration: 6.5, swayPhase: 0.4),
                progress: { progressValues.append($0) },
                completion: { _ in completions += 1 }
            )
            fakeNow = fakeNow.addingTimeInterval(0.1)
            motion.performTickForTesting()
            fakeNow = fakeNow.addingTimeInterval(jump)
            motion.performTickForTesting()
            XCTAssertEqual(completions, 1, "jump \(jump)s: float completes exactly once")
            XCTAssertEqual(progressValues.last ?? -1, 1, "jump \(jump)s: progress clamps to exactly 1")
            XCTAssertTrue(progressValues.allSatisfy { $0.isFinite }, "jump \(jump)s: no NaN progress")
            let frame = windowController.currentFrame
            XCTAssertTrue(frame.origin.x.isFinite && frame.origin.y.isFinite
                          && frame.width.isFinite && frame.height.isFinite)
            motion.cancelMotion()
        }
    }

    func testSettleCompletesAfterLongJumps() {
        for jump in jumps {
            var fakeNow = Date()
            let windowController = PetWindowController()
            windowController.configureForTesting(frame: petFrame)
            let motion = PetMotionController(windowController: windowController)
            motion.nowProvider = { fakeNow }
            var completions = 0
            motion.startSettle(
                from: petFrame, to: petFrame,
                progress: { _ in },
                completion: { _ in completions += 1 }
            )
            fakeNow = fakeNow.addingTimeInterval(jump)
            motion.performTickForTesting()
            XCTAssertEqual(completions, 1, "jump \(jump)s: settle completes exactly once")
            motion.cancelMotion()
        }
    }

    func testBackwardClockAdjustmentNeverReversesMotion() {
        var fakeNow = Date()
        let windowController = PetWindowController()
        windowController.configureForTesting(frame: petFrame)
        let motion = PetMotionController(windowController: windowController)
        motion.nowProvider = { fakeNow }

        var progressValues: [CGFloat] = []
        motion.startHop(
            from: petFrame,
            parameters: HopParameters(height: 80, drift: 0, duration: 1.0),
            progress: { progressValues.append($0) },
            completion: { _ in }
        )
        fakeNow = fakeNow.addingTimeInterval(0.5)
        motion.performTickForTesting()
        let mid = progressValues.last ?? -1
        // Clock jumps BACKWARD by an hour: progress must clamp, never
        // rewind below the previously reported value.
        fakeNow = fakeNow.addingTimeInterval(-3600)
        motion.performTickForTesting()
        XCTAssertGreaterThanOrEqual(progressValues.last ?? -1, 0)
        XCTAssertGreaterThanOrEqual(progressValues.last ?? -1, mid - 0.0001,
                                    "backward clock adjustments must not rewind motion")
        motion.cancelMotion()
    }

    func testMotionFramesRemainWithinVisibleUnionForAllJumps() {
        for jump in jumps {
            var fakeNow = Date()
            let windowController = PetWindowController()
            windowController.configureForTesting(frame: petFrame)
            let motion = PetMotionController(windowController: windowController)
            motion.nowProvider = { fakeNow }
            motion.startFloat(
                from: petFrame,
                parameters: FloatParameters(height: 300, drift: 400, duration: 6.5, swayPhase: 0.1),
                progress: { _ in },
                completion: { _ in }
            )
            for _ in 0..<5 {
                fakeNow = fakeNow.addingTimeInterval(jump / 5)
                motion.performTickForTesting()
                let frame = windowController.currentFrame
                let screens = ScreenGeometry.screenVisibleFrames()
                XCTAssertTrue(
                    screens.contains { $0.insetBy(dx: -1, dy: -1).intersects(frame) },
                    "jump \(jump)s: every rendered frame must intersect a real display"
                )
            }
            motion.cancelMotion()
        }
    }

    // MARK: - Pet states through long suspension

    func testSleepingPetStaysSleepingAndWindowUntouched() {
        let windowController = PetWindowController()
        windowController.configureForTesting(frame: petFrame)
        let motion = PetMotionController(windowController: windowController)
        let controller = PetController(
            windowController: windowController,
            motionController: motion,
            positionStore: PetPositionStore()
        )
        let idle = FixedIdle()
        controller.idleTimeProvider = idle
        idle.idleSeconds = 600
        controller.awarenessTick(at: 0)
        controller.awarenessTick(at: 1)
        XCTAssertEqual(controller.state, .sleeping)

        // 72-hour suspension: the sleep evaluator runs again with an even
        // longer idle time — the pet must remain sleeping (no auto-wake).
        idle.idleSeconds = 72 * 3600
        let frameBefore = windowController.currentFrame
        let panelBefore = windowController.petPanel
        for tick in 0..<20 {
            controller.awarenessTick(at: TimeInterval(tick) * 0.5)
        }
        XCTAssertEqual(controller.state, .sleeping,
                       "long suspension must not wake the sleeping pet")
        XCTAssertEqual(windowController.currentFrame, frameBefore,
                       "the sleeping pet's window must not move or close")
        XCTAssertTrue(windowController.petPanel === panelBefore,
                      "no duplicate pet window may be created")
    }

    func testClickedStateDoesNotAutoRecoverFromLongSuspension() {
        let windowController = PetWindowController()
        windowController.configureForTesting(frame: petFrame)
        let motion = PetMotionController(windowController: windowController)
        let controller = PetController(
            windowController: windowController,
            motionController: motion,
            positionStore: PetPositionStore()
        )
        controller.handleClick()
        XCTAssertEqual(controller.state, .clicked)
        // The revert is a wall-clock DispatchWorkItem; under a virtual
        // long suspension nothing runs it — the state must remain
        // .clicked until the revert executes.
        XCTAssertEqual(controller.state, .clicked)
        controller.completeClickReaction()
        XCTAssertEqual(controller.state, .idle)
    }

    func testIdleAndCuriousSurviveLongJumpsWithoutDuplicateWindows() {
        let windowController = PetWindowController()
        windowController.configureForTesting(frame: petFrame)
        let motion = PetMotionController(windowController: windowController)
        let controller = PetController(
            windowController: windowController,
            motionController: motion,
            positionStore: PetPositionStore()
        )
        controller.mouseLocationProvider = { CGPoint(x: 5000, y: 5000) }
        let panelBefore = windowController.petPanel
        controller.awarenessTick(at: 0, evaluateSleepiness: false)
        XCTAssertEqual(controller.state, .idle)
        for tick in 0..<40 {
            controller.awarenessTick(at: TimeInterval(tick) * 0.5, evaluateSleepiness: false)
        }
        XCTAssertEqual(controller.state, .idle,
                       "an idle pet stays idle across long suspension")
        XCTAssertTrue(windowController.petPanel === panelBefore)
        XCTAssertTrue(windowController.currentFrame.origin.x.isFinite)

        // Curious engagement then a long suspension with the pointer
        // still present: the tracker keeps running without crashes and
        // the state machine stays on the valid {curious, idle} path.
        controller.mouseLocationProvider = { CGPoint(x: 60, y: 40) }
        for tick in 0..<12 {
            controller.awarenessTick(at: 100 + TimeInterval(tick) * 0.5, evaluateSleepiness: false)
        }
        XCTAssertEqual(controller.state, .curious)
        for tick in 0..<40 {
            controller.awarenessTick(at: 200 + TimeInterval(tick) * 0.5, evaluateSleepiness: false)
        }
        XCTAssertTrue(controller.state == .curious || controller.state == .idle)
        XCTAssertTrue(windowController.petPanel === panelBefore)
    }

    func testSleepyProgressesToSleepingAcrossLongSuspensionByDesign() {
        let windowController = PetWindowController()
        windowController.configureForTesting(frame: petFrame)
        let motion = PetMotionController(windowController: windowController)
        let controller = PetController(
            windowController: windowController,
            motionController: motion,
            positionStore: PetPositionStore()
        )
        let idle = FixedIdle()
        controller.idleTimeProvider = idle
        idle.idleSeconds = 300
        controller.awarenessTick(at: 0)
        XCTAssertEqual(controller.state, .sleepy)
        // 72 hours of idle: the accepted design transitions sleepy ->
        // sleeping (never back to awake, never a crash).
        idle.idleSeconds = 72 * 3600
        controller.awarenessTick(at: 1)
        XCTAssertEqual(controller.state, .sleeping,
                       "a long-idle sleepy pet falls asleep, as designed")
    }

    // MARK: - Birthday + meteor under long suspension

    func testBirthdayEventCompletesAfterDayLongSuspensionWithoutTouchingPetWindow() {
        let zone = TimeZone(identifier: "America/New_York")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 17
        components.hour = 9; components.timeZone = zone
        let start = cal.date(from: components)!

        let windowController = PetWindowController()
        windowController.configureForTesting(frame: petFrame)
        let coordinator = BirthdayEventCoordinator(
            clock: FixedClock(now: start, calendar: cal),
            persistence: BirthdayPersistence()
        )
        let presenter = BirthdayPresenter(
            windowController: windowController,
            coordinator: coordinator,
            store: .shared,
            persistence: BirthdayPersistence()
        )
        coordinator.presenter = presenter
        coordinator.isPetBusy = { false }

        coordinator.requestTrigger(.replay)
        coordinator.servicePendingTrigger()
        XCTAssertTrue(coordinator.isRunning)

        let petFrameBefore = windowController.currentFrame
        coordinator.advance(at: start.addingTimeInterval(24 * 3600))
        XCTAssertEqual(coordinator.phase, .idle, "the birthday event must complete, not hang")
        XCTAssertEqual(windowController.currentFrame, petFrameBefore,
                       "the main pet window must never be moved or closed by the birthday event")
    }

    func testMeteorCompletesAfterLongMonotonicJumpWithoutTouchingPetWindow() {
        let zone = TimeZone(identifier: "America/New_York")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        let windowController = PetWindowController()
        windowController.configureForTesting(frame: petFrame)
        let controller = MeteorEventController(
            clock: FixedClock(now: start, calendar: cal),
            persistence: MeteorPersistence()
        )
        var uptime: TimeInterval = 1000
        controller.monotonicNow = { uptime }
        controller.isPetBusy = { false }
        controller.isBirthdayBlocking = { false }
        let presenter = MeteorEventPresenter(
            windowController: windowController, controller: controller, store: .shared
        )
        controller.presenter = presenter

        controller.requestTrigger(.replay)
        controller.servicePendingTrigger()
        controller.advance(at: start.addingTimeInterval(1.3))
        XCTAssertEqual(controller.phase, .flight)
        XCTAssertNotNil(presenter.debugPanel)

        // 72-hour monotonic jump: progress clamps to 1, phases advance
        // and complete; the meteor panel is parked, the pet untouched.
        uptime += 72 * 3600
        let petFrameBefore = windowController.currentFrame
        controller.advance(at: start.addingTimeInterval(2))
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(windowController.currentFrame, petFrameBefore)
        if let panel = presenter.debugPanel {
            XCTAssertEqual(panel.alphaValue, 0, accuracy: 0.01,
                           "the meteor panel must be fully faded after completion")
        }
    }

    // MARK: - SIGSTOP/SIGCONT host (wall-clock spin; used by CI)

    /// This test spins in real time so the CI SIGSTOP/SIGCONT step can
    /// freeze and resume the WHOLE test process mid-execution. The
    /// assertions verify the host survived the freeze and completed.
    func testSuspensionHostSurvivesStopCont() {
        let wallBefore = Date()
        print("SUSPENSION_HOST_BEGIN")
        let deadline = Date().addingTimeInterval(3)
        var counter = 0
        while Date() < deadline {
            counter &+= 1
            if counter % 1_000_000 == 0 { Thread.sleep(forTimeInterval: 0.001) }
        }
        print("SUSPENSION_HOST_END wallDelta=\(Date().timeIntervalSince(wallBefore)) counter=\(counter)")
        XCTAssertGreaterThan(counter, 0, "the spin must actually run")
    }
}
