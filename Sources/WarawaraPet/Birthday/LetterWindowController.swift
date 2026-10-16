import AppKit
import SwiftUI

/// Native reading window for the personal birthday letter. This window
/// is deliberately ACTIVATABLE when opened on purpose — unlike the pet
/// panels, which never steal focus. Closing it never affects the pet.
final class LetterWindowController: NSWindowController {
    private let store: BirthdayAssetStore

    /// True while the letter reading window is open (seasonal events
    /// never start while the user is reading).
    static private(set) var isOpen = false

    init(store: BirthdayAssetStore = .shared) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Birthday Letter"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        let text = store.letterText() ?? ""
        let hosting = NSHostingView(rootView: LetterView(text: text, store: store))
        window.contentView = hosting
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showLetter() {
        guard let window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        Self.isOpen = true
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension LetterWindowController: NSWindowDelegate {
    /// Closing the reading window only resets the envelope illustration:
    /// the main pet stays visible and the envelope stays accessible.
    func windowWillClose(_ notification: Notification) {
        Self.isOpen = false
        NotificationCenter.default.post(name: .birthdayLetterDidClose, object: nil)
    }
}
