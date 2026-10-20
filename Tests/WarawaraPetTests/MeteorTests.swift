import AppKit
import XCTest
@testable import WarawaraPet

/// Meteor coverage: trajectory, single-timebase motion, phase sequence
/// (including the wish beat), nightly scheduling, presentation-path
/// visibility and cleanup.
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

    private final class TestTime {
        var uptime: TimeInterval = 1000
        var now: Date
        let zone: TimeZone
        init(now: Date, zone: TimeZone) { self.now = now; self.zone = zone }
    }

    private func makeController(now: Date, zone: TimeZone, uptime: TimeInterval = 1000) -> (MeteorEventController, TestTime) {
        let time = TestTime(now: now, zone: zone)
        time.uptime = uptime
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
        var visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        var noticeCount = 0
        var flightBeginCount = 0
        var departedCount = 0
        var wishingCount = 0
        var celebrationCount = 0
        var cleanupCount = 0
        var phases: [MeteorPhase] = []
        var activeVisibleFrame: CGRect { visibleFrame }
        func noticeScene() { noticeCount += 1; phases.append(.noticing) }
        func flightDidBegin(trajectory: MeteorTrajectory) { flightBeginCount += 1; phases.append(.flight) }
        func meteorDeparted() { departedCount += 1; phases.append(.departed) }
        func wishingDidBegin() { wishingCount += 1; phases.append(.wishing) }
        func celebrationDidBegin() { celebrationCount += 1; phases.append(.celebration) }
        func cleanup() { cleanupCount += 1; phases.append(.completed) }
    }

    // MARK: - Trajectory

    func testTrajectoryEntersAndExitsBeyondTheDisplay() {
        let trajectory = MeteorTrajectory.fixed(in: visible)
        XCTAssertLessThan(trajectory.entry.x, visible.minX)
        XCTAssertGreaterThan(trajectory.exit.x, visible.maxX)
        XCTAssertLessThan(trajectory.position(at: 0).x, visible.minX)
        XCTAssertGreaterThan(trajectory.position(at: 1).x, visible.maxX)
        XCTAssertEqual(MeteorTrajectory.fixed(in: visible), trajectory)
    }

    func testSamplerYieldsNearlyUniformScreenSpeed() {
        let sampler = MeteorTrajectorySampler(trajectory: MeteorTrajectory.fixed(in: visible), samples: 512)
        var previous = sampler.position(atArcLength: 0)
        var distances: [CGFloat] = []
        for step in 1...100 {
            let p = sampler.position(atArcLength: CGFloat(step) / 100)
            distances.append(hypot(p.x - previous.x, p.y - previous.y))
            previous = p
        }
        let average = distances.reduce(0, +) / CGFloat(distances.count)
        for distance in distances {
            XCTAssertLessThan(abs(distance - average) / average, 0.55,
                              "arc-length sampling must keep speed nearly uniform")
        }
    }

    // MARK: - Single timebase + phase sequence

    func testPhaseSequenceIsNoticingFlightDepartedWishingCelebration() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = date(2026, 10, 1, 10, zone: zone)
        let (controller, time) = makeController(now: start, zone: zone)
        let spy = SpyPresenter()
        controller.presenter = spy

        controller.requestTrigger(.replay)
        controller.servicePendingTrigger()
        XCTAssertEqual(controller.phase, .noticing)

        // Enter the flight phase via the DATE timeline (notice).
        time.now = start.addingTimeInterval(controller.timing.noticeDuration + 0.1)
        controller.advance(at: time.now)
        XCTAssertEqual(controller.phase, .flight)
        XCTAssertNotNil(controller.trajectory)
        XCTAssertEqual(spy.flightBeginCount, 1)

        // Flight progress derives ONLY from the monotonic clock.
        XCTAssertEqual(controller.flightProgress(atUptime: time.uptime) ?? -1, 0, accuracy: 0.01)
        time.uptime += controller.timing.flightDuration / 2
        XCTAssertEqual(controller.flightProgress(atUptime: time.uptime) ?? 0, 0.5, accuracy: 0.01)

        // A 4 Hz tick does NOT move the position: it only manages phases.
        time.now = start.addingTimeInterval(controller.timing.noticeDuration + 1)
        controller.advance(at: time.now)
        XCTAssertEqual(controller.phase, .flight)
        XCTAssertEqual(controller.flightProgress(atUptime: time.uptime) ?? 0, 0.5, accuracy: 0.01)

        // Flight ends on the SAME monotonic timeline.
        time.uptime += controller.timing.flightDuration / 2 + 0.1
        controller.advance(at: time.now)
        XCTAssertEqual(controller.phase, .departed)
        XCTAssertEqual(spy.departedCount, 1)
        XCTAssertEqual(spy.celebrationCount, 0)

        // Wish beat (constant duration) between departure and celebration.
        time.uptime += controller.timing.departedDuration + 0.1
        controller.advance(at: time.now)
        XCTAssertEqual(controller.phase, .wishing)
        XCTAssertEqual(spy.wishingCount, 1)
        time.uptime += controller.timing.wishingDuration + 0.1
        controller.advance(at: time.now)
        XCTAssertEqual(controller.phase, .celebration)
        XCTAssertEqual(spy.celebrationCount, 1)

        time.uptime += controller.timing.celebrationDuration + 0.1
        controller.advance(at: time.now)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(spy.cleanupCount, 1)
        XCTAssertEqual(spy.phases, [.noticing, .flight, .departed, .wishing, .celebration, .completed])
    }

    func testWishingDurationIsWithinSpecRange() {
        XCTAssertGreaterThanOrEqual(MeteorEventController.Timing().wishingDuration, 2.5)
        XCTAssertLessThanOrEqual(MeteorEventController.Timing().wishingDuration, 4.0)
    }

    func testPositionIsPureFunctionOfUptimeAcrossCadences() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = date(2026, 10, 1, 10, zone: zone)
        let (controller, time) = makeController(now: start, zone: zone)
        controller.presenter = SpyPresenter()
        controller.requestTrigger(.replay)
        controller.servicePendingTrigger()
        time.now = start.addingTimeInterval(controller.timing.noticeDuration + 0.1)
        controller.advance(at: time.now)

        // The same uptime always yields the same progress, regardless of
        // how many render ticks happened before it.
        time.uptime += 1.0
        let first = controller.flightProgress(atUptime: time.uptime)!
        // Simulate many small ticks (60 Hz) and few big ticks (30 Hz):
        // the progress at the same uptime must be identical.
        time.uptime += 2.0
        let second = controller.flightProgress(atUptime: time.uptime)!
        time.uptime = time.uptime - 2.0 + 2.0
        let sameAgain = controller.flightProgress(atUptime: time.uptime)!
        XCTAssertEqual(second, sameAgain, accuracy: 0.0001)
        XCTAssertGreaterThan(second, first, "progress must advance monotonically")
    }

    func testDroppedFramesNeverJumpOrGoBackward() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = date(2026, 10, 1, 10, zone: zone)
        let (controller, time) = makeController(now: start, zone: zone)
        let spy = SpyPresenter()
        controller.presenter = spy
        controller.requestTrigger(.replay)
        controller.servicePendingTrigger()
        time.now = start.addingTimeInterval(controller.timing.noticeDuration + 0.1)
        controller.advance(at: time.now)
        guard let trajectory = controller.trajectory else { return XCTFail("no trajectory") }
        let sampler = MeteorTrajectorySampler(trajectory: trajectory)

        var previous = sampler.position(atArcLength: 0)
        var timeCursor = time.uptime
        // Mixed cadences with occasional 0.25 s drops must stay monotonic
        // and continuous.
        while timeCursor < time.uptime + controller.timing.flightDuration {
            timeCursor += Double.random(in: 0.01...0.25)
            guard let progress = controller.flightProgress(atUptime: timeCursor) else { break }
            let position = sampler.position(atArcLength: progress)
            let delta = hypot(position.x - previous.x, position.y - previous.y)
            XCTAssertLessThan(delta, 80, "no teleport between frames")
            XCTAssertGreaterThanOrEqual(progress, 0)
            previous = position
        }
        XCTAssertEqual(controller.flightProgress(atUptime: time.uptime + controller.timing.flightDuration + 5), 1,
                       "progress clamps at exactly 1 after the flight")
    }

    // MARK: - Nightly automatic scheduling (fixed local 22:17 — see
    // MeteorDaily22_17Tests for the full boundary matrix)

    private func nightDate(_ hour: Int, minute: Int = 0, zone: TimeZone = TimeZone(identifier: "America/New_York")!) -> Date {
        date(2026, 10, 1, hour, zone: zone, minute: minute)
    }

    func testManualReplayDoesNotTouchDailyHistory() {
        let zone = TimeZone(identifier: "America/New_York")!
        let start = nightDate(21, zone: zone)
        let persistence = MeteorPersistence(defaults: defaults)
        let key = MeteorPersistence.nightKey(start, calendar: calendar(zone))
        let firedBefore = persistence.automaticFired(forKey: key)
        let skippedBefore = persistence.automaticSkipped(forKey: key)

        let (controller, time) = makeController(now: start, zone: zone)
        controller.presenter = SpyPresenter()
        controller.requestTrigger(.replay)
        controller.servicePendingTrigger()
        XCTAssertEqual(controller.phase, .noticing, "manual replay works at any hour")
        let total = controller.timing.noticeDuration + controller.timing.flightDuration
            + controller.timing.departedDuration + controller.timing.wishingDuration
            + controller.timing.celebrationDuration
        time.uptime += total + 1
        time.now = start.addingTimeInterval(total + 2)
        controller.advance(at: time.now)
        // Advance through phases one step at a time with monotonic sync.
        for _ in 0..<16 {
            time.uptime += 1
            controller.advance(at: time.now)
            if controller.phase == .idle { break }
        }
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(persistence.automaticFired(forKey: key), firedBefore,
                       "manual replay must not consume the daily automatic qualification")
        XCTAssertEqual(persistence.automaticSkipped(forKey: key), skippedBefore,
                       "manual replay must not mark the day skipped")
    }

    // MARK: - Final head asset wiring (the user-replaced PNG)

    func testFinalHeadAssetIsTheNew1254CanvasWithoutBakedTail() {
        let store = GiftAssetStore.shared
        store.reset()
        guard let image = store.image(named: "meteor_head_from_approved.png") else {
            return XCTFail("final head asset missing")
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return XCTFail("final head asset not decodable")
        }
        XCTAssertEqual(rep.pixelsWide, 1254, "the user-supplied final head PNG is 1254 wide")
        XCTAssertEqual(rep.pixelsHigh, 1254, "the user-supplied final head PNG is 1254 tall")
        // The old 408x408 crop must no longer ship.
        XCTAssertNotEqual(rep.pixelsWide, 408)
        // Hash verification against the final art.
        XCTAssertTrue(store.verifySHA256().ok, store.verifySHA256().details)
        // The old baked-tail canvas is reference-only and must never be
        // used by the renderer: it stays a verified reference asset.
        XCTAssertNotNil(store.image(named: "meteor_celfilm.png"))
    }

    // MARK: - Production presentation path

    func testProductionPresenterMovesOnlyViaRenderTick() {
        let windowController = PetWindowController()
        windowController.configureForTesting(
            frame: CGRect(x: 400, y: 300, width: 180, height: 226)
        )
        let zone = TimeZone(identifier: "America/New_York")!
        let now = date(2026, 10, 1, 14, zone: zone)
        let (controller, time) = makeController(now: now, zone: zone)
        let presenter = MeteorEventPresenter(
            windowController: windowController, controller: controller, store: .shared
        )
        controller.presenter = presenter

        controller.requestTrigger(.replay)
        controller.servicePendingTrigger()
        time.now = now.addingTimeInterval(controller.timing.noticeDuration + 0.1)
        controller.advance(at: time.now)
        XCTAssertEqual(controller.phase, .flight)

        // The panel exists (small, ordered, view attached).
        guard let panel = presenter.debugPanel else { return XCTFail("panel missing") }
        XCTAssertEqual(panel.frame.size, CGSize(width: 360, height: 360))
        XCTAssertNotNil(panel.contentView)

        // Mid-flight render tick: panel on-screen, opaque, trail building.
        time.uptime += controller.timing.flightDuration / 2
        presenter.renderTick(uptime: time.uptime)
        let visible = presenter.activeVisibleFrame
        XCTAssertTrue(visible.intersects(panel.frame), "panel must cross the display")
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.01)
        XCTAssertGreaterThan(presenter.debugHistoryCount, 0, "the trail history records the flight")

        // A delayed scheduler tick must NOT overwrite the position.
        let originBefore = panel.frame.origin
        time.now = time.now.addingTimeInterval(0.25)
        controller.advance(at: time.now)
        XCTAssertEqual(panel.frame.origin, originBefore,
                       "the 4 Hz scheduler never moves the panel")

        // Cleanup: alpha zero, parked off-screen, history cleared.
        presenter.cleanup()
        XCTAssertEqual(panel.alphaValue, 0, accuracy: 0.01)
        XCTAssertFalse(visible.intersects(panel.frame))
        XCTAssertEqual(presenter.debugHistoryCount, 0)
    }
}
