import AppKit
import SwiftUI

/// Phase 8C reading window: the letter paper UI. Opens from a click on
/// the bottle; letters are marked read ONLY via the explicit
/// "收好这封信" action (closing the window keeps the letter unread and
/// the pet stays a bottle). Read letters stay in the collection and can
/// be re-browsed at any time. Revoked devices keep full offline reading
/// (markOpened completes locally without any server call).
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
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Bottle Mail"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: BottleReadingView(coordinator: coordinator, visual: visual)
        )
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows (or re-fronts) the reading window. This is a deliberate
    /// user action, so the window may become key — the pet panel
    /// itself never grabs focus.
    func show() {
        guard let window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Self.isOpen = true
    }

    func closeReadingWindow() {
        guard let window else { return }
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        Self.isOpen = false
        visual.readingWindowClosed()
    }
}

/// The paper reading surface: collection list on the left, the letter
/// paper on the right. Only "收好这封信" completes a read.
struct BottleReadingView: View {
    @ObservedObject var coordinator: BottleMailCoordinator
    @ObservedObject var visual: BottleVisualCoordinator
    /// Manual browsing override; nil = follow the visual's current
    /// letter (the put-away flow).
    @State private var manualSelection: String?

    var body: some View {
        HSplitView {
            collectionList
                .frame(minWidth: 190, idealWidth: 190, maxWidth: 230)
            letterPaper
                .frame(minWidth: 340)
        }
        .frame(width: 560, height: 640)
    }

    private var shownLetter: BottleMailLetter? {
        let target = manualSelection ?? visual.readingLetterID
        return coordinator.letters.first(where: { $0.id == target })
            ?? coordinator.letters.first
    }

    // MARK: - Collection list

    private var collectionList: some View {
        List(selection: $manualSelection) {
            ForEach(coordinator.letters) { letter in
                HStack(spacing: 6) {
                    if letter.isUnread {
                        Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                    } else {
                        Circle().fill(Color.clear).frame(width: 7, height: 7)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(letter.body.prefix(22))
                            .lineLimit(1)
                            .font(.system(size: 12))
                        Text(letter.createdAt)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)
                .tag(letter.id)
            }
        }
        .overlay {
            if coordinator.letters.isEmpty {
                Text("还没有收到信件")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Letter paper

    @ViewBuilder
    private var letterPaper: some View {
        VStack(spacing: 0) {
            if let letter = shownLetter {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            if let scroll = BottleMailArtStore.shared.scrollSealed {
                                Image(nsImage: scroll)
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFit()
                                    .frame(height: 26)
                            }
                            Text("来自远方的信")
                                .font(.system(size: 15, weight: .semibold, design: .serif))
                                .foregroundColor(Color(red: 0.32, green: 0.26, blue: 0.18))
                            Spacer()
                        }
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
                        Spacer(minLength: 0)
                    }
                    .padding(28)
                }
                .background(paperBackground)
                Divider()
                letterFooter(letter)
            } else {
                VStack {
                    Text("还没有收到信件")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(paperBackground)
            }
        }
    }

    /// The v3 parchment (`letter_paper_blank.png`) fills the paper area;
    /// a warm solid fallback keeps the reading surface usable if the
    /// art is missing.
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

    @ViewBuilder
    private func letterFooter(_ letter: BottleMailLetter) -> some View {
        HStack(spacing: 12) {
            if case .revoked = coordinator.activationState {
                Label("离线阅读中（设备授权已撤销）", systemImage: "wifi.slash")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            Spacer()
            Text("关闭窗口不会标记已读")
                .font(.caption2)
                .foregroundColor(.secondary)
            Button(letter.isUnread ? "收好这封信" : "已收藏") {
                guard letter.isUnread else { return }
                visual.letterPutAway(id: letter.id)
                manualSelection = nil
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!letter.isUnread)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
