import AppKit
import XCTest
@testable import WarawaraPet

/// Second fix pass: event attention targets, envelope retirement,
/// double-click reopen, and carry-modular resource hooks.
final class BirthdaySecondFixTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "BirthdaySecondFixTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Attention target model

    func testAttentionTargetsFollowEventPhases() {
        XCTAssertEqual(BirthdayAttentionTarget.expected(for: .noticing), .leadCompanion)
        XCTAssertEqual(BirthdayAttentionTarget.expected(for: .gathering), .leadCompanion)
        XCTAssertEqual(BirthdayAttentionTarget.expected(for: .celebrating), .cakeDelivery)
        XCTAssertEqual(BirthdayAttentionTarget.expected(for: .awaitingLetter), .envelopeDelivery)
        XCTAssertEqual(BirthdayAttentionTarget.expected(for: .completed), .envelopeDelivery)
        XCTAssertEqual(BirthdayAttentionTarget.expected(for: .idle), .none)
        XCTAssertEqual(BirthdayAttentionTarget.expected(for: .cancelled), .none)
    }

    func testAttentionDirectionSignsAndDeadband() {
        let center = CGPoint(x: 100, y: 100)
        let right = EventAttentionMath.direction(from: center, to: CGPoint(x: 200, y: 100))
        XCTAssertEqual(right.dx, 1, accuracy: 0.01)
        XCTAssertEqual(right.dy, 0, accuracy: 0.01)

        let above = EventAttentionMath.direction(from: center, to: CGPoint(x: 100, y: 200))
        XCTAssertEqual(above.dy, 1, accuracy: 0.01, "up-positive convention")

        let below = EventAttentionMath.direction(from: center, to: CGPoint(x: 100, y: 0))
        XCTAssertEqual(below.dy, -1, accuracy: 0.01)

        XCTAssertEqual(
            EventAttentionMath.direction(from: center, to: CGPoint(x: 101, y: 100)),
            .zero,
            "tiny movements are deadbanded"
        )
        XCTAssertTrue(EventAttentionMath.differs(CGVector(dx: 1, dy: 0), CGVector(dx: 0.2, dy: 0)))
        XCTAssertFalse(EventAttentionMath.differs(CGVector(dx: 1, dy: 0), CGVector(dx: 0.95, dy: 0)))
    }

    func testCoordinatorAdvancesAttentionTargetThroughTheEvent() {
        let zone = TimeZone(identifier: "America/New_York")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 17
        components.hour = 9; components.timeZone = zone
        let start = cal.date(from: components)!

        final class FixedClock: BirthdayClock {
            var currentNow: Date
            let calendar: Calendar
            init(now: Date, calendar: Calendar) { self.currentNow = now; self.calendar = calendar }
            func now() -> Date { currentNow }
        }
        let clock = FixedClock(now: start, calendar: cal)
        let coordinator = BirthdayEventCoordinator(
            clock: clock,
            persistence: BirthdayPersistence(defaults: defaults)
        )
        class NoopPresenter: BirthdayEventPresenting {
            func noticeCompanionsArriving() {}
            func presentCarriedProps() {}
            func deliverPropsToPet() {}
            func activateEnvelope() {}
            func hideCake() {}
            func startCompanionGroup() {}
            func cancelCompanionGroup() {}
            func performMainPetHop() {}
            func clearAttention() {}
            func envelopeDidBecomeAvailable() {}
        }
        coordinator.presenter = NoopPresenter()

        coordinator.requestTrigger(.replay)
        coordinator.servicePendingTrigger()
        XCTAssertEqual(coordinator.attentionTarget, .leadCompanion)

        clock.currentNow = start.addingTimeInterval(3.0)
        coordinator.advance(at: clock.currentNow)
        XCTAssertEqual(coordinator.attentionTarget, .leadCompanion, "gathering still tracks the lead carrier")

        coordinator.companionGroupDidStart()
        let gatherStart = clock.currentNow
        clock.currentNow = gatherStart.addingTimeInterval(5.2)
        coordinator.advance(at: clock.currentNow)
        XCTAssertEqual(coordinator.attentionTarget, .cakeDelivery)

        coordinator.companionGroupDidEnd()
        XCTAssertEqual(coordinator.phase, .idle, "completion resets the event")
        XCTAssertEqual(coordinator.attentionTarget, .none, "reset clears the target")
        XCTAssertEqual(
            BirthdayAttentionTarget.expected(for: .awaitingLetter),
            .envelopeDelivery,
            "the envelope phase attends the envelope"
        )
    }

    // MARK: - Envelope retirement

    func testEnvelopeRetiresAfterFirstRead() {
        let windowController = PetWindowController()
        let persistence = BirthdayPersistence(defaults: defaults)
        persistence.markEnvelopeUnlocked()
        let coordinator = BirthdayEventCoordinator(persistence: persistence)
        let presenter = BirthdayPresenter(
            windowController: windowController,
            coordinator: coordinator,
            store: .shared,
            persistence: persistence
        )
        presenter.reassertPetVisibility = {}
        presenter.delivered = true
        presenter.activateEnvelope()
        XCTAssertEqual(presenter.letterReadCount, 0)

        NotificationCenter.default.post(name: .birthdayLetterDidClose, object: nil)
        XCTAssertEqual(presenter.letterReadCount, 1)
        XCTAssertTrue(presenter.envelopeRetiredThisSession, "the large envelope retires after the first read")
        XCTAssertTrue(persistence.envelopeRetired)

        NotificationCenter.default.post(name: .birthdayLetterDidClose, object: nil)
        XCTAssertEqual(presenter.letterReadCount, 2)
        XCTAssertTrue(presenter.envelopeRetiredThisSession, "retirement is idempotent")
    }

    func testLetterRemainsAvailableAfterRetirement() {
        let persistence = BirthdayPersistence(defaults: defaults)
        persistence.markEnvelopeUnlocked()
        persistence.markEnvelopeRetired()
        XCTAssertTrue(persistence.isLetterAvailable, "retirement never removes letter access")
    }

    func testDoubleClickReopenRequiresLetterAvailability() {
        let windowController = PetWindowController()
        let persistence = BirthdayPersistence(defaults: defaults)
        let coordinator = BirthdayEventCoordinator(persistence: persistence)
        let presenter = BirthdayPresenter(
            windowController: windowController,
            coordinator: coordinator,
            store: .shared,
            persistence: persistence
        )
        // Locked + not the birthday: double-click does nothing.
        presenter.openLetterForDoubleClick()
        XCTAssertEqual(presenter.letterPresentedCount, 0)

        persistence.markEnvelopeUnlocked()
        presenter.openLetterForDoubleClick()
        XCTAssertEqual(presenter.letterPresentedCount, 1, "double-click reopens after retirement")
    }

    func testPetDoubleClickRoutesToCallbackAndSkipsSquash() throws {
        let windowController = PetWindowController()
        let motion = PetMotionController(windowController: windowController)
        let store = PetPositionStore(defaults: defaults)
        let controller = PetController(
            windowController: windowController,
            motionController: motion,
            positionStore: store
        )
        let interaction = PetInteractionController(
            windowController: windowController,
            controller: controller
        )
        var doubleClicked = false
        interaction.onDoubleClick = { doubleClicked = true }

        guard let doubleEvent = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 2,
            clickCount: 2,
            pressure: 1
        ) else {
            throw XCTSkip("cannot synthesize mouse events")
        }
        interaction.mouseDown(at: doubleEvent)
        XCTAssertTrue(doubleClicked)
        XCTAssertEqual(controller.state, .idle, "double-click must not trigger the squash")

        guard let singleEvent = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 3,
            clickCount: 1,
            pressure: 1
        ) else {
            throw XCTSkip("cannot synthesize mouse events")
        }
        interaction.mouseDown(at: singleEvent)
        XCTAssertEqual(controller.state, .clicked, "single click keeps the accepted squash")
    }

    func testCarryHelperSlotsFallBackGracefully() {
        // v4 optional helpers do not exist yet: the slots must return
        // nil without affecting anything.
        XCTAssertNil(BirthdayAssetStore.shared.optionalImage(named: "carry_tray.png"))
        XCTAssertNil(BirthdayAssetStore.shared.optionalImage(named: "envelope_band.png"))
    }

    // MARK: - Phase 6B birthday polish

    func testApproachBobIsContinuousBoundedAndSettles() {
        // Zero at rest; bounded by the amplitude; intensity follows
        // speed so decelerating companions settle softly.
        XCTAssertEqual(
            GroupMotionMath.approachBob(speed: 0, maxAmplitude: 11, phase: 0, time: 1, hopPeriod: 0.55),
            0,
            accuracy: 0.0001
        )
        var maxValue: CGFloat = 0
        var previous = GroupMotionMath.approachBob(
            speed: 60, maxAmplitude: 11, phase: 0.4, time: 0, hopPeriod: 0.55
        )
        for step in 1..<120 {
            let t = TimeInterval(step) / 60.0
            let bob = GroupMotionMath.approachBob(
                speed: 60, maxAmplitude: 11, phase: 0.4, time: t, hopPeriod: 0.55
            )
            XCTAssertLessThanOrEqual(abs(bob), 11 + 0.001, "bob must stay bounded")
            XCTAssertLessThanOrEqual(abs(bob - previous), 11 * 2 * .pi / 60.0 / 0.55 + 0.15,
                                     "bob must be continuous between 60 Hz samples")
            maxValue = max(maxValue, abs(bob))
            previous = bob
        }
        XCTAssertGreaterThan(maxValue, 5, "fast companions must visibly bounce")

        let slow = GroupMotionMath.approachBob(
            speed: 8, maxAmplitude: 11, phase: 0.4, time: 2, hopPeriod: 0.55
        )
        XCTAssertLessThan(abs(slow), abs(previous) + 0.001, "slow companions settle toward no bob")
    }

    func testPropsRaiseAboveCompanionsWhenGroupStarts() {
        let windowController = PetWindowController()
        let persistence = BirthdayPersistence(defaults: defaults)
        let coordinator = BirthdayEventCoordinator(persistence: persistence)
        let presenter = BirthdayPresenter(
            windowController: windowController,
            coordinator: coordinator,
            store: .shared,
            persistence: persistence
        )
        presenter.presentCarriedProps()
        XCTAssertFalse(presenter.propsRaisedAboveCompanions)
        presenter.groupActivityChanged(true)
        XCTAssertTrue(
            presenter.propsRaisedAboveCompanions,
            "props must be re-ordered in front of the carrier companions"
        )
    }
}
