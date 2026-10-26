import AppKit
import SwiftUI

/// Phase 8C reading window: a plain native macOS reader, reusing the
/// birthday letter's window lifecycle (a normal, focusable window —
/// Escape, the standard close button and text selection all work; the
/// pet panel itself never grabs focus).
///
/// CLOSING THE WINDOW IS THE READING-COMPLETION ACTION: the window
/// close event notifies the visual coordinator (idempotently), which
/// marks the letter read locally and lets the mailbox publish drive the
/// reverse poof. There is no put-away button and no mailbox chrome.
final class BottleReadingWindowController: NSWindowController, NSWindowDelegate {
    /// Conflict signal for the seasonal/daily events (same role as
    /// `LetterWindowController.isOpen`).
    static private(set) var isOpen = false

    private let coordinator: BottleMailCoordinator
    private let visual: BottleVisualCoordinator

    init(coordinator: BottleMailCoordinator, visual: BottleVisualCoordinator) {
        self.coordinator = coordinator
        self.visual = visual
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        // A normal titlebar is the close entry.
        window.title = "来自远方的信"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: BottleReadingPaperView(
                coordinator: coordinator,
                visual: visual,
                onClose: { [weak window] in
                    // Closing is the reading-completion action; the
                    // delegate's windowWillClose notifies the visual.
                    window?.close()
                }
            )
        )
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows (or re-fronts) the reader. This is a deliberate user action,
    /// so the window may become key — the pet panel never grabs focus.
    func show() {
        guard let window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Self.isOpen = true
    }

    func windowWillClose(_ notification: Notification) {
        Self.isOpen = false
        // The ONLY reading-completion entry — idempotent inside the
        // visual coordinator, never closes any other window, never
        // terminates the app.
        visual.readingWindowClosed()
    }
}

/// The reading content: date + selectable body on the native window
/// background, with a plain 28 pt reading margin and normal scrolling.
struct BottleReadingPaperView: View {
    @ObservedObject var coordinator: BottleMailCoordinator
    @ObservedObject var visual: BottleVisualCoordinator
    let onClose: () -> Void

    private var shownLetter: BottleMailLetter? {
        if let id = visual.readingLetterID {
            return coordinator.letters.first(where: { $0.id == id })
        }
        return coordinator.letters.first
    }

    var body: some View {
        Group {
            if let letter = shownLetter {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(letter.createdAt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Divider()
                        Text(letter.body)
                            .font(.system(size: 15.5))
                            .lineSpacing(7)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if case .revoked = coordinator.activationState {
                            Label("离线阅读中（设备授权已撤销）", systemImage: "wifi.slash")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(28)
                }
            } else {
                Text("还没有收到信件")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand(perform: onClose)
    }
}
