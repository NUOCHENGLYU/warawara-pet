import AppKit

/// Lightweight, fully non-interactive panel for a temporary companion
/// Warawara. It can never become key/main, ignores all mouse input, and
/// does not affect the main pet panel or any other application.
final class CompanionPetPanel: NSPanel {
    convenience init(size: CGFloat) {
        self.init(
            contentRect: NSRect(origin: .zero, size: CGSize(width: size, height: size)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        alphaValue = 0
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
