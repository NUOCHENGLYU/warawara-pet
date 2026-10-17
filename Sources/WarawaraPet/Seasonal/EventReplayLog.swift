import AppKit
import Foundation

/// Consistent runtime replay diagnostics (stdout + unified logging).
/// Markers are tied to REAL lifecycle/presentation points — never to
/// model-flag flips alone.
enum EventReplayLog {
    /// Set by --replay-smoke: the app exits after the replayed scene
    /// completes (CI packaged-app smoke tests).
    static var smokeMode = false

    static func requested(id: String) {
        emit("EVENT_REPLAY_REQUESTED id=\(id)")
    }

    static func ready(id: String) {
        emit("EVENT_REPLAY_READY id=\(id)")
    }

    static func accepted(id: String) {
        emit("EVENT_REPLAY_ACCEPTED id=\(id)")
    }

    static func rejected(id: String, reason: String) {
        emit("EVENT_REPLAY_REJECTED id=\(id) reason=\(reason)")
    }

    static func started(id: String) {
        emit("EVENT_REPLAY_STARTED id=\(id)")
    }

    static func visible(id: String) {
        emit("EVENT_REPLAY_VISIBLE id=\(id)")
    }

    // MARK: - Production-presentation diagnostics (post-audit)

    static func presenterAttached(id: String) {
        emit("EVENT_PRESENTER_ATTACHED id=\(id)")
    }

    static func assetLoaded(id: String, name: String) {
        emit("EVENT_ASSET_LOADED id=\(id) name=\(name)")
    }

    static func assetMissing(id: String, name: String) {
        emit("EVENT_ASSET_MISSING id=\(id) name=\(name)")
    }

    static func windowPresented(
        id: String,
        visible: Bool,
        frame: CGRect,
        level: NSWindow.Level,
        alpha: CGFloat
    ) {
        emit(
            "EVENT_WINDOW_PRESENTED id=\(id) visible=\(visible) "
            + "frame=\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height)) "
            + "level=\(level.rawValue) alpha=\(String(format: "%.2f", alpha))"
        )
    }

    static func sceneUpdated(id: String, phase: String) {
        emit("EVENT_SCENE_UPDATED id=\(id) phase=\(phase)")
    }

    static func sceneFailed(id: String, reason: String) {
        emit("EVENT_SCENE_FAILED id=\(id) reason=\(reason)")
    }

    static func finished(id: String) {
        emit("EVENT_FINISHED id=\(id)")
    }

    static func birthdayLayering(cakeWindow: Int?, envelopeWindow: Int?) {
        emit("EVENT_BIRTHDAY_LAYERING cakeWindow=\(cakeWindow.map(String.init) ?? "-") envelopeWindow=\(envelopeWindow.map(String.init) ?? "-")")
    }

    static func attentionAcquired(direction: CGVector) {
        emit("EVENT_ATTENTION_ACQUIRED dx=\(String(format: "%.2f", direction.dx)) dy=\(String(format: "%.2f", direction.dy))")
    }

    static func attentionUpdated(direction: CGVector) {
        emit("EVENT_ATTENTION_UPDATED dx=\(String(format: "%.2f", direction.dx)) dy=\(String(format: "%.2f", direction.dy))")
    }

    static func attentionReleased() {
        emit("EVENT_ATTENTION_RELEASED")
    }

    static func anchor(id: String, anchor: String) {
        emit("EVENT_ANCHOR id=\(id) anchor=\(anchor)")
    }

    static func propGeometry(
        id: String,
        asset: String,
        petFrame: CGRect,
        desiredWidth: CGFloat,
        bboxPx: String,
        renderScale: CGFloat,
        contentFrameInPanel: CGRect,
        hostingBounds: CGRect,
        panelFrame: CGRect,
        screenFrame: CGRect,
        alpha: CGFloat,
        level: NSWindow.Level,
        isVisible: Bool,
        phase: String,
        withinVisible: Bool
    ) {
        emit(
            "EVENT_PROP_GEOMETRY id=\(id) asset=\(asset) "
            + "petFrame=\(Int(petFrame.minX)),\(Int(petFrame.minY)),\(Int(petFrame.width)),\(Int(petFrame.height)) "
            + "desiredWidthPt=\(String(format: "%.1f", desiredWidth)) "
            + "bboxPx=\(bboxPx) renderScale=\(String(format: "%.4f", renderScale)) "
            + "contentInPanel=\(Int(contentFrameInPanel.minX)),\(Int(contentFrameInPanel.minY)),\(Int(contentFrameInPanel.width)),\(Int(contentFrameInPanel.height)) "
            + "hostingBounds=\(Int(hostingBounds.width))x\(Int(hostingBounds.height)) "
            + "panelFrame=\(Int(panelFrame.minX)),\(Int(panelFrame.minY)),\(Int(panelFrame.width)),\(Int(panelFrame.height)) "
            + "screenFrame=\(Int(screenFrame.width))x\(Int(screenFrame.height)) "
            + "alpha=\(String(format: "%.2f", alpha)) level=\(level.rawValue) "
            + "isVisible=\(isVisible) phase=\(phase) withinVisible=\(withinVisible)"
        )
    }

    static func propDebugDone(id: String) {
        emit("EVENT_PROP_DEBUG_DONE id=\(id)")
    }

    static func phase(id: String, phase: String) {
        emit("EVENT_REPLAY_PHASE id=\(id) phase=\(phase)")
    }

    static func completed(id: String) {
        emit("EVENT_REPLAY_COMPLETED id=\(id)")
    }

    static func cancelled(id: String) {
        emit("EVENT_REPLAY_CANCELLED id=\(id)")
    }

    static func failed(id: String, reason: String) {
        emit("EVENT_REPLAY_FAILED id=\(id) reason=\(reason)")
    }

    private static func emit(_ message: String) {
        print(message)
        fflush(stdout)
        NSLog("[WarawaraPet] %@", message)
    }
}
