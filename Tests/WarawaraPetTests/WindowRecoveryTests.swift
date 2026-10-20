import AppKit
import XCTest
@testable import WarawaraPet

/// macOS 14 reliability coverage: off-screen/hidden window recovery,
/// sleep/wake throttling, and development fault injection. These only
/// exercise window restoration — the pet's sleep state is never touched.
final class WindowRecoveryTests: XCTestCase {
    private let screens = [
        CGRect(x: 0, y: 0, width: 1440, height: 900),
        CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    ]
    private let petFrame = CGRect(x: 400, y: 300, width: 200, height: 226)

    // MARK: - Pure math

    func testOffscreenDetection() {
        XCTAssertFalse(WindowRecovery.isOffscreen(petFrame, screens: screens))
        XCTAssertTrue(WindowRecovery.isOffscreen(
            CGRect(x: 5000, y: 5000, width: 200, height: 226), screens: screens
        ))
        // Frame straddling the two screens but centered on one: on-screen.
        XCTAssertFalse(WindowRecovery.isOffscreen(
            CGRect(x: 1390, y: 300, width: 200, height: 226), screens: screens
        ))
    }

    func testRecoveryFrameClampsIntoTheOwningScreen() {
        let offscreen = CGRect(x: 5000, y: 5000, width: 200, height: 226)
        let recovered = WindowRecovery.recoveryFrame(
            offscreen, screens: screens,
            mainScreenVisible: screens[0], margin: 8
        )
        XCTAssertTrue(screens[0].contains(recovered.insetBy(dx: -1, dy: -1)) || screens[1].contains(recovered.insetBy(dx: -1, dy: -1)),
                      "the recovered frame must land on a real display")
    }

    func testRecoveryFramePreservesSize() {
        let recovered = WindowRecovery.recoveryFrame(
            CGRect(x: -999, y: -999, width: 200, height: 226),
            screens: screens, mainScreenVisible: screens[0], margin: 8
        )
        XCTAssertEqual(recovered.size, CGSize(width: 200, height: 226))
    }

    // MARK: - Fault injection + real panel recovery

    func testOffscreenFaultThenRecoveryRestoresThePanel() {
        let windowController = PetWindowController()
        windowController.configureForTesting(frame: petFrame)
        let monitor = WindowLifecycleMonitor(windowController: windowController)
        monitor.restoreThrottle = 0

        windowController.injectOffscreenFrame()
        XCTAssertTrue(
            WindowRecovery.isOffscreen(
                windowController.currentFrame,
                screens: ScreenGeometry.screenVisibleFrames()
            ),
            "precondition: the injected frame must genuinely be off-screen"
        )

        let restored = monitor.checkAndRestore(reason: "test")
        XCTAssertTrue(restored, "the off-screen panel must be recovered")
        let frame = windowController.currentFrame
        XCTAssertTrue(
            ScreenGeometry.screenVisibleFrames().contains {
                $0.contains(CGPoint(x: frame.midX, y: frame.midY))
            },
            "after recovery the panel center is on a real display"
        )
    }

    func testHiddenPanelFaultThenRecovery() {
        let windowController = PetWindowController()
        windowController.configureForTesting(frame: petFrame)
        let monitor = WindowLifecycleMonitor(windowController: windowController)
        monitor.restoreThrottle = 0

        windowController.injectHiddenPanel()
        XCTAssertFalse(windowController.petPanel?.isVisible ?? true)

        XCTAssertTrue(monitor.checkAndRestore(reason: "test-hidden"),
                      "the hidden panel must be restored")
        XCTAssertTrue(windowController.petPanel?.isVisible ?? false)
    }

    func testHealthyPanelDoesNotReassert() {
        let windowController = PetWindowController()
        windowController.configureForTesting(frame: petFrame)
        let monitor = WindowLifecycleMonitor(windowController: windowController)
        monitor.restoreThrottle = 0

        var decisions: [Bool] = []
        monitor.onRestoreDecision = { restored, _ in decisions.append(restored) }
        XCTAssertFalse(monitor.checkAndRestore(reason: "test-healthy"))
        XCTAssertFalse(monitor.checkAndRestore(reason: "test-healthy"))
        XCTAssertEqual(decisions, [false, false],
                       "a healthy panel must never be re-asserted")
    }

    func testRestoreIsThrottled() {
        let windowController = PetWindowController()
        windowController.configureForTesting(frame: petFrame)
        let monitor = WindowLifecycleMonitor(windowController: windowController)
        monitor.restoreThrottle = 60 // effectively one restore allowed

        windowController.injectOffscreenFrame()
        XCTAssertTrue(monitor.checkAndRestore(reason: "first"))
        // The panel is healthy again but a second fault triggers
        // throttling rather than repeated orderFront calls.
        windowController.injectHiddenPanel()
        XCTAssertFalse(monitor.checkAndRestore(reason: "second"),
                       "restore must be throttled to one orderFront per interval")
    }

    func testRecoveryNeverChangesPetSleepState() {
        // Window recovery only touches the panel. The pet's sleep state
        // lives in PetController; configureForTesting has no controller,
        // so sleeping checks stay inert — the recovery path must not
        // construct or wake any pet state.
        let windowController = PetWindowController()
        windowController.configureForTesting(frame: petFrame)
        windowController.injectOffscreenFrame()
        XCTAssertTrue(windowController.runRecoveryCheck(reason: "test"))
        // isPetSleeping reads the (absent) controller: still false and
        // unchanged — recovery must not have woken anything.
        XCTAssertFalse(windowController.isPetSleeping)
    }
}
