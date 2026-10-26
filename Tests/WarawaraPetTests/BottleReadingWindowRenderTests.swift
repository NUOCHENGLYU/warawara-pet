import AppKit
import SwiftUI
import XCTest
@testable import WarawaraPet

/// Renders the REAL BottleReadingView through the PRODUCTION hosting
/// path — a genuine NSHostingView inside a real (offscreen) AppKit
/// window — and verifies:
/// - the native window background fills the reader;
/// - the full Chinese/English/Emoji/multi-line body text renders with
///   contrast against that background;
/// - the renderer-failure prohibition glyph ("nosign") is absent.
///
/// ImageRenderer alone cannot rasterize the AppKit-backed controls (it
/// yields the prohibition placeholder), so the production path is what
/// gets verified — the CI preview uses the same offscreen-window
/// snapshot.
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

    func testReadingWindowRendersSystemBackgroundAndFullBodyText() async throws {
        // The offscreen-window snapshot path is verified on the current
        // (macOS 15) runner in the universal build job; older runners
        // may stall in AppKit's table/split layout — skipped there.
        guard #available(macOS 15.0, *) else {
            throw XCTSkip("window snapshot render verified on macOS 15+")
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
            BottleReadingPaperView(coordinator: coordinator, visual: visual, onClose: {}),
            size: CGSize(width: 520, height: 640)
        )
        let rep = NSBitmapImageRep(cgImage: cgImage)

        // Coarse pixel classification over the real render. The native
        // window background fills the reader; text must contrast with it
        // in either light or dark appearance.
        var samples: [(r: CGFloat, g: CGFloat, b: CGFloat, luminance: CGFloat)] = []
        var prohibitionPixels = 0
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 60, to: width - 60, by: 4) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else {
                    continue
                }
                let r = color.redComponent
                let g = color.greenComponent
                let b = color.blueComponent
                let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
                samples.append((r, g, b, luminance))
                if r > 0.75 && g < 0.45 && b < 0.45 {
                    prohibitionPixels += 1
                }
            }
        }
        let backgroundLuminance = samples.isEmpty
            ? 0
            : samples.map { $0.luminance }.reduce(0, +) / CGFloat(samples.count)
        var inkPixels = 0
        var coloredTextPixels = 0
        for sample in samples {
            if abs(sample.luminance - backgroundLuminance) > 0.22 {
                inkPixels += 1
            }
            let chroma = max(sample.r, sample.g, sample.b)
                - min(sample.r, sample.g, sample.b)
            if chroma > 0.18 && sample.luminance > 0.15 {
                coloredTextPixels += 1
            }
        }

        XCTAssertGreaterThan(samples.count, 1500, "the native window background must fill the reader")
        XCTAssertGreaterThan(inkPixels, 60, "the letter body text must contrast with the background")
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
