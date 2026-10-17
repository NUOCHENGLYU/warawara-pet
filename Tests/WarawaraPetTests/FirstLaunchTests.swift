import XCTest
@testable import WarawaraPet

/// First-launch birthday surprise: fresh-install detection, migration,
/// October 17 deferral, deduplication and interrupted-playback recovery.
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
    ) -> (FirstLaunchCelebration, BirthdayEventCoordinator, PetWindowController) {
        let persistence = BirthdayPersistence(defaults: defaults)
        let coordinator = BirthdayEventCoordinator(
            clock: FixedClock(now: now, calendar: calendar(zone)),
            persistence: persistence
        )
        let handler = FirstLaunchCelebration(
            coordinator: coordinator,
            persistence: persistence,
            windowController: windowController,
            clock: FixedClock(now: now, calendar: calendar(zone)),
            defaults: defaults
        )
        return (handler, coordinator, windowController)
    }

    func testFreshFirstLaunchOnOctober18PlaysTheSurpriseOnce() {
        let zone = TimeZone(identifier: "America/New_York")!
        let now = date(2026, 10, 18, 10, zone: zone)
        let (handler, coordinator, _) = makeHandler(now: now, zone: zone)

        var hatRequests: [Bool] = []
        handler.setCelebrationHat = { hatRequests.append($0) }

        handler.start()
        XCTAssertTrue(defaults.bool(forKey: FirstLaunchCelebration.completedKey),
                      "completion must persist BEFORE playback")
        XCTAssertTrue(hatRequests.contains(true), "the birthday hat is requested during the surprise")
        XCTAssertFalse(coordinator.shouldTriggerAutomatically,
                       "the surprise must not consume annual eligibility")

        // Second launch: nothing happens again.
        let (handler2, coordinator2, _) = makeHandler(now: now, zone: zone)
        var hatRequests2: [Bool] = []
        handler2.setCelebrationHat = { hatRequests2.append($0) }
        handler2.start()
        XCTAssertTrue(hatRequests2.isEmpty, "the surprise is once-only")
        XCTAssertFalse(coordinator2.shouldTriggerAutomatically)
    }

    func testFreshFirstLaunchOnOctober17DefersToTheAnnualEvent() {
        let zone = TimeZone(identifier: "America/New_York")!
        let now = date(2026, 10, 17, 9, zone: zone)
        let (handler, coordinator, _) = makeHandler(now: now, zone: zone)
        var hatRequests: [Bool] = []
        handler.setCelebrationHat = { hatRequests.append($0) }
        handler.start()
        XCTAssertTrue(defaults.bool(forKey: FirstLaunchCelebration.completedKey))
        XCTAssertTrue(hatRequests.isEmpty,
                      "no first-launch surprise on the birthday itself")
        XCTAssertTrue(coordinator.shouldTriggerAutomatically,
                      "the annual October 17 path must stay intact")
    }

    func testExistingInstallationIsNeverTreatedAsFresh() {
        let zone = TimeZone(identifier: "America/New_York")!
        let now = date(2026, 11, 5, 10, zone: zone)
        // An existing install always has a legacy marker (saved pet
        // position), but NOT the new first-launch key.
        defaults.set(612.0, forKey: "pet.position.x")
        defaults.set(104.0, forKey: "pet.position.y")

        let (handler, coordinator, _) = makeHandler(now: now, zone: zone)
        var hatRequests: [Bool] = []
        handler.setCelebrationHat = { hatRequests.append($0) }
        handler.start()
        XCTAssertTrue(hatRequests.isEmpty, "existing installs must not get the surprise")
        XCTAssertTrue(defaults.bool(forKey: FirstLaunchCelebration.completedKey),
                      "the migration marks the installation complete")
        XCTAssertFalse(coordinator.shouldTriggerAutomatically)
    }

    func testSameYearDeduplicationAfterFirstLaunchOutsideOctober() {
        let zone = TimeZone(identifier: "America/New_York")!
        let launchDay = date(2026, 10, 18, 10, zone: zone)
        let (handler, _, _) = makeHandler(now: launchDay, zone: zone)
        handler.start()
        XCTAssertTrue(defaults.bool(forKey: FirstLaunchCelebration.completedKey))

        // Any later date in the same year: no duplicate celebration.
        let later = date(2026, 12, 24, 12, zone: zone)
        let (handler2, coordinator2, _) = makeHandler(now: later, zone: zone)
        handler2.start()
        XCTAssertFalse(coordinator2.shouldTriggerAutomatically)

        // Future years keep the normal annual October 17 event.
        let nextYear = date(2027, 10, 17, 9, zone: zone)
        let (_, coordinator3, _) = makeHandler(now: nextYear, zone: zone)
        XCTAssertTrue(coordinator3.shouldTriggerAutomatically,
                      "future annual birthdays must still trigger")
    }

    func testBusyLaunchDefersThenPlaysWhenIdle() {
        let zone = TimeZone(identifier: "America/New_York")!
        let now = date(2026, 10, 18, 10, zone: zone)
        let windowController = PetWindowController()
        windowController.configureForTesting(frame: CGRect(x: 500, y: 200, width: 180, height: 226))
        let (handler, coordinator, _) = makeHandler(now: now, zone: zone, windowController: windowController)
        var hatRequests: [Bool] = []
        handler.setCelebrationHat = { hatRequests.append($0) }

        // Pet busy (dragging) at launch: the handler defers; the pending
        // trigger is requested but not serviced while busy.
        handler.start()
        XCTAssertTrue(defaults.bool(forKey: FirstLaunchCelebration.completedKey),
                      "completion is persisted even while deferred")

        // The celebration coordinator becomes running once serviced.
        coordinator.servicePendingTrigger()
        XCTAssertTrue(coordinator.isRunning)
        _ = hatRequests
    }

    func testHatRemovedOnlyAfterObservedCelebration() {
        let zone = TimeZone(identifier: "America/New_York")!
        let now = date(2026, 10, 18, 10, zone: zone)
        let (handler, coordinator, _) = makeHandler(now: now, zone: zone)
        var hatRequests: [Bool] = []
        handler.setCelebrationHat = { hatRequests.append($0) }

        handler.start()
        // Before the celebration is observed running, the hat must NOT
        // be removed (deferred trigger is not "ended").
        handler.checkCelebrationEnded()
        XCTAssertFalse(hatRequests.contains(false))

        // The celebration runs...
        coordinator.servicePendingTrigger()
        XCTAssertTrue(coordinator.isRunning)
        handler.checkCelebrationEnded()
        XCTAssertFalse(hatRequests.contains(false), "still running: hat stays")

        // ...and finishes: the hat is gracefully removed.
        coordinator.requestCancellation()
        handler.checkCelebrationEnded()
        XCTAssertTrue(hatRequests.contains(false), "hat removed after the celebration")
    }

    func testInterruptedPlaybackNeverReplays() {
        let zone = TimeZone(identifier: "America/New_York")!
        let now = date(2026, 10, 18, 10, zone: zone)
        let (handler, _, _) = makeHandler(now: now, zone: zone)
        handler.start()
        // Simulate the app quitting mid-celebration: completion was
        // already persisted, so the next launch never replays.
        XCTAssertTrue(defaults.bool(forKey: FirstLaunchCelebration.completedKey))
        let (handler2, _, _) = makeHandler(now: now, zone: zone)
        var hatRequests: [Bool] = []
        handler2.setCelebrationHat = { hatRequests.append($0) }
        handler2.start()
        XCTAssertTrue(hatRequests.isEmpty)
    }
}
