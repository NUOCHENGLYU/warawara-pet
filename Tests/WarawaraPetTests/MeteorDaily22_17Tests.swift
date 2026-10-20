import XCTest
@testable import WarawaraPet

/// Fixed daily local-22:17 automatic meteor: the full boundary matrix.
/// The schedule is deterministic — no probability, no random showtime —
/// so every boundary below is a real, exact assertion.
final class MeteorDaily22_17Tests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    private var newYork: TimeZone { TimeZone(identifier: "America/New_York")! }
    private var losAngeles: TimeZone { TimeZone(identifier: "America/Los_Angeles")! }
    private var shanghai: TimeZone { TimeZone(identifier: "Asia/Shanghai")! }

    override func setUp() {
        super.setUp()
        suiteName = "MeteorDaily22_17.\(UUID().uuidString)"
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

    private func date(_ year: Int, _ month: Int, _ day: Int,
                      _ hour: Int, _ minute: Int, _ second: Int = 0,
                      zone: TimeZone) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute; components.second = second
        components.timeZone = zone
        return calendar(zone).date(from: components)!
    }

    private func evaluate(_ at: Date, zone: TimeZone,
                          busy: Bool = false, birthdayBlocking: Bool = false) -> Bool {
        var scheduler = MeteorNightlyScheduler()
        let persistence = MeteorPersistence(defaults: defaults)
        return scheduler.evaluate(
            now: at, calendar: calendar(zone), persistence: persistence,
            busy: busy, birthdayBlocking: birthdayBlocking
        )
    }

    private func key(for at: Date, zone: TimeZone) -> String {
        MeteorPersistence.nightKey(at, calendar: calendar(zone))
    }

    // MARK: - The 22:17 boundary matrix

    func testBefore2217NeverFires() {
        let zone = newYork
        XCTAssertFalse(evaluate(date(2026, 10, 1, 22, 16, 59, zone: zone), zone: zone))
        let k = key(for: date(2026, 10, 1, 22, 16, 59, zone: zone), zone: zone)
        XCTAssertFalse(MeteorPersistence(defaults: defaults).automaticFired(forKey: k))
        XCTAssertFalse(MeteorPersistence(defaults: defaults).automaticSkipped(forKey: k))
    }

    func testExactly2217Fires() {
        let zone = newYork
        XCTAssertTrue(evaluate(date(2026, 10, 1, 22, 17, 0, zone: zone), zone: zone))
        let k = key(for: date(2026, 10, 1, 22, 17, 0, zone: zone), zone: zone)
        XCTAssertTrue(MeteorPersistence(defaults: defaults).automaticFired(forKey: k))
    }

    func testOneSecondPast2217Fires() {
        let zone = newYork
        XCTAssertTrue(evaluate(date(2026, 10, 1, 22, 17, 1, zone: zone), zone: zone))
    }

    func testLateTickInsideGraceWindowStillFires() {
        let zone = newYork
        XCTAssertTrue(evaluate(date(2026, 10, 1, 22, 18, 29, zone: zone), zone: zone))
    }

    func testPastTheGraceWindowSkipsInsteadOfFiring() {
        let zone = newYork
        let late = date(2026, 10, 1, 22, 18, 31, zone: zone)
        XCTAssertFalse(evaluate(late, zone: zone))
        let k = key(for: late, zone: zone)
        XCTAssertTrue(MeteorPersistence(defaults: defaults).automaticSkipped(forKey: k))
        XCTAssertFalse(MeteorPersistence(defaults: defaults).automaticFired(forKey: k))
        // Never a late-night catch-up fire.
        XCTAssertFalse(evaluate(date(2026, 10, 1, 23, 0, 0, zone: zone), zone: zone))
    }

    func testSameDayRepeatedTicksNeverFireTwice() {
        let zone = newYork
        let persistence = MeteorPersistence(defaults: defaults)
        var scheduler = MeteorNightlyScheduler()
        let first = date(2026, 10, 1, 22, 17, 1, zone: zone)
        XCTAssertTrue(scheduler.evaluate(now: first, calendar: calendar(zone),
                                         persistence: persistence, busy: false, birthdayBlocking: false))
        for second in [2, 3, 15, 60, 88] {
            XCTAssertFalse(scheduler.evaluate(
                now: date(2026, 10, 1, 22, 17, second, zone: zone),
                calendar: calendar(zone), persistence: persistence,
                busy: false, birthdayBlocking: false
            ), "no second automatic meteor at 22:17:\(second)")
        }
    }

    func testSameDayRestartDoesNotRepeat() {
        let zone = newYork
        let persistence = MeteorPersistence(defaults: defaults)
        let at = date(2026, 10, 1, 22, 17, 10, zone: zone)
        var first = MeteorNightlyScheduler()
        XCTAssertTrue(first.evaluate(now: at, calendar: calendar(zone),
                                     persistence: persistence, busy: false, birthdayBlocking: false))
        // "Restart": a fresh scheduler, the same persisted store.
        var second = MeteorNightlyScheduler()
        XCTAssertFalse(second.evaluate(now: at.addingTimeInterval(5), calendar: calendar(zone),
                                       persistence: persistence, busy: false, birthdayBlocking: false))
    }

    func testNextLocalDayFiresAgain() {
        let zone = newYork
        let persistence = MeteorPersistence(defaults: defaults)
        let day1 = date(2026, 10, 1, 22, 17, 5, zone: zone)
        var scheduler = MeteorNightlyScheduler()
        XCTAssertTrue(scheduler.evaluate(now: day1, calendar: calendar(zone),
                                         persistence: persistence, busy: false, birthdayBlocking: false))
        let day2 = date(2026, 10, 2, 22, 17, 5, zone: zone)
        XCTAssertTrue(scheduler.evaluate(now: day2, calendar: calendar(zone),
                                         persistence: persistence, busy: false, birthdayBlocking: false),
                      "a new local day gets its own automatic meteor")
        XCTAssertNotEqual(key(for: day1, zone: zone), key(for: day2, zone: zone))
    }

    // MARK: - Timezones, DST, midnight

    func testShanghaiLocal2217FiresAndOtherZonesDoNotAtThatInstant() {
        // 22:17 in Shanghai fires at its own local instant; the SAME
        // absolute instant is a different local hour elsewhere and must
        // not fire there.
        let shanghaiInstant = date(2026, 10, 1, 22, 17, 0, zone: shanghai)
        XCTAssertTrue(evaluate(shanghaiInstant, zone: shanghai),
                      "22:17 local in Shanghai fires")
        XCTAssertFalse(evaluate(shanghaiInstant, zone: newYork),
                       "the same instant (10:17 in New York) must not fire in New York")
        XCTAssertFalse(evaluate(shanghaiInstant, zone: losAngeles),
                       "the same instant (07:17 in Los Angeles) must not fire in Los Angeles")
    }

    func testNewYorkLocal2217FiresAtItsOwnWallClockTime() {
        let newYorkInstant = date(2026, 10, 1, 22, 17, 0, zone: newYork)
        XCTAssertTrue(evaluate(newYorkInstant, zone: newYork))
        XCTAssertFalse(evaluate(newYorkInstant, zone: losAngeles),
                       "19:17 in Los Angeles must not fire")
    }

    func testTimezoneChangeKeepsTheLocalDateRecord() {
        // Fire in New York at 22:17, then evaluate the same instant under
        // Los Angeles: the LOCAL date is identical (2026-10-1), so the
        // fired record still blocks the same evening.
        let persistence = MeteorPersistence(defaults: defaults)
        let instant = date(2026, 10, 1, 22, 17, 30, zone: newYork)
        var ny = MeteorNightlyScheduler()
        XCTAssertTrue(ny.evaluate(now: instant, calendar: calendar(newYork),
                                  persistence: persistence, busy: false, birthdayBlocking: false))
        var la = MeteorNightlyScheduler()
        XCTAssertFalse(la.evaluate(now: instant, calendar: calendar(losAngeles),
                                   persistence: persistence, busy: false, birthdayBlocking: false),
                       "a timezone change on the same local date must not re-fire")
        // Moving to a zone where the local date is ALREADY the next day
        // gives that new local date its own shot at 22:17 local.
        let nextDayTokyo = date(2026, 10, 2, 22, 17, 0, zone: TimeZone(identifier: "Asia/Tokyo")!)
        var tokyo = MeteorNightlyScheduler()
        XCTAssertTrue(tokyo.evaluate(now: nextDayTokyo, calendar: calendar(TimeZone(identifier: "Asia/Tokyo")!),
                                     persistence: persistence, busy: false, birthdayBlocking: false))
    }

    func testDSTFallBackDayStillFiresAtLocal2217() {
        // US DST ends on 2026-11-01: a 25-hour local day. The fire time
        // must be the WALL-CLOCK 22:17, built from calendar components.
        let zone = newYork
        let fire = MeteorNightlyScheduler.fireDate(
            forDayContaining: date(2026, 11, 1, 12, 0, 0, zone: zone),
            calendar: calendar(zone)
        )
        let components = calendar(zone).dateComponents([.hour, .minute], from: fire)
        XCTAssertEqual(components.hour, 22)
        XCTAssertEqual(components.minute, 17)

        XCTAssertTrue(evaluate(fire.addingTimeInterval(1), zone: zone),
                      "the DST day fires at its local 22:17")
        XCTAssertFalse(evaluate(fire.addingTimeInterval(-30), zone: zone))
    }

    func testDSTSpringForwardDayStillFiresAtLocal2217() {
        // US DST starts on 2026-03-08: a 23-hour local day.
        let zone = newYork
        let fire = MeteorNightlyScheduler.fireDate(
            forDayContaining: date(2026, 3, 8, 12, 0, 0, zone: zone),
            calendar: calendar(zone)
        )
        let components = calendar(zone).dateComponents([.hour, .minute], from: fire)
        XCTAssertEqual(components.hour, 22)
        XCTAssertEqual(components.minute, 17)
        XCTAssertTrue(evaluate(fire.addingTimeInterval(1), zone: zone))
    }

    // MARK: - Sleep, busy, birthday, rollback, legacy records

    func testLidSleepPastTheWindowSkipsWithoutFiring() {
        // The machine slept from before 22:17 until 23:30: the next tick
        // is past the grace window — the night is skipped and recorded.
        let zone = newYork
        let wake = date(2026, 10, 1, 23, 30, 0, zone: zone)
        XCTAssertFalse(evaluate(wake, zone: zone))
        let k = key(for: wake, zone: zone)
        XCTAssertTrue(MeteorPersistence(defaults: defaults).automaticSkipped(forKey: k))
    }

    func testWakeInsideGraceWindowCanStillFire() {
        // Lid opens at 22:18:05 (inside the 90 s grace): the show may run.
        let zone = newYork
        XCTAssertTrue(evaluate(date(2026, 10, 1, 22, 18, 5, zone: zone), zone: zone))
    }

    func testClockRollbackAfterSkipCannotRefire() {
        let zone = newYork
        let persistence = MeteorPersistence(defaults: defaults)
        var scheduler = MeteorNightlyScheduler()
        let late = date(2026, 10, 1, 22, 18, 31, zone: zone)
        _ = scheduler.evaluate(now: late, calendar: calendar(zone),
                               persistence: persistence, busy: false, birthdayBlocking: false)
        // The user rolls the clock back into the grace window: the skip
        // record blocks the replay of the same local date.
        XCTAssertFalse(scheduler.evaluate(
            now: date(2026, 10, 1, 22, 17, 40, zone: zone),
            calendar: calendar(zone), persistence: persistence,
            busy: false, birthdayBlocking: false
        ), "a clock rollback must not re-fire a skipped local date")
    }

    func testClockRollbackAfterFiredCannotRefire() {
        let zone = newYork
        let persistence = MeteorPersistence(defaults: defaults)
        var scheduler = MeteorNightlyScheduler()
        XCTAssertTrue(scheduler.evaluate(
            now: date(2026, 10, 1, 22, 17, 20, zone: zone),
            calendar: calendar(zone), persistence: persistence,
            busy: false, birthdayBlocking: false
        ))
        XCTAssertFalse(scheduler.evaluate(
            now: date(2026, 10, 1, 22, 17, 5, zone: zone),
            calendar: calendar(zone), persistence: persistence,
            busy: false, birthdayBlocking: false
        ), "a clock rollback must not re-fire a fired local date")
    }

    func testBusyDefersWithinTheWindowAndExpiresAfterIt() {
        let zone = newYork
        let persistence = MeteorPersistence(defaults: defaults)
        var scheduler = MeteorNightlyScheduler()
        let at = date(2026, 10, 1, 22, 17, 5, zone: zone)
        XCTAssertFalse(scheduler.evaluate(now: at, calendar: calendar(zone),
                                          persistence: persistence,
                                          busy: true, birthdayBlocking: false),
                       "busy defers without marking anything")
        let k = key(for: at, zone: zone)
        XCTAssertFalse(persistence.automaticFired(forKey: k))
        XCTAssertFalse(persistence.automaticSkipped(forKey: k))
        // Freed inside the window: fires.
        XCTAssertTrue(scheduler.evaluate(now: at.addingTimeInterval(40), calendar: calendar(zone),
                                         persistence: persistence,
                                         busy: false, birthdayBlocking: false))
    }

    func testBusyNeverCarriesIntoLateNight() {
        let zone = newYork
        let persistence = MeteorPersistence(defaults: defaults)
        var scheduler = MeteorNightlyScheduler()
        let at = date(2026, 10, 1, 22, 17, 5, zone: zone)
        _ = scheduler.evaluate(now: at, calendar: calendar(zone),
                               persistence: persistence, busy: true, birthdayBlocking: false)
        // Still busy past the window: the night expires as skipped.
        XCTAssertFalse(scheduler.evaluate(now: date(2026, 10, 1, 22, 18, 31, zone: zone),
                                          calendar: calendar(zone), persistence: persistence,
                                          busy: true, birthdayBlocking: false))
        // Freed at 23:00: nothing plays.
        XCTAssertFalse(scheduler.evaluate(now: date(2026, 10, 1, 23, 0, 0, zone: zone),
                                          calendar: calendar(zone), persistence: persistence,
                                          busy: false, birthdayBlocking: false))
        XCTAssertTrue(persistence.automaticSkipped(forKey: key(for: at, zone: zone)))
    }

    func testBirthdayBlockingDefersWithinTheWindow() {
        let zone = newYork
        let persistence = MeteorPersistence(defaults: defaults)
        var scheduler = MeteorNightlyScheduler()
        let at = date(2026, 10, 17, 22, 17, 2, zone: zone) // the birthday!
        XCTAssertFalse(scheduler.evaluate(now: at, calendar: calendar(zone),
                                          persistence: persistence,
                                          busy: false, birthdayBlocking: true),
                       "the birthday blocks the meteor")
        let k = key(for: at, zone: zone)
        XCTAssertFalse(persistence.automaticFired(forKey: k))
        // Birthday finished inside the window: the meteor may run.
        XCTAssertTrue(scheduler.evaluate(now: at.addingTimeInterval(60), calendar: calendar(zone),
                                         persistence: persistence,
                                         busy: false, birthdayBlocking: false))
    }

    func testLegacyRandomNightRecordsDoNotAffectTheNewSchedule() {
        let zone = newYork
        let at = date(2026, 10, 1, 22, 17, 0, zone: zone)
        let k = key(for: at, zone: zone)
        // Seed the LEGACY keyspace with a fired random decision.
        defaults.set(true, forKey: "warawarapet.meteor.night.\(k).selected")
        defaults.set(true, forKey: "warawarapet.meteor.night.\(k).fired")
        defaults.set(75600.0, forKey: "warawarapet.meteor.night.\(k).seconds")
        // The new fixed schedule ignores the legacy records entirely.
        XCTAssertTrue(evaluate(at, zone: zone),
                      "legacy random-night records must not block the new 22:17 schedule")
    }

    // MARK: - Controller-level automatic trigger (production wiring shape)

    func testControllerFiresAutomaticallyAt2217ExactlyOnce() {
        let zone = newYork
        let at = date(2026, 10, 1, 22, 17, 3, zone: zone)
        let (controller, time) = makeController(now: at, zone: zone)
        let spy = SpyPresenter()
        controller.presenter = spy
        controller.tick()
        XCTAssertEqual(controller.phase, .noticing, "the automatic meteor begins at 22:17")
        XCTAssertEqual(spy.noticeCount, 1)

        // Later ticks on the same local date: never a second show.
        time.now = at.addingTimeInterval(60)
        controller.tick()
        XCTAssertEqual(spy.noticeCount, 1)
    }

    func testSleepingPetStillGetsTheAutomaticMeteor() {
        // Production wiring (AppDelegate) no longer counts sleeping as
        // busy; the presenter wakes the pet through the formal state
        // machine. Simulate the wired closures: busy only while dragging.
        let zone = newYork
        let at = date(2026, 10, 1, 22, 17, 3, zone: zone)
        let (controller, time) = makeController(now: at, zone: zone)
        controller.isPetBusy = { false } // sleeping is not busy anymore
        let spy = SpyPresenter()
        controller.presenter = spy
        controller.tick()
        XCTAssertEqual(controller.phase, .noticing,
                       "a sleeping pet no longer blocks the 22:17 show")
        XCTAssertEqual(spy.noticeCount, 1)
    }

    // MARK: - Helpers

    private final class FixedClock: BirthdayClock {
        var currentNow: Date
        let calendar: Calendar
        init(now: Date, calendar: Calendar) { self.currentNow = now; self.calendar = calendar }
        func now() -> Date { currentNow }
    }

    private final class TestTime {
        var uptime: TimeInterval = 1000
        var now: Date
        init(now: Date) { self.now = now }
    }

    private func makeController(now: Date, zone: TimeZone) -> (MeteorEventController, TestTime) {
        let time = TestTime(now: now)
        let controller = MeteorEventController(
            clock: FixedClock(now: now, calendar: calendar(zone)),
            persistence: MeteorPersistence(defaults: defaults)
        )
        controller.monotonicNow = { time.uptime }
        controller.isPetBusy = { false }
        controller.isBirthdayBlocking = { false }
        return (controller, time)
    }

    private final class SpyPresenter: MeteorEventPresenting {
        var noticeCount = 0
        var activeVisibleFrame: CGRect { CGRect(x: 0, y: 0, width: 1440, height: 900) }
        func noticeScene() { noticeCount += 1 }
        func flightDidBegin(trajectory: MeteorTrajectory) {}
        func meteorDeparted() {}
        func wishingDidBegin() {}
        func celebrationDidBegin() {}
        func cleanup() {}
    }
}
