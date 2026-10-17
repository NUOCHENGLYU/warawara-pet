import XCTest
@testable import WarawaraPet

/// First-launch birthday surprise state machine: fresh detection (no
/// unrelated keys), pending/running/completed transitions, interruption
/// recovery, October 17 deferral to the annual event, and deduplication.
final class FirstLaunchTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "FirstLaunchTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
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
                      zone: TimeZone, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute
        components.timeZone = zone
        return calendar(zone).date(from: components)!
    }

    private func makeHandler(
        now: Date, zone: TimeZone,
        windowController: PetWindowController = PetWindowController()
    ) -> (FirstLaunchCelebration, BirthdayEventCoordinator) {
        let coordinator = BirthdayEventCoordinator(
            clock: FixedClock(now: now, calendar: calendar(zone)),
            persistence: BirthdayPersistence(defaults: defaults)
        )
        let handler = FirstLaunchCelebration(
            coordinator: coordinator,
            windowController: windowController,
            clock: FixedClock(now: now, calendar: calendar(zone)),
            defaults: defaults
        )
        return (handler, coordinator)
    }

    func testCleanMachineNotOnBirthdayPlaysTheSurprise() {
        let zone = TimeZone(identifier: "America/New_York")!
        let now = date(2026, 10, 18, 10, zone: zone)
        let (handler, coordinator) = makeHandler(now: now, zone: zone)

        var hatRequests: [Bool] = []
        handler.setCelebrationHat = { hatRequests.append($0) }

        handler.start()
        XCTAssertEqual(defaults.string(forKey: FirstLaunchState.key), FirstLaunchState.pending.rawValue,
                       "the surprise is owed, not completed before playback")
        XCTAssertTrue(hatRequests.isEmpty, "no hat before the celebration actually runs")

        // The birthday tick services the pending trigger: the celebration
        // runs and the machine observes it.
        coordinator.servicePendingTrigger()
        XCTAssertTrue(coordinator.isRunning)
        handler.evaluate()
        XCTAssertEqual(defaults.string(forKey: FirstLaunchState.key), FirstLaunchState.running.rawValue)
        XCTAssertTrue(hatRequests.contains(true), "the hat appears while the surprise runs")
        XCTAssertFalse(coordinator.shouldTriggerAutomatically,
                       "the surprise must not consume annual eligibility")
    }

    func testCleanMachineOnOctober17DefersToTheAnnualEvent() {
        let zone = TimeZone(identifier: "America/New_York")!
        let now = date(2026, 10, 17, 9, zone: zone)
        let (handler, coordinator) = makeHandler(now: now, zone: zone)
        var hatRequests: [Bool] = []
        handler.setCelebrationHat = { hatRequests.append($0) }

        handler.start()
        XCTAssertEqual(defaults.string(forKey: FirstLaunchState.key), FirstLaunchState.pending.rawValue)
        XCTAssertTrue(hatRequests.isEmpty, "no separate surprise on the birthday itself")
        XCTAssertTrue(coordinator.shouldTriggerAutomatically,
                      "the annual October 17 event must stay intact")
        // The annual event plays (services its automatic trigger): the
        // machine watches it, then completes.
        coordinator.checkAutomaticTrigger()
        coordinator.servicePendingTrigger()
        XCTAssertTrue(coordinator.isRunning)
        handler.evaluate()
        XCTAssertEqual(defaults.string(forKey: FirstLaunchState.key), FirstLaunchState.running.rawValue)
        coordinator.requestCancellation()
        handler.evaluate()
        XCTAssertEqual(defaults.string(forKey: FirstLaunchState.key), FirstLaunchState.completed.rawValue)
        XCTAssertTrue(hatRequests.contains(false), "the hat is removed after completion")
    }

    func testInterruptedRunningCelebrationReplaysSafely() {
        let zone = TimeZone(identifier: "America/New_York")!
        let now = date(2026, 10, 18, 10, zone: zone)
        let (handler, coordinator) = makeHandler(now: now, zone: zone)
        handler.start()
        coordinator.servicePendingTrigger()
        handler.evaluate()
        XCTAssertEqual(defaults.string(forKey: FirstLaunchState.key), FirstLaunchState.running.rawValue)

        // The app quits mid-celebration: `running` is persisted. On the
        // next launch a fresh coordinator sees the state and replays.
        let (handler2, coordinator2) = makeHandler(now: now, zone: zone)
        handler2.start()
        coordinator2.servicePendingTrigger()
        XCTAssertTrue(coordinator2.isRunning, "interrupted celebration must be replayed safely")
        handler2.evaluate()
        XCTAssertEqual(defaults.string(forKey: FirstLaunchState.key), FirstLaunchState.running.rawValue)
        // The replay finishes: completion recorded.
        coordinator2.requestCancellation()
        handler2.evaluate()
        XCTAssertEqual(defaults.string(forKey: FirstLaunchState.key), FirstLaunchState.completed.rawValue)
    }

    func testCompletedInstallationNeverReplays() {
        let zone = TimeZone(identifier: "America/New_York")!
        let now = date(2026, 11, 5, 10, zone: zone)
        defaults.set(FirstLaunchState.completed.rawValue, forKey: FirstLaunchState.key)
        let (handler, coordinator) = makeHandler(now: now, zone: zone)
        var hatRequests: [Bool] = []
        handler.setCelebrationHat = { hatRequests.append($0) }
        handler.start()
        coordinator.servicePendingTrigger()
        XCTAssertFalse(coordinator.isRunning)
        XCTAssertTrue(hatRequests.isEmpty)
    }

    func testLegacySingleKeyBuildMigratesToCompleted() {
        let zone = TimeZone(identifier: "America/New_York")!
        let now = date(2026, 11, 5, 10, zone: zone)
        // The previous build's own completion marker (our key only):
        defaults.set(true, forKey: FirstLaunchState.legacyCompletedKey)
        let (handler, coordinator) = makeHandler(now: now, zone: zone)
        handler.start()
        XCTAssertEqual(defaults.string(forKey: FirstLaunchState.key), FirstLaunchState.completed.rawValue)
        XCTAssertFalse(defaults.bool(forKey: FirstLaunchState.legacyCompletedKey))
        coordinator.servicePendingTrigger()
        XCTAssertFalse(coordinator.isRunning, "migrated installs must not replay")
    }

    func testPendingStateKeepsRetryingWithoutDuplicateTriggers() {
        let zone = TimeZone(identifier: "America/New_York")!
        let now = date(2026, 10, 18, 10, zone: zone)
        let (handler, coordinator) = makeHandler(now: now, zone: zone)
        handler.start()
        XCTAssertEqual(defaults.string(forKey: FirstLaunchState.key), FirstLaunchState.pending.rawValue)

        // The trigger is not yet serviced: repeated evaluations keep the
        // machine in pending without stacking duplicate triggers.
        handler.evaluate()
        handler.evaluate()
        XCTAssertEqual(defaults.string(forKey: FirstLaunchState.key), FirstLaunchState.pending.rawValue)

        // Once the birthday tick services the trigger, the machine
        // recovers into running.
        coordinator.servicePendingTrigger()
        XCTAssertTrue(coordinator.isRunning)
        handler.evaluate()
        XCTAssertEqual(defaults.string(forKey: FirstLaunchState.key), FirstLaunchState.running.rawValue)
    }

    func testAnnualBirthdayStillWorksAfterCompletion() {
        let zone = TimeZone(identifier: "America/New_York")!
        defaults.set(FirstLaunchState.completed.rawValue, forKey: FirstLaunchState.key)
        let nextYear = date(2027, 10, 17, 9, zone: zone)
        let (_, coordinator) = makeHandler(now: nextYear, zone: zone)
        XCTAssertTrue(coordinator.shouldTriggerAutomatically,
                      "future annual birthdays must still trigger")
    }

    func testDebugResetClearsAllFirstLaunchState() {
        defaults.set(FirstLaunchState.completed.rawValue, forKey: FirstLaunchState.key)
        defaults.set(true, forKey: FirstLaunchState.legacyCompletedKey)
        FirstLaunchState.resetForDebugging(defaults: defaults)
        XCTAssertNil(defaults.string(forKey: FirstLaunchState.key))
        XCTAssertFalse(defaults.bool(forKey: FirstLaunchState.legacyCompletedKey))
        XCTAssertEqual(FirstLaunchState.load(defaults: defaults), .fresh)
    }
}
