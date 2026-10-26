import AppKit
import SwiftUI
import XCTest
@testable import WarawaraPet

/// Renders the REAL BottleReadingView through the PRODUCTION hosting
/// path — a genuine NSHostingView inside a real (offscreen) AppKit
/// window — and verifies:
/// - the parchment background renders (paper pixels in the reading pane);
/// - the full Chinese/English/Emoji/multi-line body text renders (ink
///   pixels in the paper region);
/// - the renderer-failure prohibition glyph ("nosign") is absent.
///
/// ImageRenderer alone cannot rasterize the AppKit-backed
/// List/HSplitView (it yields the prohibition placeholder), so the
/// production path is what gets verified — the CI preview uses the same
/// offscreen-window snapshot.
@MainActor
final class BottleReadingWindowRenderTests: XCTestCase {
    private struct StubTransport: BottleMailAPITransport {
        func activate(code: String, label: String) async throws -> BottleMailActivation {
            throw BottleMailAPIError.network("stub")
        }

        func fetchLetters(after: Int, limit: Int, token: String) async throws -> BottleMailPage {
            BottleMailPage(letters: [], nextAfter: after)
        }

        func markOpened(id: String, token: String) async throws -> String? { nil }
    }

    func testReadingWindowRendersPaperAndFullBodyText() async throws {
        // The offscreen-window snapshot path is verified on the current
        // (macOS 15) runner in the universal build job; older runners
        // may stall in AppKit's table/split layout — skipped there.
        guard #available(macOS 15.0, *) else {
            throw XCTSkip("window snapshot render verified on macOS 15+")
        }
        guard BottleMailArtStore.shared.letterPaper != nil else {
            throw XCTSkip("letter paper asset unavailable")
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadingRender-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = tempDir.appendingPathComponent("mailbox.json")

        let body = "亲爱的你：\n\n这是第一段，包含中文与 English words。\n第二行有 Emoji：🎉 🍰 🎁\n\n第三段：换行、长段落——这封信应当完整显示在信纸上，可滚动阅读。"
        let store = BottleMailFileStore(fileURL: fileURL)
        try store.merge(
            remote: [
                BottleMailRemoteLetter(
                    id: "render-check", seq: 1, body: body,
                    createdAt: "2026-10-17 00:00", openedAt: nil
                )
            ],
            advancingCursorTo: 1
        )
        let coordinator = BottleMailCoordinator(
            transport: StubTransport(),
            credentials: InMemoryBottleMailCredentialStore(),
            store: BottleMailFileStore(fileURL: fileURL)
        )
        coordinator.start()
        let visual = BottleVisualCoordinator(mailbox: coordinator)
        visual.start(usingTimer: false)

        let deadline = Date().addingTimeInterval(3)
        while coordinator.letters.isEmpty && Date() < deadline {
            await MainActor.run {}
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(coordinator.letters.isEmpty, "the test letter must publish")

        let cgImage = try renderWindowSnapshot(
            BottleReadingView(coordinator: coordinator, visual: visual),
            size: CGSize(width: 560, height: 640)
        )
        let rep = NSBitmapImageRep(cgImage: cgImage)

        // Coarse pixel classification over the real render.
        var paperPixels = 0
        var inkPixels = 0
        var prohibitionPixels = 0
        var coloredTextPixels = 0
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                let r = color.redComponent
                let g = color.greenComponent
                let b = color.blueComponent
                let a = color.alphaComponent
                // The reading pane starts after the collection column.
                let inPaperPane = x > 260 && a > 0.5
                if inPaperPane {
                    if r > 0.85 && g > 0.78 && b > 0.60 && b < 0.98 {
                        paperPixels += 1
                    }
                    if r < 0.45 && g < 0.40 && b < 0.35 {
                        inkPixels += 1
                    }
                    if r > 0.75 && g < 0.45 && b < 0.45 {
                        prohibitionPixels += 1
                    }
                    // Emoji / colored glyph pixels (saturated, non-paper).
                    if r > 0.4, g < 0.85, b < 0.85, !(r > 0.85 && g > 0.78 && b > 0.6) {
                        coloredTextPixels += 1
                    }
                }
            }
        }

        XCTAssertGreaterThan(paperPixels, 800, "the parchment background must fill the reading pane")
        XCTAssertGreaterThan(inkPixels, 60, "the letter body text must render in ink on the paper")
        XCTAssertGreaterThan(coloredTextPixels, 15, "the body glyphs (incl. Emoji) must render")
        XCTAssertLessThan(prohibitionPixels, 120,
                          "no renderer-failure prohibition glyph may appear")
    }

    // MARK: - Offscreen production-path snapshot

    /// Mounts the view in a REAL NSHostingView + NSWindow (the exact
    /// production hosting path) and rasterizes it. This renders AppKit-
    /// backed controls (List, HSplitView) that ImageRenderer cannot.
    private func renderWindowSnapshot<Content: View>(
        _ content: Content,
        size: CGSize
    ) throws -> CGImage {
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        // A real window session is available on the CI runner: order it
        // on-screen so AppKit fully lays out the table/split machinery,
        // snapshot, then hide it again.
        window.orderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            window.orderOut(nil)
            throw NSError(domain: "render", code: 1)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        guard let cgImage = rep.cgImage else {
            throw NSError(domain: "render", code: 2)
        }
        return cgImage
    }
}
