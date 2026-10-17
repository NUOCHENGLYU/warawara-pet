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
