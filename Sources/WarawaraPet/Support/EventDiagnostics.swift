import AppKit
import Foundation

/// Consistent runtime diagnostics for the final gift build: attention
/// ownership, wearables, meteor, first-launch celebration and packaged
/// verification. Markers are tied to real lifecycle points.
enum EventDiagnostics {
    /// Set by --replay-smoke: the app exits after the replayed scene
    /// completes (CI packaged-app smoke tests).
    static var smokeMode = false

    static func attentionAcquired(direction: CGVector) {
        emit("EVENT_ATTENTION_ACQUIRED dx=\(String(format: "%.2f", direction.dx)) dy=\(String(format: "%.2f", direction.dy))")
    }

    static func attentionUpdated(direction: CGVector) {
        emit("EVENT_ATTENTION_UPDATED dx=\(String(format: "%.2f", direction.dx)) dy=\(String(format: "%.2f", direction.dy))")
    }

    static func attentionReleased() {
        emit("EVENT_ATTENTION_RELEASED")
    }

    static func wearableChanged(id: String, active: Bool) {
        emit("WEARABLE_CHANGED id=\(id) active=\(active)")
    }

    static func meteor(_ event: String) {
        emit("METEOR_\(event)")
    }

    static func firstLaunch(_ event: String) {
        emit("FIRST_LAUNCH_\(event)")
    }

    static func giftAssets(_ event: String) {
        emit("GIFT_ASSETS_\(event)")
    }

    static func audio(_ event: String) {
        emit("AUDIO_ACTIVITY_\(event)")
    }

    static func emit(_ message: String) {
        print(message)
        fflush(stdout)
        NSLog("[WarawaraPet] %@", message)
    }
}
