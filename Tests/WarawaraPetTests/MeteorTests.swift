import XCTest
@testable import WarawaraPet

/// Meteor event coverage: independent world-space trajectory, complete
/// disappearance, phase sequencing, attention timing, and automatic
/// scheduling limits.
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
        var cleanupCount = 0
        var activeVisibleFrame: CGRect { visibleFrame }
        func noticeScene() { noticeCount += 1 }
        func flightDidBegin(trajectory: MeteorTrajectory) {}
        func flightFrame(progress: CGFloat, at now: Date) { flightFrames.append(progress) }
        func meteorDeparted() { departedCount += 1 }
        func cleanup() { cleanupCount += 1 }
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
        let again = MeteorTrajectory.fixed(in: visible)
        XCTAssertEqual(trajectory, again)
    }

    func testFlightIsContinuousAtRenderCadence() {
        let trajectory = MeteorTrajectory.fixed(in: visible)
        var previous = trajectory.position(at: 0)
        for step in 1...60 {
            let t = CGFloat(step) / 60
            let p = trajectory.position(at: t)
            let delta = hypot(p.x - previous.x, p.y - previous.y)
            XCTAssertLessThan(delta, 80, "no teleporting between 60 Hz samples")
            previous = p
        }
    }

    // MARK: - Phase sequence + full disappearance

    func testReplayRunsFullSequenceAndCleansUp() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = date(2026, 10, 1, 10, zone: zone)
        let controller = makeController(now: start, zone: zone)
        let spy = SpyPresenter()
        controller.presenter = spy

        controller.requestTrigger(.replay)
        controller.servicePendingTrigger()
        XCTAssertEqual(controller.phase, .noticing)
        XCTAssertEqual(spy.noticeCount, 1)

        // Flight begins after the notice period.
        let noticeEnd = start.addingTimeInterval(controller.timing.noticeDuration + 0.1)
        controller.advance(at: noticeEnd)
        XCTAssertEqual(controller.phase, .flight)
        XCTAssertNotNil(controller.trajectory)

        // Mid-flight frames are rendered with increasing progress.
        for step in 1...5 {
            let t = start.addingTimeInterval(
                controller.timing.noticeDuration + controller.timing.flightDuration * Double(step) / 5
            )
            controller.advance(at: t)
        }
        XCTAssertGreaterThan(spy.flightFrames.count, 0)
        XCTAssertEqual(controller.phase, .flight)

        // End of flight: the meteor has FULLY left the display.
        let flightEnd = start.addingTimeInterval(
            controller.timing.noticeDuration + controller.timing.flightDuration + 0.1
        )
        controller.advance(at: flightEnd)
        XCTAssertEqual(controller.phase, .celebration)
        XCTAssertEqual(spy.departedCount, 1, "celebration only AFTER departure")

        // Scene completes and everything is cleaned up.
        let done = flightEnd.addingTimeInterval(controller.timing.celebrationDuration + 0.1)
        controller.advance(at: done)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(spy.cleanupCount, 1)
    }

    func testReplayIgnoresQuietHoursAndCooldown() {
        let zone = TimeZone(identifier: "America/New_York")!
        // 02:00 local, deep inside quiet hours.
        let start = date(2026, 10, 1, 2, zone: zone)
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

        // Quiet hours: 23:00 blocks.
        let late = date(2026, 10, 1, 23, zone: zone)
        XCTAssertFalse(controller.shouldTriggerAutomatically(now: late))
        let early = date(2026, 10, 2, 7, zone: zone)
        XCTAssertFalse(controller.shouldTriggerAutomatically(now: early))
        let morning = date(2026, 10, 2, 8, zone: zone)
        XCTAssertTrue(controller.shouldTriggerAutomatically(now: morning))

        // Cooldown: recording one blocks the next 45 minutes.
        var persistence = MeteorPersistence(defaults: defaults)
        persistence.recordAutomatic(at: start, calendar: calendar(zone))
        let tooSoon = start.addingTimeInterval(10 * 60)
        XCTAssertFalse(controller.shouldTriggerAutomatically(now: tooSoon))
        let later = start.addingTimeInterval(46 * 60)
        XCTAssertTrue(controller.shouldTriggerAutomatically(now: later))

        // Daily cap: two records block the rest of the day.
        persistence.recordAutomatic(at: start.addingTimeInterval(50 * 60), calendar: calendar(zone))
        let afternoon = date(2026, 10, 1, 16, zone: zone)
        XCTAssertFalse(controller.shouldTriggerAutomatically(now: afternoon))
        // A new day resets the cap (cooldown still applies).
        let nextDay = date(2026, 10, 2, 9, zone: zone)
        XCTAssertTrue(controller.shouldTriggerAutomatically(now: nextDay))
    }

    func testAutomaticTriggerRecordsHistoryButReplayDoesNot() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = date(2026, 10, 1, 14, zone: zone)
        let persistence = MeteorPersistence(defaults: defaults)

        let automatic = makeController(now: start, zone: zone)
        automatic.presenter = SpyPresenter()
        automatic.requestTrigger(.automatic)
        automatic.servicePendingTrigger()
        let done = start.addingTimeInterval(
            automatic.timing.noticeDuration + automatic.timing.flightDuration
                + automatic.timing.celebrationDuration + 0.2
        )
        automatic.advance(at: done)
        XCTAssertEqual(automatic.phase, .idle)
        XCTAssertEqual(persistence.count(forDayKey: MeteorPersistence.dayKey(start, calendar: calendar(zone))), 1)

        // Replay: no history mutation.
        let replay = makeController(now: start, zone: zone)
        replay.presenter = SpyPresenter()
        replay.requestTrigger(.replay)
        replay.servicePendingTrigger()
        replay.advance(at: done)
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
        XCTAssertEqual(spy.cleanupCount, 1, "cancellation must clean the panel state")
    }
}
