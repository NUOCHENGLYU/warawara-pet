import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import WarawaraPet

/// Phase 8C poof-transition visual QA against the OFFICIAL assets: two
/// ANIMATED GIFs of the continuous hop -> smoke -> hidden swap ->
/// landing choreography (forward and reverse), plus state sheets and
/// the reading window. Gated by BOTTLE_PREVIEW_OUT (CI sets it).
@MainActor
final class BottlePreviewGeneratorTests: XCTestCase {
    private struct StubTransport: BottleMailAPITransport {
        func activate(code: String, label: String) async throws -> BottleMailActivation {
            throw BottleMailAPIError.network("stub")
        }

        func fetchLetters(after: Int, limit: Int, token: String) async throws -> BottleMailPage {
            BottleMailPage(letters: [], nextAfter: after)
        }

        func markOpened(id: String, token: String) async throws -> String? { nil }
    }

    func testGenerateBottlePreviews() async throws {
        guard let outputPath = ProcessInfo.processInfo.environment["BOTTLE_PREVIEW_OUT"] else {
            throw XCTSkip("BOTTLE_PREVIEW_OUT not set; skipping preview generation")
        }
        let outputDir = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let rigRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/WarawaraPet/Resources/Assets/WarawaraRig")
        let rigLoader = WarawaraRigLoader()
        guard rigLoader.loadManifest(from: rigRoot), let rig = rigLoader.rig else {
            throw XCTSkip("rig unavailable")
        }
        guard let renderSize = WarawaraExpressionDriver.renderSize(
            rig: rig, targetBodyHeight: PetMetrics.blobHeight
        ) else {
            throw XCTSkip("no render size")
        }

        let store = BottleMailArtStore()
        store.resetFully()
        guard store.verifyAllRequiredAssets().ok,
              let unread = store.bottleUnread else {
            throw XCTSkip("bottle v3 art unavailable")
        }
        let lift = max(0, PetMetrics.visualCenter.y - renderSize.height / 2)

        // 1. Forward morph GIF: Warawara -> bottle (30 frames, 1.35 s).
        let forwardTimes = (0..<30).map { Double($0) / 29.0 }
        var forwardFrames: [CGImage] = []
        for (index, t) in forwardTimes.enumerated() {
            forwardFrames.append(try renderTransitionFrame(
                label: String(format: "forward %02d", index),
                rig: rig, rigLoader: rigLoader, renderSize: renderSize, lift: lift,
                timeline: t, bottleImage: unread, store: store,
                size: CGSize(width: 420, height: 520)
            ))
        }
        try writeAnimatedGIF(
            frames: forwardFrames, delay: BottlePoofTimeline.duration / 30,
            to: outputDir.appendingPathComponent("200-poof-forward.gif")
        )

        // 2. Reverse morph GIF: bottle -> Warawara.
        let reverseTimes = (0..<30).map { Double(29 - $0) / 29.0 }
        var reverseFrames: [CGImage] = []
        for (index, t) in reverseTimes.enumerated() {
            reverseFrames.append(try renderTransitionFrame(
                label: String(format: "reverse %02d", index),
                rig: rig, rigLoader: rigLoader, renderSize: renderSize, lift: lift,
                timeline: t, bottleImage: unread, store: store,
                size: CGSize(width: 420, height: 520)
            ))
        }
        try writeAnimatedGIF(
            frames: reverseFrames, delay: BottlePoofTimeline.duration / 30,
            to: outputDir.appendingPathComponent("201-poof-reverse.gif")
        )

        // 3. State sheets: full occlusion moment + landing dust.
        try renderTransitionFrame(
            label: "occlusion", rig: rig, rigLoader: rigLoader, renderSize: renderSize, lift: lift,
            timeline: 0.45, bottleImage: unread, store: store,
            size: CGSize(width: 420, height: 520),
            writePNGTo: outputDir.appendingPathComponent("210-poof-occlusion.png")
        )
        try renderTransitionFrame(
            label: "landing", rig: rig, rigLoader: rigLoader, renderSize: renderSize, lift: lift,
            timeline: 0.8, bottleImage: unread, store: store,
            size: CGSize(width: 420, height: 520),
            writePNGTo: outputDir.appendingPathComponent("211-poof-landing.png")
        )
        try await renderReadingWindow(to: outputDir)

        // 4. Verification: both GIFs must be real multi-frame animations.
        for gifName in ["200-poof-forward.gif", "201-poof-reverse.gif"] {
            let gifURL = outputDir.appendingPathComponent(gifName)
            guard let source = CGImageSourceCreateWithURL(gifURL as CFURL, nil) else {
                XCTFail("\(gifName) could not be opened")
                continue
            }
            XCTAssertGreaterThanOrEqual(
                CGImageSourceGetCount(source), 25,
                "\(gifName) must be an actual animation"
            )
        }
        for name in ["200-poof-forward.gif", "201-poof-reverse.gif",
                     "210-poof-occlusion.png", "211-poof-landing.png", "212-reading.png"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: outputDir.appendingPathComponent(name).path),
                "missing bottle preview \(name)"
            )
        }
    }

    // MARK: - Scenes (mirror PetView exactly)

    private func renderTransitionFrame(
        label: String,
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader,
        renderSize: CGSize, lift: CGFloat,
        timeline: Double, bottleImage: NSImage, store: BottleMailArtStore,
        size: CGSize,
        writePNGTo pngURL: URL? = nil
    ) throws -> CGImage {
        let form = BottlePoofTimeline.formProgress(at: timeline)
        let params = WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(
                state: .idle, bottleMorphProgress: CGFloat(form)
            ),
            breathPhase: 0.25
        ))
        let poofSquash = (
            BottlePoofTimeline.squashX(t: timeline),
            BottlePoofTimeline.squashY(t: timeline)
        )
        let jump = BottlePoofTimeline.jumpOffsetY(t: timeline, reduceMotion: false)
        let wobble = BottlePoofTimeline.landingWobble(t: timeline)

        let content = ZStack {
            CheckerboardBackground()
            VStack(spacing: 8) {
                Text(label).font(.headline)
                ZStack {
                    ZStack {
                        WarawaraLayeredCharacterView(
                            rig: rig, rigLoader: rigLoader,
                            parameters: params, renderSize: renderSize
                        )
                        .position(
                            x: PetMetrics.visualCenter.x,
                            y: PetMetrics.size.height - lift - renderSize.height / 2
                        )
                        if form >= 1 {
                            BottlePoofArtView(image: bottleImage)
                                .position(
                                    x: PetMetrics.visualCenter.x,
                                    y: BottleMetrics.artBottomY - BottleMetrics.artHeight / 2
                                )
                        }
                        if BottlePoofTimeline.smokeVisible(t: timeline) {
                            BottlePoofSmokeView(
                                timeline: timeline,
                                reduceMotion: false,
                                store: store
                            )
                        }
                    }
                    .scaleEffect(x: poofSquash.0, y: poofSquash.1, anchor: .bottom)
                    .offset(y: -jump)
                    .rotationEffect(.radians(wobble), anchor: .bottom)
                }
                .frame(width: PetMetrics.size.width, height: PetMetrics.size.height)
            }
        }
        let cgImage = try renderImage(content, size: size, scale: 1)
        if let pngURL {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "preview", code: 2)
            }
            try png.write(to: pngURL)
        }
        return cgImage
    }

    private func renderReadingWindow(to outputDir: URL) async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BottlePreview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = tempDir.appendingPathComponent("mailbox.json")

        let store = BottleMailFileStore(fileURL: fileURL)
        try store.merge(
            remote: [
                BottleMailRemoteLetter(
                    id: "preview", seq: 1,
                    body: "亲爱的你：\n\n你好呀。这是你的第一封漂流瓶来信。\n希望你喜欢这个小小的惊喜 🎉\n\n—— 来自远方的 Warawara",
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

        // The reading window contains AppKit-backed controls that
        // ImageRenderer cannot rasterize (it yields the prohibition
        // placeholder) — snapshot the REAL view through a real offscreen
        // NSWindow instead, and verify the render pixel-wise so the
        // preview can never silently regress to the placeholder.
        let size = CGSize(width: 520, height: 640)
        let cgImage = try renderWindowSnapshot(
            BottleReadingPaperView(coordinator: coordinator, visual: visual, onClose: {}),
            size: size
        )
        let rep = NSBitmapImageRep(cgImage: cgImage)
        var paperPixels = 0
        var prohibitionPixels = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
            for x in stride(from: 60, to: rep.pixelsWide - 60, by: 4) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
                let r = color.redComponent
                let g = color.greenComponent
                let b = color.blueComponent
                if r > 0.85 && g > 0.78 && b > 0.60 && b < 0.98 {
                    paperPixels += 1
                }
                if r > 0.75 && g < 0.45 && b < 0.45 {
                    prohibitionPixels += 1
                }
            }
        }
        XCTAssertGreaterThan(paperPixels, 1500,
                             "the reading preview must show the parchment paper")
        XCTAssertLessThan(prohibitionPixels, 120,
                          "the reading preview must not be the renderer placeholder")

        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "preview", code: 7)
        }
        try png.write(to: outputDir.appendingPathComponent("212-reading.png"))
    }

    /// Mounts a view in a REAL NSHostingView + NSWindow (the production
    /// hosting path) and rasterizes it — required for AppKit-backed
    /// controls (List/HSplitView) that ImageRenderer cannot render.
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
        window.orderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            window.orderOut(nil)
            throw NSError(domain: "preview", code: 5)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        guard let cgImage = rep.cgImage else {
            throw NSError(domain: "preview", code: 6)
        }
        return cgImage
    }

    // MARK: - Rendering + GIF encoding

    private func renderImage(_ view: some View, size: CGSize, scale: CGFloat) throws -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = scale
        guard let cgImage = renderer.cgImage else {
            throw NSError(domain: "preview", code: 1)
        }
        return cgImage
    }

    private func writeAnimatedGIF(frames: [CGImage], delay: Double, to url: URL) throws {
        guard !frames.isEmpty,
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL, UTType.gif.identifier as CFString, frames.count, nil
              ) else {
            throw NSError(domain: "preview", code: 3)
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay,
                kCGImagePropertyGIFLoopCount: 0
            ]
        ]
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "preview", code: 4)
        }
    }
}

private struct CheckerboardBackground: View {
    var tile: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            let cols = Int(ceil(size.width / tile))
            let rows = Int(ceil(size.height / tile))
            for row in 0..<rows {
                for col in 0..<cols {
                    let light = (row + col) % 2 == 0
                    context.fill(
                        Path(CGRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile,
                                    width: tile, height: tile)),
                        with: .color(light ? Color(white: 0.86) : Color(white: 0.64))
                    )
                }
            }
        }
    }
}
