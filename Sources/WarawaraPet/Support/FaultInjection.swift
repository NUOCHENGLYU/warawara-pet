import AppKit
import Foundation

/// Development-only fault injection, reachable exclusively through the
/// explicit `--fault-inject <name>` CLI flag. Never active during
/// normal use; each case simulates a real-world reliability failure so
/// the recovery paths can be exercised on a real Mac.
enum FaultInjection {
    static let flag = "--fault-inject"

    static func apply(_ name: String, windowController: PetWindowController) {
        switch name {
        case "offscreen-frame":
            windowController.injectOffscreenFrame()
        case "hidden-panel":
            windowController.injectHiddenPanel()
        case "screen-change":
            LifecycleDiagnostics.log("FAULT_INJECT", details: "name=screen-change")
            NotificationCenter.default.post(
                name: NSApplication.didChangeScreenParametersNotification, object: nil
            )
        case "wake-recovery":
            LifecycleDiagnostics.log("FAULT_INJECT", details: "name=wake-recovery")
            windowController.runRecoveryCheck(reason: "injected-wake")
        default:
            LifecycleDiagnostics.log("FAULT_INJECT_UNKNOWN", details: "name=\(name)")
        }
    }

    static let knownNames = [
        "offscreen-frame", "hidden-panel", "screen-change", "wake-recovery"
    ]
}
