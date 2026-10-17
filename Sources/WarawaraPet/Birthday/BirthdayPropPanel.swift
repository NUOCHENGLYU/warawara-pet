import AppKit
import SwiftUI

/// Transparent, borderless, nonactivating panel for birthday props
/// (cake/sparkles/envelope). Never steals keyboard focus; mouse events
/// are ignored for decorative props and accepted (first click included)
/// for the clickable envelope.
/// Test spy subclasses override orderFrontRegardless to observe the
/// layering contract, so the class must stay non-final.
class BirthdayPropPanel: NSPanel {
    convenience init(size: CGSize, interactive: Bool) {        self.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = !interactive
        becomesKeyOnlyIfNeeded = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosting view for interactive prop panels: delivers the first click
/// without making the panel key, mirroring the main pet's behavior.
final class BirthdayPropHostingView<Content: View>: NSHostingView<Content> {
    override var needsPanelToBecomeKey: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
