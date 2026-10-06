import AppKit

final class PetPanel: NSPanel {
    convenience init(size: CGSize) {
        self.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configure()
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        // .stationary keeps the pet visible during Show Desktop / Mission
        // Control, like a desktop-level window. Real-Mac behavior with
        // "click wallpaper to reveal desktop" is unverified.
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
    }

    // The pet must never take keyboard focus away from the active app.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
