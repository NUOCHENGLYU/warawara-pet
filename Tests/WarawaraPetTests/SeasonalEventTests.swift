import XCTest
@testable import WarawaraPet

/// Deterministic tests for seasonal eligibility, daily policy, and the
/// shared scene coordinator/scheduler.
final class SeasonalEventTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SeasonalEventTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        SeasonalAssetStore.shared.reset()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private final class FixedClock: BirthdayClock {
        var currentNow: Date
        let calendar: Calendar
        init(now: Date, calendar: Calendar) { self.currentNow = now; self.calendar = calendar }
        func now() -> Date { currentNow }
    }

    private func calendar(_ zone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int,
                      timeZone: TimeZone, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute
        components.timeZone = timeZone
        return calendar(timeZone).date(from: components)!
    }

    // MARK: - Eligibility

    func testChineseNewYearEligibilityUsesLunarCalendar() {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let cal = calendar(zone)
        // 2027 CNY: lunar 1/1 = Feb 6 (Gregorian).
        let eveGregorian = date(2027, 2, 5, 12, timeZone: zone)
        XCTAssertFalse(SeasonalEligibility.isChineseNewYear(date: eveGregorian, calendar: cal),
                       "Feb 5 2027 is lunar 12/30, not the festival")
        for day in 6...8 {
            let d = date(2027, 2, day, 12, timeZone: zone)
            XCTAssertTrue(SeasonalEligibility.isChineseNewYear(date: d, calendar: cal),
                          "lunar 1/\(day - 5) must be eligible")
        }
        let after = date(2027, 2, 9, 12, timeZone: zone)
        XCTAssertFalse(SeasonalEligibility.isChineseNewYear(date: after, calendar: cal),
                       "lunar 1/4 is outside the festival")
    }

    func testChristmasEligibilityWindow() {
        let zone = TimeZone(identifier: "America/New_York")!
        let cal = calendar(zone)
        XCTAssertFalse(SeasonalEligibility.isChristmas(date: date(2026, 12, 24, 17, timeZone: zone), calendar: cal))
        XCTAssertTrue(SeasonalEligibility.isChristmas(date: date(2026, 12, 24, 18, timeZone: zone), calendar: cal))
        XCTAssertTrue(SeasonalEligibility.isChristmas(date: date(2026, 12, 25, 10, timeZone: zone), calendar: cal))
        XCTAssertTrue(SeasonalEligibility.isChristmas(date: date(2026, 12, 26, 23, timeZone: zone), calendar: cal))
        XCTAssertFalse(SeasonalEligibility.isChristmas(date: date(2026, 12, 27, 9, timeZone: zone), calendar: cal))
    }

    func testNewYearEligibility() {
        let zone = TimeZone(identifier: "America/Chicago")!
        let cal = calendar(zone)
        XCTAssertTrue(SeasonalEligibility.isNewYear(date: date(2027, 1, 1, 0, timeZone: zone, minute: 30), calendar: cal))
        XCTAssertFalse(SeasonalEligibility.isNewYear(date: date(2026, 12, 31, 23, timeZone: zone, minute: 59), calendar: cal))
        XCTAssertFalse(SeasonalEligibility.isNewYear(date: date(2027, 1, 2, 9, timeZone: zone), calendar: cal))
    }

    func testHolidayOccurrenceYearIsLocalGregorianYear() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let cal = calendar(zone)
        let cny = date(2027, 2, 6, 10, timeZone: zone)
        XCTAssertEqual(SeasonalEligibility.occurrenceYear(for: .cny, date: cny, calendar: cal), 2027)
        let xmas = date(2026, 12, 25, 10, timeZone: zone)
        XCTAssertEqual(SeasonalEligibility.occurrenceYear(for: .christmas, date: xmas, calendar: cal), 2026)
    }

    // MARK: - Persistence

    func testHolidayCompletionIsOncePerOccurrence() {
        let persistence = SeasonalPersistence(defaults: defaults)
        XCTAssertFalse(persistence.isCompleted(.cny, occurrenceYear: 2027))
        persistence.markCompleted(.cny, occurrenceYear: 2027)
        XCTAssertTrue(persistence.isCompleted(.cny, occurrenceYear: 2027))
        XCTAssertFalse(persistence.isCompleted(.cny, occurrenceYear: 2028))
        XCTAssertFalse(persistence.isCompleted(.christmas, occurrenceYear: 2027))
    }

    func testDailyHistoryRoundTripsAndCaps() {
        let persistence = SeasonalPersistence(defaults: defaults)
        for index in 0..<15 {
            persistence.appendDailyRecord(SeasonalPersistence.DailyRecord(
                kind: "umbrella", dayKey: "2026-10-17", timestamp: 1000 + Double(index)
            ))
        }
        let records = persistence.dailyHistory()
        XCTAssertLessThanOrEqual(records.count, 10, "history stays bounded")
        persistence.markDailyCompleted(at: 5000)
        XCTAssertEqual(persistence.lastDailyCompletion ?? 0, 5000, accuracy: 0.001)
    }

    // MARK: - Daily policy

    func testDailyPolicyRespectsUptimeCooldownCapsAndQuietHours() {
        var policy = DailyEventPolicy()
        let zone = TimeZone(identifier: "America/New_York")!
        let cal = calendar(zone)
        let launch = date(2026, 10, 17, 10, timeZone: zone)
        let history: [SeasonalPersistence.DailyRecord] = []

        // Too soon after launch.
        XCTAssertFalse(policy.maySchedule(
            now: launch.addingTimeInterval(5 * 60), calendar: cal,
            appUptime: 5 * 60, history: history, lastCompletion: nil, isBusy: false
        ))
        // Quiet hours.
        XCTAssertFalse(policy.maySchedule(
            now: date(2026, 10, 18, 0, timeZone: zone), calendar: cal,
            appUptime: 40 * 60, history: history, lastCompletion: nil, isBusy: false
        ))
        // Busy (dragging/sleeping).
        XCTAssertFalse(policy.maySchedule(
            now: launch.addingTimeInterval(30 * 60), calendar: cal,
            appUptime: 30 * 60, history: history, lastCompletion: nil, isBusy: true
        ))
        // Cooldown not elapsed.
        XCTAssertFalse(policy.maySchedule(
            now: launch.addingTimeInterval(30 * 60), calendar: cal,
            appUptime: 30 * 60, history: history,
            lastCompletion: launch.addingTimeInterval(20 * 60).timeIntervalSince1970,
            isBusy: false
        ))
        // Healthy case.
        XCTAssertTrue(policy.maySchedule(
            now: launch.addingTimeInterval(40 * 60), calendar: cal,
            appUptime: 40 * 60, history: history,
            lastCompletion: launch.addingTimeInterval(-200 * 60).timeIntervalSince1970,
            isBusy: false
        ))

        // Per-day cap.
        let todayKey = DailyEventPolicy.dayKey(for: launch, calendar: cal)
        let twoToday = [
            SeasonalPersistence.DailyRecord(kind: "umbrella", dayKey: todayKey, timestamp: 100),
            SeasonalPersistence.DailyRecord(kind: "sprout", dayKey: todayKey, timestamp: 200)
        ]
        XCTAssertFalse(policy.maySchedule(
            now: launch.addingTimeInterval(45 * 60), calendar: cal,
            appUptime: 45 * 60, history: twoToday,
            lastCompletion: launch.addingTimeInterval(-300 * 60).timeIntervalSince1970,
            isBusy: false
        ))
    }

    func testDailyPickAvoidsRecentKindsDeterministically() {
        let policy = DailyEventPolicy()
        let zone = TimeZone(identifier: "America/New_York")!
        let now = date(2026, 10, 17, 12, timeZone: zone)
        let history = [
            SeasonalPersistence.DailyRecord(kind: "umbrella", dayKey: "2026-10-17", timestamp: now.timeIntervalSince1970 - 60),
            SeasonalPersistence.DailyRecord(kind: "hotCocoa", dayKey: "2026-10-17", timestamp: now.timeIntervalSince1970 - 120),
            SeasonalPersistence.DailyRecord(kind: "sprout", dayKey: "2026-10-17", timestamp: now.timeIntervalSince1970 - 180)
        ]
        var rng = SeededRandomSource(seed: 42)
        // Only paperAirplane remains fresh.
        XCTAssertEqual(policy.pickKind(now: now, history: history, using: &rng), .paperAirplane)
    }

    // MARK: - Coordinator

    func testSeasonalCoordinatorPhasesAndCompletionPersistence() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = date(2027, 2, 6, 10, timeZone: zone)
        let clock = FixedClock(now: start, calendar: calendar(zone))
        let persistence = SeasonalPersistence(defaults: defaults)
        let coordinator = SeasonalEventCoordinator(
            clock: clock, persistence: persistence, timing: .forKind(.cny)
        )
        final class Spy: SeasonalEventPresenting {
            var calls: [String] = []
            func noticeScene() { calls.append("notice") }
            func presentProp() { calls.append("present") }
            func settleProp() { calls.append("settle") }
            func celebrateScene() { calls.append("celebrate") }
            func departScene() { calls.append("depart") }
            func clearAttention() { calls.append("clear") }
        }
        let spy = Spy()
        coordinator.presenter = spy

        coordinator.requestTrigger(.cny, trigger: .automatic)
        coordinator.servicePendingTrigger()
        XCTAssertEqual(coordinator.phase, .noticing)

        let timing = SeasonalTiming.forKind(.cny)
        let total = timing.noticeDuration + timing.approachDuration
            + timing.presentDuration + timing.celebrateDuration + timing.departDuration
        coordinator.advance(at: start.addingTimeInterval(timing.noticeDuration + 0.1))
        XCTAssertEqual(coordinator.phase, .approach)
        XCTAssertTrue(spy.calls.contains("present"))

        coordinator.advance(at: start.addingTimeInterval(timing.noticeDuration + timing.approachDuration + 0.1))
        XCTAssertEqual(coordinator.phase, .present)

        coordinator.advance(at: start.addingTimeInterval(timing.noticeDuration + timing.approachDuration + timing.presentDuration + 0.1))
        XCTAssertEqual(coordinator.phase, .celebrate)

        coordinator.advance(at: start.addingTimeInterval(
            timing.noticeDuration + timing.approachDuration + timing.presentDuration
                + timing.celebrateDuration + timing.departDuration + 0.1
        ))
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertTrue(persistence.isCompleted(.cny, occurrenceYear: 2027))
        XCTAssertTrue(spy.calls.contains("clear"))
    }

    func testReplayDoesNotConsumeHolidayCompletion() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = date(2027, 8, 1, 10, timeZone: zone) // NOT CNY
        let clock = FixedClock(now: start, calendar: calendar(zone))
        let persistence = SeasonalPersistence(defaults: defaults)
        let coordinator = SeasonalEventCoordinator(
            clock: clock, persistence: persistence, timing: .forKind(.christmas)
        )
        final class Spy: SeasonalEventPresenting {
            func noticeScene() {}
            func presentProp() {}
            func settleProp() {}
            func celebrateScene() {}
            func departScene() {}
            func clearAttention() {}
        }
        coordinator.presenter = Spy()

        coordinator.requestTrigger(.christmas, trigger: .replay)
        coordinator.servicePendingTrigger()
        XCTAssertEqual(coordinator.phase, .noticing)

        let timing = SeasonalTiming.forKind(.christmas)
        let total = timing.noticeDuration + timing.approachDuration
            + timing.presentDuration + timing.celebrateDuration + timing.departDuration
        coordinator.advance(at: start.addingTimeInterval(
            timing.noticeDuration + timing.approachDuration + timing.presentDuration
                + timing.celebrateDuration + timing.departDuration + 0.1
        ))
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertFalse(persistence.isCompleted(.christmas, occurrenceYear: 2027),
                       "replay must not consume annual completion")
    }

    // MARK: - Scheduler

    func testSchedulerTriggersHolidayByPriority() {
        let zone = TimeZone(identifier: "America/New_York")!
        // Christmas eligible (Dec 25 2026) and CNY NOT eligible.
        let now = date(2026, 12, 25, 10, timeZone: zone)
        let clock = FixedClock(now: now, calendar: calendar(zone))
        let persistence = SeasonalPersistence(defaults: defaults)
        let scheduler = EventScheduler(clock: clock, persistence: persistence)
        scheduler.configure(windowController: PetWindowController())
        scheduler.isPetBusy = { false }
        scheduler.isBirthdayBlocking = { false }
        scheduler.tick()
        let coordinator = scheduler.coordinators[.christmas]
        coordinator?.servicePendingTrigger()
        XCTAssertEqual(coordinator?.phase, .noticing, "Christmas should trigger on Dec 25")
        scheduler.tick()
        XCTAssertEqual(scheduler.coordinators[.newYear]?.phase, .idle,
                       "no other holiday may start while one runs")
    }

    func testSchedulerDefersToBirthday() {
        let zone = TimeZone(identifier: "America/New_York")!
        let now = date(2026, 12, 25, 10, timeZone: zone)
        let clock = FixedClock(now: now, calendar: calendar(zone))
        let persistence = SeasonalPersistence(defaults: defaults)
        let scheduler = EventScheduler(clock: clock, persistence: persistence)
        scheduler.configure(windowController: PetWindowController())
        scheduler.isPetBusy = { false }
        scheduler.isBirthdayBlocking = { true } // birthday pending
        scheduler.tick()
        for coordinator in scheduler.coordinators.values {
            XCTAssertEqual(coordinator.phase, .idle,
                           "birthday priority must block holiday events")
        }
    }

    func testSchedulerDailyFlowWithSeededRng() {
        let zone = TimeZone(identifier: "America/New_York")!
        let launch = date(2026, 10, 17, 10, timeZone: zone)
        let clock = FixedClock(now: launch, calendar: calendar(zone))
        let persistence = SeasonalPersistence(defaults: defaults)
        let scheduler = EventScheduler(
            clock: clock, persistence: persistence,
            appLaunchDate: launch, seededRNG: SeededRandomSource(seed: 7)
        )
        scheduler.configure(windowController: PetWindowController())
        scheduler.isPetBusy = { false }
        scheduler.isBirthdayBlocking = { false }

        // First tick: uptime 0 -> nothing.
        scheduler.tick()
        XCTAssertFalse(scheduler.isAnyEventRunning)

        // 40 minutes later: healthy case -> a daily event may schedule.
        let later = launch.addingTimeInterval(40 * 60)
        clock.currentNow = later
        // Global cooldown not elapsed yet (never completed) -> allowed.
        scheduler.tick()
        let running = scheduler.coordinators.values.first { $0.phase != .idle }
        XCTAssertNotNil(running, "a daily event should be scheduled after the first-event delay")
    }

    // MARK: - Assets

    func testSeasonalAssetsResolveAndHash() {
        XCTAssertTrue(SeasonalAssetStore.shared.verifyAllRequiredAssets().ok)
        XCTAssertTrue(SeasonalAssetStore.shared.verifySHA256().ok)
        for name in SeasonalAssetStore.requiredFileNames {
            guard let image = SeasonalAssetStore.shared.image(named: name) else {
                XCTFail("\(name) missing")
                continue
            }
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else {
                XCTFail("\(name) not decodable")
                continue
            }
            XCTAssertEqual(rep.pixelsWide, 1024, "\(name) must be a 1024 canvas")
            XCTAssertEqual(rep.colorAt(x: 0, y: 0)?.alphaComponent ?? 0, 0, accuracy: 0.01,
                           "\(name) corner must be transparent")
        }
    }
}

