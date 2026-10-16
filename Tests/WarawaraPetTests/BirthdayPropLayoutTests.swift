import XCTest
@testable import WarawaraPet

/// Stable prop layout, stationary envelope invariants, and the letter
/// window close regression (pet must never disappear).
final class BirthdayPropLayoutTests: XCTestCase {
    private let petFrame = CGRect(x: 400, y: 300, width: 200, height: 226)
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let cakePanel = CGSize(width: 200, height: 230)
    private let envelopePanel = CGSize(width: 100, height: 100)

    // MARK: - Layout model

    func testPropsRestInFrontOfPetWithoutOverlappingBody() {
        let origins = BirthdayPropLayout.deliveryOrigins(
            petFrame: petFrame,
            cakePanelSize: cakePanel,
            envelopePanelSize: envelopePanel,
            visibleFrame: visibleFrame
        )
        let body = BirthdayPropLayout.petBodyRect(petFrame: petFrame)
        let cakeRect = CGRect(origin: origins.cake, size: cakePanel)
        let envelopeRect = CGRect(origin: origins.envelope, size: envelopePanel)
        XCTAssertFalse(cakeRect.intersects(body), "cake must not clip into the pet")
        XCTAssertFalse(envelopeRect.intersects(body), "envelope must not clip into the pet")
        XCTAssertFalse(cakeRect.intersects(envelopeRect), "props must not overlap each other")
    }

    func testPropsRestNearTheDesktopPlane() {
        let origins = BirthdayPropLayout.deliveryOrigins(
            petFrame: petFrame,
            cakePanelSize: cakePanel,
            envelopePanelSize: envelopePanel,
            visibleFrame: visibleFrame
        )
        // Bottoms sit near the pet window baseline (the desktop plane).
        XCTAssertEqual(origins.cake.y + cakePanel.height, petFrame.minY + 46 + 230 / 2, accuracy: 0.5)
        XCTAssertLessThan(abs((origins.cake.y + cakePanel.height) - (petFrame.minY + 46 + 115)), 200)
        XCTAssertGreaterThan(origins.cake.y, petFrame.minY - 300)
        XCTAssertGreaterThan(origins.envelope.y, petFrame.minY - 200)
    }

    func testDeliveryOriginsAreClampedToVisibleFrame() {
        let tiny = CGRect(x: 2, y: 2, width: 100, height: 80)
        let origins = BirthdayPropLayout.deliveryOrigins(
            petFrame: tiny,
            cakePanelSize: cakePanel,
            envelopePanelSize: envelopePanel,
            visibleFrame: visibleFrame
        )
        for origin in [origins.cake, origins.envelope] {
            XCTAssertGreaterThanOrEqual(origin.x, visibleFrame.minX + 4 - 0.01)
            XCTAssertGreaterThanOrEqual(origin.y, visibleFrame.minY + 4 - 0.01)
            XCTAssertLessThanOrEqual(origin.x + cakePanel.width, visibleFrame.maxX + 0.01)
            XCTAssertLessThanOrEqual(origin.y + cakePanel.height, visibleFrame.maxY + 0.01)
        }
    }

    func testLayoutIsDeterministic() {
        let a = BirthdayPropLayout.deliveryOrigins(
            petFrame: petFrame, cakePanelSize: cakePanel,
            envelopePanelSize: envelopePanel, visibleFrame: visibleFrame
        )
        let b = BirthdayPropLayout.deliveryOrigins(
            petFrame: petFrame, cakePanelSize: cakePanel,
            envelopePanelSize: envelopePanel, visibleFrame: visibleFrame
        )
        XCTAssertEqual(a.cake, b.cake)
        XCTAssertEqual(a.envelope, b.envelope)
    }

    // MARK: - Ascent exit continuity

    func testExitVelocityBlendIsContinuousAndMonotonic() {
        let target: CGFloat = 45
        var previous: CGFloat = 0
        for _ in 0..<60 {
            let blended = GroupMotionMath.exitVelocityBlend(
                current: previous, target: target, dt: 1.0 / 60.0, timeConstant: 0.35
            )
            XCTAssertGreaterThanOrEqual(blended, previous - 0.0001, "velocity must approach monotonically")
            XCTAssertLessThanOrEqual(blended, target + 0.0001, "velocity must never overshoot the slow speed")
            previous = blended
        }
        XCTAssertEqual(previous, target, accuracy: 0.5, "velocity must converge to the exit speed")
    }

    func testExitVelocityBlendHasNoJumpAtAnyDt() {
        for dt in [0.001, 0.016, 0.05, 0.1, 0.25] {
            let blended = GroupMotionMath.exitVelocityBlend(
                current: 30, target: 45, dt: dt, timeConstant: 0.35
            )
            XCTAssertTrue(blended >= 30 && blended <= 45, "dt \(dt): blend must stay bounded")
        }
    }

    // MARK: - Letter close regression

    func testLetterCloseDoesNotDisturbCoordinatorState() {
        let coordinator = BirthdayEventCoordinator(
            clock: SystemBirthdayClock(),
            persistence: BirthdayPersistence(defaults: UserDefaults(suiteName: "layout-tests")!)
        )
        let before = coordinator.phase
        // Simulate the letter window closing: the notification must not
        // cancel or complete anything.
        NotificationCenter.default.post(name: .birthdayLetterDidClose, object: nil)
        XCTAssertEqual(coordinator.phase, before, "letter close must not touch the event state")
    }

    func testPresenterLetterCloseReassertsPetVisibility() {
        let windowController = PetWindowController()
        let coordinator = BirthdayEventCoordinator()
        let presenter = BirthdayPresenter(
            windowController: windowController,
            coordinator: coordinator,
            store: .shared
        )
        var reasserted = false
        presenter.reassertPetVisibility = { reasserted = true }
        NotificationCenter.default.post(name: .birthdayLetterDidClose, object: nil)
        XCTAssertTrue(reasserted, "closing the letter must re-assert the pet panel")
    }
}
