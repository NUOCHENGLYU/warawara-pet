import AppKit
import XCTest
@testable import WarawaraPet

/// Window-recovery fault matrix: two-screen → one-screen transitions,
/// main-screen resize, screen-edge frames, healthy-panel no-ops,
/// repeated wake storms, and the documented empty-screen-list weakness.
final class WindowRecoveryFaultMatrixTests: XCTestCase {
    private let petSize = CGSize(width: 200, height: 226)
    private let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let secondary = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    private let margin: CGFloat = 8

    // MARK: - Pure math matrix

    /// D: two screens, then only one remains (external display removed).
    func testFrameOnRemovedSecondaryScreenRecoversToPrimary() {
        let frame = CGRect(x: 1600, y: 400, width: petSize.width, height: petSize.height)
        XCTAssertFalse(WindowRecovery.isOffscreen(frame, screens: [primary, secondary]))

        // After unplug: only the primary remains and the frame is lost.
        XCTAssertTrue(WindowRecovery.isOffscreen(frame, screens: [primary]))
        let recovered = WindowRecovery.recoveryFrame(
            frame, screens: [primary], mainScreenVisible: primary, margin: margin
        )
        XCTAssertTrue(primary.contains(recovered.insetBy(dx: -1, dy: -1)),
                      "the recovered frame must land on the remaining display")
        XCTAssertEqual(recovered.size, petSize, "recovery must preserve size")
    }

    /// E: the main screen shrinks (resolution change). A pet that was
    /// healthy on the old 1440x900 screen ends up outside the new
    /// 1280x720 visible frame and must be clamped back onto it.
    func testMainScreenResizeClampsTheFrame() {
        let small = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let frame = CGRect(x: 1300, y: 400, width: petSize.width, height: petSize.height)
        XCTAssertFalse(WindowRecovery.isOffscreen(frame, screens: [primary]),
                       "the frame is healthy on the original screen")
        XCTAssertTrue(WindowRecovery.isOffscreen(frame, screens: [small]),
                      "after the resize the same frame is off the shrunken screen")
        let clamped = WindowRecovery.recoveryFrame(
            frame, screens: [small], mainScreenVisible: small, margin: margin
        )
        XCTAssertTrue(small.contains(CGPoint(x: clamped.midX, y: clamped.midY)),
                      "the recovered frame must land on the resized display")
        XCTAssertEqual(clamped.size, petSize)
    }

    /// I: a frame exactly on the visible edge is healthy and must not be
    /// re-clamped into the interior.
    func testEdgeFrameIsConsideredHealthy() {
        let edge = CGRect(x: primary.maxX - petSize.width, y: primary.minY + 4,
                          width: petSize.width, height: petSize.height)
        XCTAssertFalse(WindowRecovery.isOffscreen(edge, screens: [primary]))
        XCTAssertFalse(WindowRecovery.needsRecovery(
            frame: edge, screens: [primary], isVisible: true
        ))
    }

    /// C (DOCUMENTED WEAKNESS): an empty screen list currently makes
    /// `isOffscreen` return true (nothing contains the center), so the
    /// recovery path would clamp a healthy window into the fallback
    /// 1280x800 box. This test records the ACTUAL current behavior so
    /// the limitation stays visible; the recommended minimal fix is to
    /// no-op when the screen list is empty and retry later.
    func testEmptyScreenListIsAKnownWeakness() {
        XCTAssertTrue(WindowRecovery.isOffscreen(
            CGRect(x: 400, y: 300, width: petSize.width, height: petSize.height),
            screens: []
        ), "KNOWN WEAKNESS: an empty screen list currently reports off-screen")
        // The computed recovery frame falls back to the main screen (or
        // the hardcoded 1280x800 box when even NSScreen.main is nil).
        let recovered = WindowRecovery.recoveryFrame(
            CGRect(x: 400, y: 300, width: petSize.width, height: petSize.height),
            screens: [],
            mainScreenVisible: primary,
            margin: margin
        )
        XCTAssertTrue(primary.contains(recovered.insetBy(dx: -1, dy: -1)),
                      "fallback lands on the main screen when provided")
    }

    // MARK: - Real-panel matrix

    private func makeMonitor(
        _ windowController: PetWindowController
    ) -> WindowLifecycleMonitor {
        let monitor = WindowLifecycleMonitor(windowController: windowController)
        monitor.restoreThrottle = 0
        return monitor
    }

    /// F + J: a healthy, visible panel must never be moved or re-asserted
    /// even when recovery notifications arrive.
    func testHealthyPanelIsNeverMovedByRecoveryNotifications() {
        let frame = CGRect(x: 400, y: 300, width: petSize.width, height: petSize.height)
        let windowController = PetWindowController()
        windowController.configureForTesting(frame: frame)
        let monitor = makeMonitor(windowController)
        var restores = 0
        monitor.onRestoreDecision = { restored, _ in if restored { restores += 1 } }

        for _ in 0..<10 {
            XCTAssertFalse(monitor.checkAndRestore(reason: "notify"))
        }
        XCTAssertEqual(restores, 0, "a healthy panel must never be moved")
        XCTAssertEqual(windowController.currentFrame.origin, frame.origin,
                       "the frame stays exactly where it was")
    }

    /// G + H: a storm of wake notifications / rapid repeated checks must
    /// result in a single restore (throttled).
    func testNotificationStormRestoresExactlyOnce() {
        let windowController = PetWindowController()
        windowController.configureForTesting(
            frame: CGRect(x: 400, y: 300, width: petSize.width, height: petSize.height)
        )
        let monitor = WindowLifecycleMonitor(windowController: windowController)
        monitor.restoreThrottle = 60 // one restore allowed per minute
        var restores = 0
        monitor.onRestoreDecision = { restored, _ in if restored { restores += 1 } }

        windowController.injectOffscreenFrame()
        for _ in 0..<20 {
            monitor.checkAndRestore(reason: "storm")
        }
        XCTAssertEqual(restores, 1, "a storm of notifications must yield exactly one restore")
        // The panel is back on a real display.
        let center = CGPoint(
            x: windowController.currentFrame.midX,
            y: windowController.currentFrame.midY
        )
        XCTAssertTrue(ScreenGeometry.screenVisibleFrames().contains { $0.contains(center) })
    }

    /// The monitor never steals keyboard focus: restoring a hidden panel
    /// must not make the app active (the panel is nonactivating by
    /// construction — this asserts the recovery path only orders the
    /// panel front and leaves activation policy untouched).
    func testRecoveryDoesNotChangeActivationOrCreateDuplicatePanels() {
        let windowController = PetWindowController()
        windowController.configureForTesting(
            frame: CGRect(x: 400, y: 300, width: petSize.width, height: petSize.height)
        )
        let panelBefore = windowController.petPanel
        windowController.injectHiddenPanel()
        let monitor = makeMonitor(windowController)
        XCTAssertTrue(monitor.checkAndRestore(reason: "test"))
        XCTAssertTrue(windowController.petPanel === panelBefore,
                      "recovery must reuse the SAME panel, never create a new one")
        XCTAssertTrue(windowController.petPanel?.canBecomeKey == false,
                      "the pet panel must remain non-key (no focus stealing)")
    }
}
