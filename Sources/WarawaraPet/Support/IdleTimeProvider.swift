import CoreGraphics
import Foundation

protocol SystemIdleTimeProviding {
    func secondsSinceLastUserActivity() -> TimeInterval
}

/// System-wide user inactivity via CGEventSource timestamps. No
/// accessibility, input-monitoring, or other permissions; no input is
/// collected or stored. Permission-free behavior is verified on a real Mac.
struct CGEventSourceIdleTimeProvider: SystemIdleTimeProviding {
    func secondsSinceLastUserActivity() -> TimeInterval {
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .mouseMoved]
        let values = types.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }
        return values.min() ?? 0
    }
}
