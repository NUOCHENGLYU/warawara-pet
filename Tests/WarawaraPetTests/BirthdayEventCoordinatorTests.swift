import XCTest
@testable import WarawaraPet

/// Deterministic tests for birthday eligibility, persistence, trigger
/// semantics, and the event phase machine 鈥?using an injectable clock
/// and a recording presenter spy (no real windows).
final class BirthdayEventCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "BirthdayEventCoordinatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private final class FixedClock: BirthdayClock {
        var currentNow: Date
        let calendar: Calendar

        init(now: Date, calendar: Calendar) {
            self.currentNow = now
            self.calendar = calendar
        }

        func now() -> Date { currentNow }
    }

    private final class Spy: BirthdayEventPresenting {
        var calls: [String] = []
        func presentCake() { calls.append("presentCake") }
        func hideCake() { calls.append("hideCake") }
        func presentSparkles() { calls.append("presentSparkles") }
        func hideSparkles() { calls.append("hideSparkles") }
        func presentEnvelope() { calls.append("presentEnvelope") }
        func hideEnvelope() { calls.append("hideEnvelope") }
        func startCompanionGroup() { calls.append("startCompanionGroup") }
        func cancelCompanionGroup() { calls.append("cancelCompanionGroup") }
        func performMainPetHop() { calls.append("hop") }
        func envelopeDidBecomeAvailable() { calls.append("envelopeDidBecomeAvailable") }
    }

    private func calendar(_ timeZone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, timeZone: TimeZone, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = timeZone
        let cal = calendar(timeZone)
        return cal.date(from: components)!
    }

    private func makeCoordinator(
        clock: BirthdayClock,
        persistence: BirthdayPersistence? = nil
    ) -> (BirthdayEventCoordinator, Spy) {
        let coordinator = BirthdayEventCoordinator(
            clock: clock,
            persistence: persistence ?? BirthdayPersistence(defaults: defaults)
        )
        let spy = Spy()
        coordinator.presenter = spy
        return (coordinator, spy)
    }

    // MARK: - Calendar eligibility

    func testOctober17IsEligibleInLocalCalendar() {
        let zone = TimeZone(identifier: "America/New_York")!
        let cal = calendar(zone)
        let day16 = date(2026, 10, 16, 12, timeZone: zone)
        let day17 = date(2026, 10, 17, 12, timeZone: zone)
        let day18 = date(2026, 10, 18, 12, timeZone: zone)
        XCTAssertFalse(BirthdayDateMath.isBirthday(date: day16, calendar: cal))
        XCTAssertTrue(BirthdayDateMath.isBirthday(date: day17, calendar: cal))
        XCTAssertFalse(BirthdayDateMath.isBirthday(date: day18, calendar: cal))
    }

    func testEligibilityUsesEachLocalTimezoneNotUTC() {
        // 2026-10-16T22:30 -05:00 == 2026-10-17T03:30 UTC: still not the
        // birthday in New York, but IS the birthday in Honolulu where the
        // local date is October 16... the point: the SAME instant must be
        // judged by each local calendar independently.
        let newYork = TimeZone(identifier: "America/New_York")!
        let chicago = TimeZone(identifier: "America/Chicago")!
        let instant = Date(timeIntervalSince1970: 1_792_648_200) // arbitrary fixed instant
        let nyCal = calendar(newYork)
        let chicagoCal = calendar(chicago)
        let nyComponents = nyCal.dateComponents([.month, .day], from: instant)
        let chicagoComponents = chicagoCal.dateComponents([.month, .day], from: instant)
        XCTAssertEqual(
            BirthdayDateMath.isBirthday(nyComponents),
            BirthdayDateMath.isBirthday(chicagoComponents),
            "October 17 is the same local date in both US zones at any instant"
        )
        // Deterministic boundary: construct 2026-10-17T00:30 in New York.
        let nyMidnight = date(2026, 10, 17, 0, timeZone: newYork, minute: 30)
        XCTAssertTrue(BirthdayDateMath.isBirthday(date: nyMidnight, calendar: nyCal))
        // Same instant in Honolulu is 2026-10-16T18:30 -> NOT birthday there.
        let honolulu = TimeZone(identifier: "Pacific/Honolulu")!
        XCTAssertFalse(
            BirthdayDateMath.isBirthday(date: nyMidnight, calendar: calendar(honolulu))
        )
    }

    func testDSTAdjacentDatesStayOctober17Locally() {
        let zone = TimeZone(identifier: "America/New_York")!
        let cal = calendar(zone)
        // DST ends Nov 1 2026; October 17 is well inside DST 鈥?verify
        // the local calendar reports month/day 10/17 across the day.
        for hour in [0, 6, 12, 18, 23] {
            let d = date(2026, 10, 17, hour, timeZone: zone)
            XCTAssertTrue(
                BirthdayDateMath.isBirthday(date: d, calendar: cal),
                "hour \(hour) must remain October 17 locally"
            )
        }
    }

    // MARK: - Persistence

    func testCompletionIsOncePerLocalYear() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let persistence = BirthdayPersistence(defaults: defaults)
        let clock2026 = FixedClock(
            now: date(2026, 10, 17, 10, timeZone: zone),
            calendar: calendar(zone)
        )
        let (coordinator, _) = makeCoordinator(clock: clock2026, persistence: persistence)
        XCTAssertTrue(coordinator.shouldTriggerAutomatically)

        persistence.markCompleted(year: 2026)
        XCTAssertTrue(coordinator.isCompletedThisYear)
        XCTAssertFalse(coordinator.shouldTriggerAutomatically, "must not re-trigger in the same year")

        let clock2027 = FixedClock(
            now: date(2027, 10, 17, 10, timeZone: zone),
            calendar: calendar(zone)
        )
        let (nextYear, _) = makeCoordinator(clock: clock2027, persistence: persistence)
        XCTAssertTrue(nextYear.shouldTriggerAutomatically, "a new local year is eligible again")
    }

    func testTimezoneChangeStillUsesLocalCalendar() {
        let zone = TimeZone(identifier: "America/New_York")!
        let persistence = BirthdayPersistence(defaults: defaults)
        persistence.markCompleted(year: 2026)
        // The user travels to Chicago on the birthday: local calendar is
        // still October 17, 2026 -> completed record still applies.
        let chicago = TimeZone(identifier: "America/Chicago")!
        let clock = FixedClock(
            now: date(2026, 10, 17, 14, timeZone: chicago),
            calendar: calendar(chicago)
        )
        let (coordinator, _) = makeCoordinator(clock: clock, persistence: persistence)
        XCTAssertEqual(coordinator.currentYear, 2026)
        XCTAssertTrue(coordinator.isCompletedThisYear)
        XCTAssertFalse(coordinator.shouldTriggerAutomatically)
    }

    // MARK: - Trigger semantics

    func testMidnightTransitionTriggersOnce() {
        let zone = TimeZone(identifier: "America/New_York")!
        let persistence = BirthdayPersistence(defaults: defaults)
        let clock = FixedClock(
            now: date(2026, 10, 16, 23, timeZone: zone, minute: 59),
            calendar: calendar(zone)
        )
        let (coordinator, spy) = makeCoordinator(clock: clock, persistence: persistence)
        coordinator.checkAutomaticTrigger()
        coordinator.servicePendingTrigger()
        XCTAssertEqual(coordinator.phase, .idle, "no trigger before midnight")

        clock.currentNow = date(2026, 10, 17, 0, timeZone: zone, minute: 5)
        coordinator.checkAutomaticTrigger()
        XCTAssertFalse(coordinator.isRunning, "trigger is pending, not started while unserviced")
        coordinator.servicePendingTrigger()
        XCTAssertEqual(coordinator.phase, .surprise)
        XCTAssertTrue(spy.calls.contains("hop"))

        // Duplicate trigger attempts are ignored while running.
        coordinator.checkAutomaticTrigger()
        coordinator.servicePendingTrigger()
        XCTAssertEqual(spy.calls.filter { $0 == "hop" }.count, 1)
    }

    func testTriggerDeferredWhilePetIsDragging() {
        let zone = TimeZone(identifier: "America/New_York")!
        let clock = FixedClock(
            now: date(2026, 10, 17, 10, timeZone: zone),
            calendar: calendar(zone)
        )
        let (coordinator, _) = makeCoordinator(clock: clock)
        var dragging = true
        coordinator.isPetBusy = { dragging }
        coordinator.requestTrigger(.automatic)
        coordinator.servicePendingTrigger()
        XCTAssertEqual(coordinator.phase, .idle, "must defer while dragging")

        dragging = false
        coordinator.servicePendingTrigger()
        XCTAssertEqual(coordinator.phase, .surprise)
    }

    // MARK: - Phase lifecycle

    func testFullSequencePhaseOrderingAndCompletion() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = date(2026, 10, 17, 9, timeZone: zone)
        let clock = FixedClock(now: start, calendar: calendar(zone))
        let persistence = BirthdayPersistence(defaults: defaults)
        let (coordinator, spy) = makeCoordinator(clock: clock, persistence: persistence)

        coordinator.requestTrigger(.automatic)
        coordinator.servicePendingTrigger()
        XCTAssertEqual(coordinator.phase, .surprise)
        XCTAssertEqual(spy.calls.filter { $0 == "hop" }.count, 1)

        clock.currentNow = start.addingTimeInterval(2.5)
        coordinator.advance(at: clock.currentNow)
        XCTAssertEqual(spy.calls.filter { $0 == "hop" }.count, 2, "second hop in surprise")

        clock.currentNow = start.addingTimeInterval(3.5)
        coordinator.advance(at: clock.currentNow)
        XCTAssertEqual(coordinator.phase, .cakeArriving)
        XCTAssertTrue(spy.calls.contains("presentCake"))

        clock.currentNow = start.addingTimeInterval(5.0)
        coordinator.advance(at: clock.currentNow)
        XCTAssertEqual(coordinator.phase, .gathering)
        XCTAssertTrue(spy.calls.contains("startCompanionGroup"))

        clock.currentNow = start.addingTimeInterval(10.5)
        coordinator.advance(at: clock.currentNow)
        XCTAssertEqual(spy.calls.filter { $0 == "hop" }.count, 3, "celebration hop")

        coordinator.companionGroupDidStart()
        XCTAssertEqual(coordinator.phase, .ascending)

        coordinator.companionGroupDidEnd()
        XCTAssertEqual(coordinator.phase, .envelopeReveal)
        XCTAssertTrue(spy.calls.contains("presentEnvelope"))
        XCTAssertTrue(spy.calls.contains("hideCake"))

        clock.currentNow = start.addingTimeInterval(14.0)
        coordinator.advance(at: clock.currentNow)
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertTrue(spy.calls.contains("envelopeDidBecomeAvailable"))
        XCTAssertTrue(persistence.envelopeUnlocked)
        XCTAssertTrue(persistence.isCompleted(year: 2026), "automatic trigger consumes the annual record")
    }

    func testReplayDoesNotConsumeAnnualRecordAndIsRepeatable() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = date(2026, 11, 3, 9, timeZone: zone) // NOT the birthday
        let clock = FixedClock(now: start, calendar: calendar(zone))
        let persistence = BirthdayPersistence(defaults: defaults)
        let (coordinator, spy) = makeCoordinator(clock: clock, persistence: persistence)

        coordinator.requestTrigger(.replay)
        coordinator.servicePendingTrigger()
        XCTAssertEqual(coordinator.phase, .surprise, "replay works on any date")

        // Fast-forward the whole sequence.
        coordinator.advance(at: start.addingTimeInterval(3.5))
        coordinator.advance(at: start.addingTimeInterval(5.0))
        coordinator.companionGroupDidStart()
        coordinator.companionGroupDidEnd()
        coordinator.advance(at: start.addingTimeInterval(10.0))
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertTrue(persistence.envelopeUnlocked)
        XCTAssertFalse(persistence.isCompleted(year: 2026), "replay must not consume the annual record")

        // Repeatable.
        let hopsBefore = spy.calls.filter { $0 == "hop" }.count
        coordinator.requestTrigger(.replay)
        coordinator.servicePendingTrigger()
        XCTAssertEqual(coordinator.phase, .surprise)
        XCTAssertGreaterThan(spy.calls.filter { $0 == "hop" }.count, hopsBefore)
    }

    func testInterruptionCleansUpWithoutCompletion() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = date(2026, 10, 17, 9, timeZone: zone)
        let clock = FixedClock(now: start, calendar: calendar(zone))
        let persistence = BirthdayPersistence(defaults: defaults)
        let (coordinator, spy) = makeCoordinator(clock: clock, persistence: persistence)

        coordinator.requestTrigger(.automatic)
        coordinator.servicePendingTrigger()
        coordinator.advance(at: start.addingTimeInterval(5.0))
        coordinator.companionGroupDidStart()

        coordinator.requestCancellation()
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertTrue(spy.calls.contains("cancelCompanionGroup"))
        XCTAssertFalse(persistence.isCompleted(year: 2026), "interruption must not complete")
        XCTAssertFalse(persistence.envelopeUnlocked)
    }

    func testEnvelopeAvailabilityRule() {
        let zone = TimeZone(identifier: "America/New_York")!
        let persistence = BirthdayPersistence(defaults: defaults)
        let oct17 = FixedClock(
            now: date(2026, 10, 17, 9, timeZone: zone),
            calendar: calendar(zone)
        )
        let (onBirthday, _) = makeCoordinator(clock: oct17, persistence: persistence)
        XCTAssertTrue(onBirthday.shouldShowEnvelope, "envelope shows on the birthday")

        let oct20 = FixedClock(
            now: date(2026, 10, 20, 9, timeZone: zone),
            calendar: calendar(zone)
        )
        let (offBirthday, _) = makeCoordinator(clock: oct20, persistence: persistence)
        XCTAssertFalse(offBirthday.shouldShowEnvelope, "no envelope before unlock")

        persistence.markEnvelopeUnlocked()
        XCTAssertTrue(offBirthday.shouldShowEnvelope, "unlocked envelope persists any date")
    }
}

