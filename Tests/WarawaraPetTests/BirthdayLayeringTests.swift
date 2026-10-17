import AppKit
import XCTest
@testable import WarawaraPet

/// Sustained prop-over-companion ordering regression coverage. The
/// cake/tray and envelope must stay in FRONT of companion bodies through
/// carrying, delivery, panel reuse, and the letter-close pet re-assert.
final class BirthdayLayeringTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "BirthdayLayeringTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// Spy panel: counts real orderFrontRegardless calls so the tests
    /// observe the ACTUAL AppKit ordering boundary.
    private final class OrderingSpyPanel: BirthdayPropPanel {
        private(set) var orderFrontCount = 0
        override func orderFrontRegardless() {
            orderFrontCount += 1
            super.orderFrontRegardless()
        }
    }

    private func makePresenter(
        windowController: PetWindowController,
        panels: inout [OrderingSpyPanel]
    ) -> BirthdayPresenter {
        let persistence = BirthdayPersistence(defaults: defaults)
        let coordinator = BirthdayEventCoordinator(persistence: persistence)
        let presenter = BirthdayPresenter(
            windowController: windowController,
            coordinator: coordinator,
            store: .shared,
            persistence: persistence
        )
        presenter.makePropPanel = { size, interactive in
            let panel = OrderingSpyPanel(size: size, interactive: interactive)
            panels.append(panel)
            return panel
        }
        return presenter
    }

    func testPropsRaisedAboveCompanionsAndSustainedThroughLateOrderFrontCalls() {
        let windowController = PetWindowController()
        var panels: [OrderingSpyPanel] = []
        let presenter = makePresenter(windowController: windowController, panels: &panels)

        // Carrying starts: panels created and ordered front once each.
        presenter.presentCarriedProps()
        XCTAssertEqual(panels.count, 2, "cake + envelope panels")
        XCTAssertTrue(panels.allSatisfy { $0.orderFrontCount == 1 })

        // Companion panels get (re-)ordered front AFTER this (group
        // start, pooled reuse): every one of those passes must re-assert
        // the props in front.
        presenter.groupActivityChanged(true)
        XCTAssertTrue(presenter.propsRaisedAboveCompanions)
        presenter.reassertLayering() // late companion orderFront (fresh panels)
        presenter.reassertLayering() // late companion orderFront (pool reuse)
        XCTAssertEqual(panels.map(\.orderFrontCount), [4, 4],
                       "props must be re-raised after EVERY companion ordering pass")
        XCTAssertGreaterThanOrEqual(presenter.layeringReassertCount, 3)
    }

    func testDeliveryAndLetterCloseKeepPropsInFrontOfPetPanel() {
        let windowController = PetWindowController()
        windowController.configureForTesting(
            frame: CGRect(x: 400, y: 300, width: 180, height: 200)
        )
        var panels: [OrderingSpyPanel] = []
        let presenter = makePresenter(windowController: windowController, panels: &panels)

        var petReasserts = 0
        // Production wiring: the letter close re-asserts the pet panel
        // AND re-raises the props above it.
        presenter.reassertPetVisibility = { [weak presenter] in
            petReasserts += 1
            presenter?.reassertLayering()
        }

        presenter.presentCarriedProps()
        let beforeDelivery = presenter.layeringReassertCount
        presenter.deliverPropsToPet()
        XCTAssertGreaterThan(presenter.layeringReassertCount, beforeDelivery,
                             "delivery must re-assert the final desktop layering")

        NotificationCenter.default.post(name: .birthdayLetterDidClose, object: nil)
        XCTAssertEqual(petReasserts, 1, "letter close re-asserts the pet panel")
        XCTAssertTrue(
            panels.allSatisfy { $0.orderFrontCount >= 3 },
            "props must be above the re-asserted pet panel after letter close"
        )
    }

    func testCompanionPanelsOrderedObserverReassertsProps() {
        // The AppDelegate wires this callback to the presenter; the
        // presenter side must re-assert every time it fires.
        let windowController = PetWindowController()
        var panels: [OrderingSpyPanel] = []
        let presenter = makePresenter(windowController: windowController, panels: &panels)
        presenter.presentCarriedProps()

        let observer: () -> Void = { [weak presenter] in presenter?.reassertLayering() }
        windowController.setCompanionPanelsOrderedObserver(observer)
        // Simulate the group controller notifying after preparePanels.
        observer()
        observer()
        XCTAssertTrue(
            panels.allSatisfy { $0.orderFrontCount >= 3 },
            "the ordered-observer path must keep props in front"
        )
    }

    func testGroupControllerFiresOrderingCallbackAfterPreparePanels() {
        let windowController = PetWindowController()
        windowController.configureForTesting(
            frame: CGRect(x: 200, y: 200, width: 180, height: 200)
        )
        let sequence = GroupSequenceController(windowController: windowController)
        var orderedCount = 0
        sequence.onCompanionPanelsOrdered = { orderedCount += 1 }
        sequence.start()
        XCTAssertEqual(orderedCount, 1,
                       "preparePanels orders companions front and MUST notify layering afterwards")
        sequence.cancel()
        // Let the fade finish so cleanup invalidates the timer.
        RunLoop.current.run(until: Date().addingTimeInterval(3))
    }
}
