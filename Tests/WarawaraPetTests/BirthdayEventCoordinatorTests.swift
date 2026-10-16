import XCTest
@testable import WarawaraPet

/// Deterministic tests for birthday eligibility, persistence, trigger
/// semantics, and the event phase machine — using an injectable clock
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
        func noticeCompanionsArriving() { calls.append("notice") }
        func presentCarriedProps() { calls.append("presentCarriedProps") }
        func deliverPropsToPet() { calls.append("deliverProps") }
        func activateEnvelope() { calls.append("activateEnvelope") }
        func hideCake() { calls.append("hideCake") }
        func startCompanionGroup() { calls.append("startCompanionGroup") }
        func cancelCompanionGroup() { calls.append("cancelCompanionGroup") }
        func performMainPetHop() { calls.append("hop") }
        func clearAttention() { calls.append("clearAttention") }
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
        let newYork = TimeZone(identifier: "America/New_York")!
        let chicago = TimeZone(identifier: "America/Chicago")!
        let instant = Date(timeIntervalSince1970: 1_792_648_200)
        let nyCal = calendar(newYork)
        let chicagoCal = calendar(chicago)
        let nyComponents = nyCal.dateComponents([.month, .day], from: instant)
        let chicagoComponents = chicagoCal.dateComponents([.month, .day], from: instant)
        XCTAssertEqual(
            BirthdayDateMath.isBirthday(nyComponents),
            BirthdayDateMath.isBirthday(chicagoComponents),
            "October 17 is the same local date in both US zones at any instant"
        )
        let nyMidnight = date(2026, 10, 17, 0, timeZone: newYork, minute: 30)
        XCTAssertTrue(BirthdayDateMath.isBirthday(date: nyMidnight, calendar: nyCal))
        let honolulu = TimeZone(identifier: "Pacific/Honolulu")!
        XCTAssertFalse(
            BirthdayDateMath.isBirthday(date: nyMidnight, calendar: calendar(honolulu))
        )
    }

    func testDSTAdjacentDatesStayOctober17Locally() {
        let zone = TimeZone(identifier: "America/New_York")!
        let cal = calendar(zone)
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
        XCTAssertEqual(coordinator.phase, .noticing)
        XCTAssertTrue(spy.calls.contains("notice"), "the pet must notice the arrival")
        XCTAssertTrue(spy.calls.contains("hop"))

        coordinator.checkAutomaticTrigger()
        coordinator.servicePendingTrigger()
        XCTAssertEqual(spy.calls.filter { $0 == "hop" }.count, 1, "duplicate triggers are ignored")
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
        XCTAssertEqual(coordinator.phase, .noticing)
    }

    // MARK: - Phase lifecycle (companions bring the gifts)

    func testFullSequenceGiftDeliveryPhaseOrdering() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = date(2026, 10, 17, 9, timeZone: zone)
        let clock = FixedClock(now: start, calendar: calendar(zone))
        let persistence = BirthdayPersistence(defaults: defaults)
        let (coordinator, spy) = makeCoordinator(clock: clock, persistence: persistence)

        coordinator.requestTrigger(.automatic)
        coordinator.servicePendingTrigger()
        XCTAssertEqual(coordinator.phase, .noticing)
        XCTAssertTrue(spy.calls.contains("notice"))
        XCTAssertEqual(spy.calls.filter { $0 == "hop" }.count, 1)

        // Second hop during the noticing beat.
        clock.currentNow = start.addingTimeInterval(1.5)
        coordinator.advance(at: clock.currentNow)
        XCTAssertEqual(spy.calls.filter { $0 == "hop" }.count, 2)

        // Companions enter carrying the props.
        clock.currentNow = start.addingTimeInterval(3.0)
        coordinator.advance(at: clock.currentNow)
        XCTAssertEqual(coordinator.phase, .gathering)
        XCTAssertTrue(spy.calls.contains("presentCarriedProps"))
        XCTAssertTrue(spy.calls.contains("startCompanionGroup"))
        XCTAssertFalse(spy.calls.contains("deliverProps"), "props arrive WITH the companions first")

        coordinator.companionGroupDidStart()
        let gatherStart = clock.currentNow

        // Delivery to the front-of-pet layout after the carriers settle.
        clock.currentNow = gatherStart.addingTimeInterval(5.2)
        coordinator.advance(at: clock.currentNow)
        XCTAssertEqual(coordinator.phase, .celebrating)
        XCTAssertTrue(spy.calls.contains("deliverProps"))

        // Staggered celebration hops.
        clock.currentNow = gatherStart.addingTimeInterval(9.0)
        coordinator.advance(at: clock.currentNow)
        XCTAssertEqual(spy.calls.filter { $0 == "hop" }.count, 4, "both celebration hops")

        // Ascent ends: envelope activated, cake fades, pet released.
        coordinator.companionGroupDidEnd()
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertTrue(spy.calls.contains("activateEnvelope"))
        XCTAssertTrue(spy.calls.contains("hideCake"))
        XCTAssertTrue(spy.calls.contains("clearAttention"))
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
        XCTAssertEqual(coordinator.phase, .noticing, "replay works on any date")

        clock.currentNow = start.addingTimeInterval(3.0)
        coordinator.advance(at: clock.currentNow)
        coordinator.companionGroupDidStart()
        let gatherStart = clock.currentNow
        clock.currentNow = gatherStart.addingTimeInterval(5.2)
        coordinator.advance(at: clock.currentNow)
        coordinator.companionGroupDidEnd()
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertTrue(persistence.envelopeUnlocked)
        XCTAssertFalse(persistence.isCompleted(year: 2026), "replay must not consume the annual record")

        let hopsBefore = spy.calls.filter { $0 == "hop" }.count
        coordinator.requestTrigger(.replay)
        coordinator.servicePendingTrigger()
        XCTAssertEqual(coordinator.phase, .noticing)
        XCTAssertGreaterThan(spy.calls.filter { $0 == "hop" }.count, hopsBefore)
    }

    func testInterruptionBeforeDeliveryCleansUpWithoutCompletion() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = date(2026, 10, 17, 9, timeZone: zone)
        let clock = FixedClock(now: start, calendar: calendar(zone))
        let persistence = BirthdayPersistence(defaults: defaults)
        let (coordinator, spy) = makeCoordinator(clock: clock, persistence: persistence)

        coordinator.requestTrigger(.automatic)
        coordinator.servicePendingTrigger()
        clock.currentNow = start.addingTimeInterval(3.0)
        coordinator.advance(at: clock.currentNow)
        coordinator.companionGroupDidStart()

        coordinator.requestCancellation()
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertTrue(spy.calls.contains("cancelCompanionGroup"))
        XCTAssertTrue(spy.calls.contains("clearAttention"))
        XCTAssertFalse(spy.calls.contains("activateEnvelope"), "undelivered gift is not left behind")
        XCTAssertFalse(persistence.isCompleted(year: 2026))
        XCTAssertFalse(persistence.envelopeUnlocked)
    }

    func testInterruptionAfterDeliveryKeepsTheEnvelope() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = date(2026, 10, 17, 9, timeZone: zone)
        let clock = FixedClock(now: start, calendar: calendar(zone))
        let persistence = BirthdayPersistence(defaults: defaults)
        let (coordinator, spy) = makeCoordinator(clock: clock, persistence: persistence)

        coordinator.requestTrigger(.replay)
        coordinator.servicePendingTrigger()
        clock.currentNow = start.addingTimeInterval(3.0)
        coordinator.advance(at: clock.currentNow)
        coordinator.companionGroupDidStart()
        let gatherStart = clock.currentNow
        clock.currentNow = gatherStart.addingTimeInterval(5.2)
        coordinator.advance(at: clock.currentNow)
        XCTAssertTrue(coordinator.propsDelivered)

        coordinator.requestCancellation()
        XCTAssertTrue(spy.calls.contains("activateEnvelope"), "delivered gift remains readable")
        XCTAssertFalse(persistence.isCompleted(year: 2026), "interruption is not completion")
        XCTAssertTrue(persistence.envelopeUnlocked, "the delivered gift unlocks the envelope")
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
