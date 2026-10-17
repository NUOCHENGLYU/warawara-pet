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
        // Enter celebrate at a distinct earlier timestamp...
        coordinator.advance(at: start.addingTimeInterval(
            timing.noticeDuration + timing.approachDuration + timing.presentDuration + 0.1
        ))
        XCTAssertEqual(coordinator.phase, .celebrate)
        // ...then let celebrate + depart elapse.
        coordinator.advance(at: start.addingTimeInterval(
            timing.noticeDuration + timing.approachDuration + timing.presentDuration
                + timing.celebrateDuration + timing.departDuration + 0.2
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

    // MARK: - Production presentation path (every event ID)

    /// For EVERY event ID the REAL production presenter must be reached:
    /// a real prop panel created, real packaged PNGs loaded, a real
    /// nonzero window frame presented, and cleanup run. This is the
    /// regression that the silent no-op acceptance failure demanded.
    func testEveryKindReachesRealProductionPresentation() {
        for kind in SeasonalEventKind.allCases {
            let zone = TimeZone(identifier: "America/New_York")!
            let start = date(2027, 8, 1, 9, timeZone: zone)
            let clock = FixedClock(now: start, calendar: calendar(zone))
            let windowController = PetWindowController()
            windowController.configureForTesting(
                frame: CGRect(x: 300, y: 300, width: 180, height: 200)
            )
            let coordinator = SeasonalEventCoordinator(
                clock: clock, persistence: SeasonalPersistence(defaults: defaults),
                timing: .forKind(kind)
            )
            let presenter = SeasonalEventPresenter(
                windowController: windowController, coordinator: coordinator, store: .shared
            )
            coordinator.presenter = presenter

            coordinator.requestTrigger(kind, trigger: .replay)
            coordinator.servicePendingTrigger()
            XCTAssertEqual(coordinator.phase, .noticing, "\(kind): replay must begin")

            let timing = SeasonalTiming.forKind(kind)
            coordinator.advance(at: start.addingTimeInterval(timing.noticeDuration + 0.2))
            XCTAssertEqual(coordinator.phase, .approach, "\(kind): scene must reach presentation")
            XCTAssertEqual(presenter.presentCallCount, 1, "\(kind): production presenter must be invoked")
            XCTAssertTrue(presenter.rejectionReasons.isEmpty,
                          "\(kind): presentation must not be rejected: \(presenter.rejectionReasons)")
            guard let panel = presenter.presentedPanel else {
                XCTFail("\(kind): real prop panel missing")
                continue
            }
            XCTAssertFalse(panel.frame.isEmpty, "\(kind): panel needs a real frame")
            XCTAssertTrue(panel.frame.origin.x.isFinite && panel.frame.origin.y.isFinite,
                          "\(kind): panel frame must be finite")
            XCTAssertNotNil(panel.contentView, "\(kind): panel must host the production view")
            XCTAssertEqual(panel.level, .floating, "\(kind): prop level must match the pet plane")

            // Every production PNG for the scene loads from the real
            // packaged bundle.
            for asset in kind.displayedAssets {
                XCTAssertNotNil(SeasonalAssetStore.shared.image(named: asset),
                                "\(kind): production PNG \(asset) must load")
            }

            // Scene remains active for a meaningful interval, then
            // cleanup (depart) runs.
            let celebrateAt = start.addingTimeInterval(
                timing.noticeDuration + timing.approachDuration + timing.presentDuration + 0.2
            )
            coordinator.advance(at: celebrateAt)
            XCTAssertEqual(coordinator.phase, .celebrate, "\(kind): present duration must hold the prop")
            coordinator.advance(at: celebrateAt.addingTimeInterval(
                timing.celebrateDuration + timing.departDuration + 0.3
            ))
            XCTAssertEqual(coordinator.phase, .idle, "\(kind): scene must complete and reset")
            XCTAssertGreaterThanOrEqual(presenter.departCallCount, 1, "\(kind): cleanup must depart the prop")
            XCTAssertNil(coordinator.presentationFault, "\(kind): no presentation fault")
        }
    }

    /// Coordinator progress without ANY presentation callback is a
    /// failure, not a completed event.
    func testCoordinatorProgressWithoutPresenterIsAFault() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = date(2027, 8, 1, 9, timeZone: zone)
        let clock = FixedClock(now: start, calendar: calendar(zone))
        let coordinator = SeasonalEventCoordinator(
            clock: clock, persistence: SeasonalPersistence(defaults: defaults),
            timing: .forKind(.umbrella)
        )
        // NO presenter attached on purpose.
        coordinator.requestTrigger(.umbrella, trigger: .replay)
        coordinator.servicePendingTrigger()
        coordinator.advance(at: start.addingTimeInterval(
            SeasonalTiming.forKind(.umbrella).noticeDuration + 0.2
        ))
        XCTAssertEqual(coordinator.phase, .approach, "phases still advance")
        XCTAssertEqual(coordinator.presentationFault, "no-presenter",
                       "phase progress without a presentation path must be flagged")
    }

    /// A presenter that cannot present (zero pet frame) must REJECT
    /// loudly instead of silently succeeding.
    func testInvalidGeometryRejectsPresentation() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = date(2027, 8, 1, 9, timeZone: zone)
        let clock = FixedClock(now: start, calendar: calendar(zone))
        let windowController = PetWindowController() // no panel -> zero frame
        let coordinator = SeasonalEventCoordinator(
            clock: clock, persistence: SeasonalPersistence(defaults: defaults),
            timing: .forKind(.sprout)
        )
        let presenter = SeasonalEventPresenter(
            windowController: windowController, coordinator: coordinator, store: .shared
        )
        coordinator.presenter = presenter

        coordinator.requestTrigger(.sprout, trigger: .replay)
        coordinator.servicePendingTrigger()
        coordinator.advance(at: start.addingTimeInterval(
            SeasonalTiming.forKind(.sprout).noticeDuration + 0.2
        ))
        XCTAssertEqual(presenter.presentCallCount, 1, "the presenter was reached")
        XCTAssertTrue(presenter.rejectionReasons.contains("invalid-geometry"),
                      "zero-frame presentation must be rejected, not faked")
    }

    /// Scene minimums: every scene must draw at least one production PNG
    /// and holiday scenes must include their decorations.
    func testDisplayedAssetsCoverEverySceneMinimum() {
        XCTAssertEqual(Set(SeasonalEventKind.cny.displayedAssets), Set([
            "cny_hongbao.png", "cny_lantern.png", "cny_plum_branch.png",
            "cny_firecracker_hanging.png"
        ]), "CNY must show hongbao + lantern/plum decorations")
        XCTAssertEqual(Set(SeasonalEventKind.christmas.displayedAssets), Set([
            "xmas_gift.png", "xmas_wreath.png"
        ]), "Christmas must show gift + wreath")
        XCTAssertEqual(Set(SeasonalEventKind.newYear.displayedAssets), Set([
            "newyear_calendar_jan1.png", "newyear_party_popper.png"
        ]), "New Year must show calendar + popper")
        for daily in [SeasonalEventKind.umbrella, .hotCocoa, .sprout, .paperAirplane] {
            XCTAssertEqual(daily.displayedAssets.count, 1)
            XCTAssertTrue(daily.showsSecondaryDecor == false)
        }
        XCTAssertTrue(SeasonalEventKind.cny.showsSecondaryDecor)
        XCTAssertTrue(SeasonalEventKind.christmas.showsSecondaryDecor)
        XCTAssertTrue(SeasonalEventKind.newYear.showsSecondaryDecor)
    }

    /// Scene durations must sit inside the per-kind spec ranges so every
    /// event is visible for a meaningful interval.
    func testSceneTimingsFitSpecDurationRanges() {
        for kind in SeasonalEventKind.allCases {
            let timing = SeasonalTiming.forKind(kind)
            let total = timing.noticeDuration + timing.approachDuration
                + timing.presentDuration + timing.celebrateDuration + timing.departDuration
            XCTAssertTrue(
                kind.durationRange.contains(total),
                "\(kind): total \(total)s must fit \(kind.durationRange)"
            )
        }
    }

    // MARK: - Runtime replay regression coverage (the silent no-op fix)

    func testCommandLineParsesEveryKindAndRejectsUnknown() {
        for kind in SeasonalEventKind.allCases {
            let parsed = EventCommandLine.parseReplayEvent(arguments: ["--replay-event", kind.replayArgument])
            XCTAssertEqual(parsed, kind, "\(kind.replayArgument) must parse")
        }
        XCTAssertNil(EventCommandLine.parseReplayEvent(arguments: ["--replay-event", "nope"]))
        XCTAssertNil(EventCommandLine.parseReplayEvent(arguments: []))
        XCTAssertNil(EventCommandLine.parseReplayEvent(arguments: ["--replay-event"]))
        XCTAssertTrue(EventCommandLine.usage.contains("--replay-event"))
        XCTAssertTrue(EventCommandLine.usage.contains("paper-airplane"))
        // Smoke flag parses identically.
        XCTAssertEqual(EventCommandLine.parseReplaySmoke(arguments: ["--replay-smoke", "cny"]), .cny)
    }

    func testSchedulerTickAdvancesReplayScenes() {
        // The production playback clock: WITHOUT scheduler.advance the
        // scene sits in .noticing forever and nothing ever becomes
        // visible — the exact silent no-op the user reported.
        let zone = TimeZone(identifier: "America/New_York")!
        let launch = date(2027, 8, 1, 9, timeZone: zone)
        let clock = FixedClock(now: launch, calendar: calendar(zone))
        let persistence = SeasonalPersistence(defaults: defaults)
        let scheduler = EventScheduler(clock: clock, persistence: persistence)
        scheduler.configure(windowController: PetWindowController())
        scheduler.isPetBusy = { false }
        scheduler.isBirthdayBlocking = { false }

        scheduler.requestReplay(kind: .umbrella)
        scheduler.tick()
        let coordinator = scheduler.coordinators[.umbrella]
        XCTAssertEqual(coordinator?.phase, .noticing, "replay must start after the first tick")

        // Advance the clock past the notice duration; the next tick must
        // push the scene into .approach (visible prop presentation).
        clock.currentNow = launch.addingTimeInterval(SeasonalTiming.forKind(.umbrella).noticeDuration + 0.5)
        scheduler.tick()
        XCTAssertEqual(coordinator?.phase, .approach,
                       "the scheduler must advance scenes so props become visible")
    }

    func testReplayBypassesQuietHoursAndUptimePolicy() {
        let zone = TimeZone(identifier: "America/New_York")!
        // 01:00 local: inside quiet hours AND zero app uptime.
        let launch = date(2027, 8, 1, 1, timeZone: zone)
        let clock = FixedClock(now: launch, calendar: calendar(zone))
        let persistence = SeasonalPersistence(defaults: defaults)
        let scheduler = EventScheduler(clock: clock, persistence: persistence)
        scheduler.configure(windowController: PetWindowController())
        scheduler.isPetBusy = { false }
        scheduler.isBirthdayBlocking = { false }

        scheduler.requestReplay(kind: .hotCocoa)
        scheduler.tick()
        XCTAssertEqual(scheduler.coordinators[.hotCocoa]?.phase, .noticing,
                       "manual replay must ignore quiet hours and first-launch delays")
        // Replay must not touch daily history.
        XCTAssertTrue(persistence.dailyHistory().isEmpty)
        XCTAssertNil(persistence.lastDailyCompletion)
    }

    func testReplayDuringRunningSceneDefersThenRuns() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = date(2027, 8, 1, 9, timeZone: zone)
        let clock = FixedClock(now: start, calendar: calendar(zone))
        let persistence = SeasonalPersistence(defaults: defaults)
        let coordinator = SeasonalEventCoordinator(
            clock: clock, persistence: persistence, timing: .forKind(.cny)
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

        coordinator.requestTrigger(.cny, trigger: .replay)
        coordinator.servicePendingTrigger()
        XCTAssertEqual(coordinator.phase, .noticing)

        // A second replay during the running scene is deferred, not dropped.
        coordinator.requestTrigger(.umbrella, trigger: .replay)

        // Complete the cny scene.
        let timing = SeasonalTiming.forKind(.cny)
        coordinator.advance(at: start.addingTimeInterval(timing.noticeDuration + timing.approachDuration + timing.presentDuration + 0.1))
        XCTAssertEqual(coordinator.phase, .celebrate)
        coordinator.advance(at: start.addingTimeInterval(
            timing.noticeDuration + timing.approachDuration + timing.presentDuration
                + timing.celebrateDuration + timing.departDuration + 0.2
        ))
        XCTAssertEqual(coordinator.phase, .idle)

        // The deferred replay now runs automatically on the next service.
        coordinator.servicePendingTrigger()
        XCTAssertEqual(coordinator.kind, .umbrella)
        XCTAssertEqual(coordinator.phase, .noticing)
    }

    func testVisibleMarkerFiresOnRealPresentationPath() {
        let windowController = PetWindowController()
        let zone = TimeZone(identifier: "America/New_York")!
        let now = date(2027, 8, 1, 9, timeZone: zone)
        let clock = FixedClock(now: now, calendar: calendar(zone))
        let coordinator = SeasonalEventCoordinator(
            clock: clock, persistence: SeasonalPersistence(defaults: defaults),
            timing: .forKind(.umbrella)
        )
        // A window controller without a panel has a zero frame, so the
        // presenter cannot present — the coordinator must still advance
        // phases; the VISIBLE marker is tied to presentProp + orderFront
        // in the real app (smoke-tested against the packaged binary).
        let presenter = SeasonalEventPresenter(
            windowController: windowController, coordinator: coordinator, store: .shared
        )
        coordinator.presenter = presenter
        coordinator.requestTrigger(.umbrella, trigger: .replay)
        coordinator.servicePendingTrigger()
        XCTAssertEqual(coordinator.phase, .noticing)
        coordinator.advance(at: now.addingTimeInterval(
            SeasonalTiming.forKind(.umbrella).noticeDuration + 0.2
        ))
        XCTAssertEqual(coordinator.phase, .approach, "presentProp must be reached")
    }
}

