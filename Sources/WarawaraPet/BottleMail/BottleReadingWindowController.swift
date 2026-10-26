import AppKit
import SwiftUI

/// Phase 8C reading window: ONE hand-painted letter paper, reusing the
/// birthday letter's window lifecycle (a normal, focusable window —
/// keyboard events, Escape/Cmd+W and text selection all work; the pet
/// panel itself never grabs focus).
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
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // The window chrome disappears into the paper: hidden title,
        // transparent titlebar, the standard traffic lights stay as the
        // close entry.
        window.title = "Bottle Mail"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(
            calibratedRed: 0.96, green: 0.93, blue: 0.85, alpha: 1
        )
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

    /// Shows (or re-fronts) the paper. This is a deliberate user action,
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

/// The single hand-painted paper: the v3 parchment fills the window and
/// the letter text renders dynamically on top with safe margins.
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
        ZStack {
            paperBackground
            if let letter = shownLetter {
                VStack(spacing: 0) {
                    closeEntry
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("来自远方的信")
                                .font(.system(size: 15, weight: .semibold, design: .serif))
                                .foregroundColor(Color(red: 0.32, green: 0.26, blue: 0.18))
                            Text(letter.createdAt)
                                .font(.caption)
                                .foregroundColor(Color(red: 0.45, green: 0.4, blue: 0.32))
                            Rectangle()
                                .fill(Color(red: 0.55, green: 0.48, blue: 0.36).opacity(0.5))
                                .frame(height: 1)
                            Text(letter.body)
                                .font(.system(size: 15.5, design: .serif))
                                .foregroundColor(Color(red: 0.22, green: 0.18, blue: 0.12))
                                .lineSpacing(7.5)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            if case .revoked = coordinator.activationState {
                                Label("离线阅读中（设备授权已撤销）", systemImage: "wifi.slash")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                            Spacer(minLength: 0)
                        }
                        // Safe margins keep the text inside the painted
                        // paper edges.
                        .padding(.horizontal, 72)
                        .padding(.top, 26)
                        .padding(.bottom, 64)
                    }
                }
            } else {
                VStack {
                    Text("还没有收到信件")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: 520, height: 640)
        .onExitCommand(perform: onClose)
    }

    /// Top-right close entry (the traffic lights stay available too).
    private var closeEntry: some View {
        HStack {
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(red: 0.45, green: 0.38, blue: 0.28).opacity(0.75))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("w", modifiers: [.command])
            .help("关闭并收好这封信")
            .padding(.top, 10)
            .padding(.trailing, 12)
        }
    }

    /// The v3 parchment fills the whole window; a warm solid fallback
    /// keeps the paper usable if the art is missing.
    @ViewBuilder
    private var paperBackground: some View {
        if let paper = BottleMailArtStore.shared.letterPaper {
            Image(nsImage: paper)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .clipped()
        } else {
            Color(red: 0.97, green: 0.95, blue: 0.90)
        }
    }
}
