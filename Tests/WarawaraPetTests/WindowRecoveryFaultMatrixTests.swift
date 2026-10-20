import AppKit
import XCTest
@testable import WarawaraPet

/// Window-recovery fault matrix: two-screen → one-screen transitions,
/// main-screen resize, screen-edge frames, healthy-panel no-ops,
/// repeated wake storms, and the fixed empty-screen-list deferral.
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

    /// C (FIXED): an empty screen list previously made `needsRecovery`
    /// true via `isOffscreen`, so a wake-time race could clamp a healthy
    /// window into the fallback box. The new contract: an empty screen
    /// list means "defer, do not act" — nothing moves, resets or
    /// orderFronts while the list is empty.
    func testEmptyScreenListDefersRecoveryWithoutMovingThePanel() {
        let frame = CGRect(x: 400, y: 300, width: petSize.width, height: petSize.height)
        XCTAssertFalse(WindowRecovery.needsRecovery(frame: frame, screens: [], isVisible: true),
                       "an empty screen list must NOT declare the panel unhealthy")
        XCTAssertTrue(WindowRecovery.isOffscreen(frame, screens: []),
                      "pure geometry still reports vacuously offscreen")

        let windowController = PetWindowController()
        windowController.configureForTesting(frame: frame)
        let monitor = makeMonitor(windowController)
        var empty: [CGRect] = []
        monitor.screenProvider = { empty }
        var decisions: [String] = []
        monitor.onRestoreDecision = { restored, reason in
            decisions.append(restored ? "restored" : reason)
        }

        // Two consecutive checks while the screen list is empty: deferred
        // twice, the frame is untouched, the panel is untouched.
        XCTAssertFalse(monitor.checkAndRestore(reason: "wake"))
        XCTAssertFalse(monitor.checkAndRestore(reason: "settle"))
        XCTAssertEqual(windowController.currentFrame.origin, frame.origin,
                       "no move while the screen list is empty")
        XCTAssertEqual(decisions, ["deferred-no-screens", "deferred-no-screens"])

        // Screens reappear with a real list: the SAME path now performs
        // the recovery for a genuinely offscreen panel.
        windowController.injectOffscreenFrame()
        monitor.screenProvider = { [self] in [primary] }
        let restored = monitor.checkAndRestore(reason: "wake")
        XCTAssertTrue(restored, "a later check with a real screen list recovers")
        XCTAssertEqual(decisions.last, "restored")
        XCTAssertTrue(primary.contains(CGPoint(
            x: windowController.currentFrame.midX,
            y: windowController.currentFrame.midY
        )))
    }

    /// Deferral must not consume the restore throttle: a deferred check
    /// followed by a real recovery inside the throttle window still
    /// restores (no permanent missed recovery).
    func testDeferredCheckDoesNotConsumeTheRestoreThrottle() {
        let frame = CGRect(x: 400, y: 300, width: petSize.width, height: petSize.height)
        let windowController = PetWindowController()
        windowController.configureForTesting(frame: frame)
        let monitor = makeMonitor(windowController)
        monitor.restoreThrottle = 60

        var empty: [CGRect] = []
        monitor.screenProvider = { empty }
        XCTAssertFalse(monitor.checkAndRestore(reason: "wake"))

        windowController.injectOffscreenFrame()
        monitor.screenProvider = { [self] in [primary] }
        XCTAssertTrue(monitor.checkAndRestore(reason: "wake"),
                      "deferral never consumes the throttle budget")
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
