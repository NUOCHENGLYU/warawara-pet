import AppKit
import XCTest
@testable import WarawaraPet

/// Meteor event coverage: independent world-space trajectory, complete
/// disappearance, phase sequencing (including the wish beat), attention
/// timing, automatic scheduling limits, and REAL presentation-path
/// visibility.
final class MeteorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "MeteorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func calendar(_ zone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int,
                      zone: TimeZone, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute
        components.timeZone = zone
        return calendar(zone).date(from: components)!
    }

    private final class FixedClock: BirthdayClock {
        var currentNow: Date
        let calendar: Calendar
        init(now: Date, calendar: Calendar) { self.currentNow = now; self.calendar = calendar }
        func now() -> Date { currentNow }
    }

    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)

    private func makeController(now: Date, zone: TimeZone, timing: MeteorEventController.Timing? = nil) -> MeteorEventController {
        let controller = MeteorEventController(
            clock: FixedClock(now: now, calendar: calendar(zone)),
            persistence: MeteorPersistence(defaults: defaults),
            timing: timing ?? MeteorEventController.Timing()
        )
        controller.isPetBusy = { false }
        controller.isBirthdayBlocking = { false }
        return controller
    }

    private final class SpyPresenter: MeteorEventPresenting {
        var visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        var noticeCount = 0
        var flightFrames: [CGFloat] = []
        var departedCount = 0
        var wishingCount = 0
        var celebrationCount = 0
        var cleanupCount = 0
        var phases: [MeteorPhase] = []
        var activeVisibleFrame: CGRect { visibleFrame }
        func noticeScene() { noticeCount += 1; phases.append(.noticing) }
        func flightDidBegin(trajectory: MeteorTrajectory) { phases.append(.flight) }
        func flightFrame(progress: CGFloat, at now: Date) { flightFrames.append(progress) }
        func meteorDeparted() { departedCount += 1; phases.append(.departed) }
        func wishingDidBegin() { wishingCount += 1; phases.append(.wishing) }
        func celebrationDidBegin() { celebrationCount += 1; phases.append(.celebration) }
        func cleanup() { cleanupCount += 1; phases.append(.completed) }
    }

    // MARK: - Trajectory

    func testTrajectoryEntersAndExitsBeyondTheDisplay() {
        let trajectory = MeteorTrajectory.fixed(in: visible)
        XCTAssertLessThan(trajectory.entry.x, visible.minX, "entry must be off-screen left")
        XCTAssertGreaterThan(trajectory.exit.x, visible.maxX, "exit must be off-screen right")
        let start = trajectory.position(at: 0)
        let end = trajectory.position(at: 1)
        XCTAssertLessThan(start.x, visible.minX)
        XCTAssertGreaterThan(end.x, visible.maxX)
        XCTAssertGreaterThan(end.y, visible.minY - 1)
        XCTAssertLessThan(end.y, visible.maxY)
        // The trajectory is fixed by the display, never by the pet.
        XCTAssertEqual(MeteorTrajectory.fixed(in: visible), trajectory)
    }

    func testFlightIntersectsTheDisplayThroughTheVisiblePhase() {
        let trajectory = MeteorTrajectory.fixed(in: visible)
        var sawOnScreen = false
        var previous = trajectory.position(at: 0)
        for step in 1...60 {
            let t = CGFloat(step) / 60
            let p = trajectory.position(at: t)
            if visible.contains(p) { sawOnScreen = true }
            let delta = hypot(p.x - previous.x, p.y - previous.y)
            XCTAssertLessThan(delta, 80, "no teleporting between 60 Hz samples")
            previous = p
        }
        XCTAssertTrue(sawOnScreen, "the meteor must cross the visible display")
    }

    // MARK: - Phase sequence + full disappearance

    func testPhaseSequenceIsNoticingFlightDepartedWishingCelebration() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = date(2026, 10, 1, 10, zone: zone)
        let controller = makeController(now: start, zone: zone)
        let spy = SpyPresenter()
        controller.presenter = spy

        controller.requestTrigger(.replay)
        controller.servicePendingTrigger()
        XCTAssertEqual(controller.phase, .noticing)

        let t = controller.timing
        let noticeEnd = start.addingTimeInterval(t.noticeDuration + 0.1)
        controller.advance(at: noticeEnd)
        XCTAssertEqual(controller.phase, .flight)
        XCTAssertNotNil(controller.trajectory)

        // Mid-flight renders increase progress; flight still active.
        for step in 1..<5 {
            controller.advance(at: start.addingTimeInterval(
                t.noticeDuration + t.flightDuration * Double(step) / 5
            ))
        }
        XCTAssertEqual(controller.phase, .flight)
        XCTAssertGreaterThan(spy.flightFrames.count, 0)

        // Flight ends: the meteor has FULLY left the display.
        let flightEnd = start.addingTimeInterval(t.noticeDuration + t.flightDuration + 0.1)
        controller.advance(at: flightEnd)
        XCTAssertEqual(controller.phase, .departed)
        XCTAssertEqual(spy.departedCount, 1, "departure registered, no celebration yet")
        XCTAssertEqual(spy.celebrationCount, 0, "no celebration immediately after departure")

        // The wish beat (constant duration) sits between departure and
        // celebration.
        let wishingEnd = flightEnd.addingTimeInterval(t.departedDuration + 0.1)
        controller.advance(at: wishingEnd)
        XCTAssertEqual(controller.phase, .wishing)
        XCTAssertEqual(spy.wishingCount, 1)
        let celebrationStart = wishingEnd.addingTimeInterval(t.wishingDuration + 0.1)
        controller.advance(at: celebrationStart)
        XCTAssertEqual(controller.phase, .celebration)
        XCTAssertEqual(spy.celebrationCount, 1)

        // Completion cleans everything up.
        let done = celebrationStart.addingTimeInterval(t.celebrationDuration + 0.1)
        controller.advance(at: done)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(spy.cleanupCount, 1)

        // The phase order is exactly the required sequence.
        XCTAssertEqual(spy.phases, [.noticing, .flight, .departed, .wishing, .celebration, .completed])
    }

    func testWishingDurationIsWithinSpecRange() {
        XCTAssertGreaterThanOrEqual(MeteorEventController.Timing().wishingDuration, 2.5)
        XCTAssertLessThanOrEqual(MeteorEventController.Timing().wishingDuration, 4.0)
    }

    func testReplayIgnoresQuietHoursAndCooldown() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = date(2026, 10, 1, 2, zone: zone) // deep inside quiet hours
        let controller = makeController(now: start, zone: zone)
        let spy = SpyPresenter()
        controller.presenter = spy
        controller.requestTrigger(.replay)
        controller.servicePendingTrigger()
        XCTAssertEqual(controller.phase, .noticing, "manual replay must bypass quiet hours")
    }

    // MARK: - Automatic scheduling

    func testAutomaticEligibilityRespectsQuietHoursCooldownAndCap() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = date(2026, 10, 1, 14, zone: zone)
        let controller = makeController(now: start, zone: zone)
        XCTAssertTrue(controller.shouldTriggerAutomatically(now: start))

        let late = date(2026, 10, 1, 23, zone: zone)
        XCTAssertFalse(controller.shouldTriggerAutomatically(now: late))
        let early = date(2026, 10, 2, 7, zone: zone)
        XCTAssertFalse(controller.shouldTriggerAutomatically(now: early))
        let morning = date(2026, 10, 2, 8, zone: zone)
        XCTAssertTrue(controller.shouldTriggerAutomatically(now: morning))

        var persistence = MeteorPersistence(defaults: defaults)
        persistence.recordAutomatic(at: start, calendar: calendar(zone))
        XCTAssertFalse(controller.shouldTriggerAutomatically(now: start.addingTimeInterval(10 * 60)))
        XCTAssertTrue(controller.shouldTriggerAutomatically(now: start.addingTimeInterval(46 * 60)))

        persistence.recordAutomatic(at: start.addingTimeInterval(50 * 60), calendar: calendar(zone))
        XCTAssertFalse(controller.shouldTriggerAutomatically(now: date(2026, 10, 1, 16, zone: zone)))
        XCTAssertTrue(controller.shouldTriggerAutomatically(now: date(2026, 10, 2, 9, zone: zone)))
    }

    func testAutomaticTriggerRecordsHistoryButReplayDoesNot() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = date(2026, 10, 1, 14, zone: zone)
        let persistence = MeteorPersistence(defaults: defaults)
        let t = MeteorEventController.Timing()
        let total = t.noticeDuration + t.flightDuration + t.departedDuration
            + t.wishingDuration + t.celebrationDuration

        let automatic = makeController(now: start, zone: zone)
        automatic.presenter = SpyPresenter()
        automatic.requestTrigger(.automatic)
        automatic.servicePendingTrigger()
        automatic.advance(at: start.addingTimeInterval(total + 0.2))
        XCTAssertEqual(automatic.phase, .idle)
        XCTAssertEqual(persistence.count(forDayKey: MeteorPersistence.dayKey(start, calendar: calendar(zone))), 1)

        let replay = makeController(now: start, zone: zone)
        replay.presenter = SpyPresenter()
        replay.requestTrigger(.replay)
        replay.servicePendingTrigger()
        replay.advance(at: start.addingTimeInterval(total + 0.2))
        XCTAssertEqual(persistence.count(forDayKey: MeteorPersistence.dayKey(start, calendar: calendar(zone))), 1,
                       "replay must not mutate automatic history")
    }

    func testBusyPetDefersTheMeteor() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = date(2026, 10, 1, 14, zone: zone)
        let controller = makeController(now: start, zone: zone)
        controller.isPetBusy = { true }
        controller.requestTrigger(.replay)
        controller.servicePendingTrigger()
        XCTAssertEqual(controller.phase, .idle, "no meteor while the pet is busy")
        controller.isPetBusy = { false }
        controller.servicePendingTrigger()
        XCTAssertEqual(controller.phase, .noticing)
    }

    func testCancellationCleansUpImmediately() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = date(2026, 10, 1, 14, zone: zone)
        let controller = makeController(now: start, zone: zone)
        let spy = SpyPresenter()
        controller.presenter = spy
        controller.requestTrigger(.replay)
        controller.servicePendingTrigger()
        controller.advance(at: start.addingTimeInterval(2))
        XCTAssertEqual(controller.phase, .flight)
        controller.cancel()
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(spy.cleanupCount, 1)
    }

    // MARK: - Production presentation path (the invisibility regression)

    func testProductionPresenterCreatesAndShowsTheMeteorPanel() {
        let windowController = PetWindowController()
        windowController.configureForTesting(
            frame: CGRect(x: 400, y: 300, width: 180, height: 226)
        )
        let zone = TimeZone(identifier: "America/New_York")!
        let now = date(2026, 10, 1, 14, zone: zone)
        let controller = MeteorEventController(
            clock: FixedClock(now: now, calendar: calendar(zone)),
            persistence: MeteorPersistence(defaults: defaults)
        )
        let presenter = MeteorEventPresenter(
            windowController: windowController, controller: controller, store: .shared
        )
        controller.presenter = presenter

        let trajectory = MeteorTrajectory.fixed(in: presenter.activeVisibleFrame)
        presenter.flightDidBegin(trajectory: trajectory)

        // The panel exists with the production view attached.
        let panel = presenter.debugPanel
        XCTAssertNotNil(panel, "METEOR_PANEL_CREATED: the panel must exist")
        guard let panel else { return }
        XCTAssertNotNil(panel.contentView, "the meteor view must be attached")
        XCTAssertFalse(panel.frame.isEmpty, "the panel needs a real size")
        // THE scale regression: the panel must be a SMALL sky object.
        // The previous double-scale bug produced a ~178,000-point panel.
        XCTAssertGreaterThan(panel.frame.width, 100, "the panel must not be tiny")
        XCTAssertLessThan(panel.frame.width, 400,
                          "the meteor panel must stay a small sky object (no giant translucent blocks)")

        // Mid-flight: the panel frame intersects the visible display and
        // alpha is fully opaque.
        presenter.flightFrame(progress: 0.5, at: now)
        let visible = presenter.activeVisibleFrame
        XCTAssertTrue(visible.intersects(panel.frame),
                      "the meteor panel must cross the display mid-flight")
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.01,
                       "the meteor must be fully opaque while flying")

        // Cleanup: alpha zero and the panel parked outside the visible
        // area — no residual edge sprite.
        presenter.cleanup()
        XCTAssertEqual(panel.alphaValue, 0, accuracy: 0.01)
        XCTAssertFalse(visible.intersects(panel.frame),
                       "after cleanup the panel must sit outside the visible area")
    }
}
