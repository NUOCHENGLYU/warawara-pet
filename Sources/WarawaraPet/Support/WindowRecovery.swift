import AppKit
import Foundation

/// Pure window-recovery math: decides whether the pet panel needs
/// recovery (hidden, or its center no longer lies on any screen) and
/// computes a safe clamped frame on the current displays.
enum WindowRecovery {

    /// True when the frame's center is not inside ANY screen's visible
    /// frame (e.g. the display it lived on was unplugged during sleep).
    static func isOffscreen(_ frame: CGRect, screens: [CGRect]) -> Bool {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return !screens.contains { $0.contains(center) }
    }

    /// True when the panel needs recovery: hidden, or offscreen.
    static func needsRecovery(
        frame: CGRect,
        screens: [CGRect],
        isVisible: Bool
    ) -> Bool {
        !isVisible || isOffscreen(frame, screens: screens)
    }

    /// A safe frame: the current frame clamped into the visible frame of
    /// the screen it currently belongs to (main-screen fallback).
    static func recoveryFrame(
        _ frame: CGRect,
        screens: [CGRect],
        mainScreenVisible: CGRect,
        margin: CGFloat
    ) -> CGRect {
        let containing = screens.first {
            $0.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
        let visible = containing ?? mainScreenVisible
        return ScreenGeometry.clampFrame(frame, to: visible, margin: margin)
    }
}

/// Watches NSWorkspace sleep/wake and screen transitions and performs a
/// THROTTLED, non-activating window restore after the screens settle.
/// It only restores the WINDOW — it never wakes the sleeping pet (the
/// pet's sleepy/sleeping state lives in PetController and is untouched).
final class WindowLifecycleMonitor {
    private weak var windowController: PetWindowController?
    private var settleTimers: [Timer] = []
    private var lastRestore = Date.distantPast
    /// Throttle: never order the panel front more than once per interval.
    var restoreThrottle: TimeInterval = 2
    /// Dev-only: report each restore decision (tests observe via logs).
    var onRestoreDecision: ((Bool, String) -> Void)?

    init(windowController: PetWindowController) {
        self.windowController = windowController
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep(_:)),
                           name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake(_:)),
                           name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(screensDidSleep(_:)),
                           name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(screensDidWake(_:)),
                           name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    func stop() {
        settleTimers.forEach { $0.invalidate() }
        settleTimers.removeAll()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func willSleep(_ note: Notification) {
        LifecycleDiagnostics.sleep()
    }

    @objc private func didWake(_ note: Notification) {
        LifecycleDiagnostics.wake()
        // The window server may still be settling displays: check twice,
        // shortly after wake and once more.
        scheduleSettledChecks(delays: [1.5, 4.0])
    }

    @objc private func screensDidSleep(_ note: Notification) {
        // Displays going dark: nothing to restore yet.
    }

    @objc private func screensDidWake(_ note: Notification) {
        scheduleSettledChecks(delays: [1.0])
    }

    private func scheduleSettledChecks(delays: [TimeInterval]) {
        for delay in delays {
            let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.checkAndRestore(reason: "settle")
            }
            settleTimers.append(timer)
        }
        settleTimers.removeAll { !$0.isValid }
    }

    /// Runs one recovery check. Throttled: repeated calls inside
    /// `restoreThrottle` do nothing. Never focuses the app.
    @discardableResult
    func checkAndRestore(reason: String) -> Bool {
        guard let windowController, let panel = windowController.petPanel else {
            onRestoreDecision?(false, "no-panel")
            return false
        }
        let screens = ScreenGeometry.screenVisibleFrames()
        let needs = WindowRecovery.needsRecovery(
            frame: panel.frame,
            screens: screens,
            isVisible: panel.isVisible
        )
        guard needs else {
            LifecycleDiagnostics.log("WINDOW_OK", details: "reason=\(reason)")
            onRestoreDecision?(false, "healthy")
            return false
        }
        guard Date().timeIntervalSince(lastRestore) >= restoreThrottle else {
            onRestoreDecision?(false, "throttled")
            return false
        }
        lastRestore = Date()
        let restored = windowController.restorePetWindow(reason: reason)
        onRestoreDecision?(restored, reason)
        return restored
    }
}
