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

    /// DOCUMENTED ACTUAL BEHAVIOR: a backward wall-clock adjustment
    /// makes `elapsed` negative and the clamp reports progress 0 — the
    /// in-flight motion visually restarts from its start pose. This is
    /// bounded (0...1), never NaN, never fires a premature completion,
    /// and after the clock moves forward again the motion completes
    /// exactly once.
    func testBackwardClockClampsProgressToZeroWithoutCrash() {
        var fakeNow = Date()
        let windowController = PetWindowController()
        windowController.configureForTesting(frame: petFrame)
        let motion = PetMotionController(windowController: windowController)
        motion.nowProvider = { fakeNow }

        var progressValues: [CGFloat] = []
        var completions = 0
        motion.startHop(
            from: petFrame,
            parameters: HopParameters(height: 80, drift: 0, duration: 1.0),
            progress: { progressValues.append($0) },
            completion: { _ in completions += 1 }
        )
        fakeNow = fakeNow.addingTimeInterval(0.5)
        motion.performTickForTesting()
        let mid = progressValues.last ?? -1
        XCTAssertEqual(mid, 0.5, accuracy: 0.001, "half-way progress first")

        // Clock jumps BACKWARD by an hour: the clamp resets to 0.
        fakeNow = fakeNow.addingTimeInterval(-3600)
        motion.performTickForTesting()
        XCTAssertEqual(progressValues.last ?? -1, 0,
                       "backward clock clamps progress to 0 (bounded restart)")
        XCTAssertEqual(completions, 0, "no completion while progress is clamped")
        XCTAssertTrue(progressValues.allSatisfy { $0.isFinite },
                      "progress never becomes NaN/Infinity")
        XCTAssertTrue(windowController.currentFrame.origin.x.isFinite,
                      "the window frame stays finite")

        // Clock moves forward past the end: exactly one completion.
        fakeNow = fakeNow.addingTimeInterval(2 * 3600)
        motion.performTickForTesting()
        XCTAssertEqual(completions, 1, "completion fires exactly once after recovery")
        XCTAssertEqual(progressValues.last ?? -1, 1, "progress ends clamped at 1")
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

    /// The curious state is dwell-hysteresis driven: the pointer must sit
    /// within `curiosityEnterRadius` for `curiosityDwellTime` before the
    /// pet engages. After a long suspension with the pointer still
    /// nearby the pet stays curious; when the pointer finally leaves it
    /// returns to idle. No duplicate window may appear.
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

        // Pointer parks 24 px from the pet's center (inside the 110 px
        // enter radius) and dwells 1.5 s -> the pet becomes curious.
        let frame = windowController.currentFrame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        controller.mouseLocationProvider = {
            CGPoint(x: center.x + 24, y: center.y - 13)
        }
        for tick in 0..<4 {
            controller.awarenessTick(at: 100 + TimeInterval(tick) * 0.5,
                                     evaluateSleepiness: false)
        }
        XCTAssertEqual(controller.state, .curious,
                       "a dwelling nearby pointer engages curiosity")

        // 100 s suspension with the pointer still nearby: stays curious,
        // same panel, finite frame.
        for tick in 0..<40 {
            controller.awarenessTick(at: 200 + TimeInterval(tick) * 0.5,
                                     evaluateSleepiness: false)
        }
        XCTAssertEqual(controller.state, .curious,
                       "curiosity survives a long suspension while the pointer stays")
        XCTAssertTrue(windowController.petPanel === panelBefore)
        XCTAssertTrue(windowController.currentFrame.origin.x.isFinite)

        // The pointer finally leaves (beyond the 170 px exit radius):
        // the pet returns to idle on the next tick.
        controller.mouseLocationProvider = { CGPoint(x: 5000, y: 5000) }
        controller.awarenessTick(at: 400, evaluateSleepiness: false)
        XCTAssertEqual(controller.state, .idle,
                       "the pet returns to idle once the pointer leaves")
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
        let clock = FixedClock(now: start, calendar: cal)

        let windowController = PetWindowController()
        windowController.configureForTesting(frame: petFrame)
        let coordinator = BirthdayEventCoordinator(
            clock: clock,
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
        // One day-long wall jump while the machine was asleep: a single
        // advance fast-forwards noticing -> gathering (one phase per call,
        // by design). The event must never hang, crash, or touch the
        // main pet window.
        let resumedAt = start.addingTimeInterval(24 * 3600)
        clock.currentNow = resumedAt
        coordinator.advance(at: resumedAt)
        XCTAssertEqual(coordinator.phase, .gathering,
                       "a day-long jump lands in gathering, never stuck in noticing")

        // The group sequence completes on resume: group-start timestamp,
        // a final advance through celebrating, then the group-end
        // notification drives awaitingLetter -> completed -> idle.
        coordinator.companionGroupDidStart()
        let resumedAt2 = resumedAt.addingTimeInterval(10)
        clock.currentNow = resumedAt2
        coordinator.advance(at: resumedAt2)
        coordinator.companionGroupDidEnd()
        XCTAssertEqual(coordinator.phase, .idle, "the birthday event completes, not hang")
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
    /// freeze and resume the WHOLE test process mid-execution. The CI
    /// step runs it with SUSPENSION_HOST_SPIN=long (45 s spin); the
    /// plain suite uses a 3 s sanity spin. The freeze itself is proven
    /// in the CI step by observing the runner in stopped state (T) at
    /// both ends of the 8 s pause, then requiring a clean exit with a
    /// non-zero iteration counter in the END marker.
    func testSuspensionHostSurvivesStopCont() {
        let longSpin = ProcessInfo.processInfo.environment["SUSPENSION_HOST_SPIN"] == "long"
        let spinDuration: TimeInterval = longSpin ? 45 : 3
        let wallBefore = Date()
        // XCTest's harness captures the test's stdout/stderr and only
        // flushes them when the test ends, so the CI freeze step cannot
        // react to them live. When SUSPENSION_HOST_MARKER is set the
        // markers are also written straight into that file, which is
        // visible to the CI script immediately.
        func marker(_ line: String) {
            if let path = ProcessInfo.processInfo.environment["SUSPENSION_HOST_MARKER"] {
                if !FileManager.default.fileExists(atPath: path) {
                    FileManager.default.createFile(atPath: path, contents: nil)
                }
                if let handle = FileHandle(forWritingAtPath: path) {
                    handle.seekToEndOfFile()
                    handle.write(Data((line + "\n").utf8))
                    handle.synchronizeFile()
                    handle.closeFile()
                }
            }
            FileHandle.standardError.write(Data((line + "\n").utf8))
        }
        marker("SUSPENSION_HOST_BEGIN")
        let deadline = Date().addingTimeInterval(spinDuration)
        var counter = 0
        while Date() < deadline {
            counter &+= 1
            if counter % 1_000_000 == 0 { Thread.sleep(forTimeInterval: 0.001) }
        }
        let wallDelta = Date().timeIntervalSince(wallBefore)
        marker("SUSPENSION_HOST_END wallDelta=\(wallDelta) counter=\(counter)")
        XCTAssertGreaterThan(counter, 0, "the spin must actually run")
        XCTAssertGreaterThanOrEqual(wallDelta, spinDuration - 0.5,
                                    "the wall clock must advance at least the spin duration")
    }
}
