import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import WarawaraPet

/// Phase 8C visual QA against the OFFICIAL v3 art: an ANIMATED GIF of
/// the continuous Warawara<->bottle morph (rig + morph geometry), plus
/// static state sheets and the reading window surface. Gated by
/// BOTTLE_PREVIEW_OUT (CI sets it).
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
        let blobWidth = BottleArtOverlayView.rigBodyWidth()
        let lift = max(0, PetMetrics.visualCenter.y - renderSize.height / 2)

        // 1. The continuous morph: forward 20 frames + backward 20
        // frames, driven by the eased morph parameter and the REAL
        // reveal geometry — an actual animation, not static shots.
        var frames: [CGImage] = []
        let forward = (0..<20).map { BottleMorphMath.eased(Double($0) / 19.0) }
        let backward = (0..<20).map { BottleMorphMath.eased(Double(19 - $0) / 19.0) }
        for (index, eased) in (forward + backward).enumerated() {
            let frame = try renderFrame(
                label: String(format: "morph %02d", index),
                rig: rig, rigLoader: rigLoader, renderSize: renderSize, lift: lift,
                eased: eased, bottleImage: unread, blobWidth: blobWidth,
                size: CGSize(width: 420, height: 520)
            )
            frames.append(frame)
        }
        let gifURL = outputDir.appendingPathComponent("200-morph.gif")
        try writeAnimatedGIF(frames: frames, delay: 0.08, to: gifURL)

        // 2. State sheets.
        try renderBottleSheet(
            name: "210-bottle-unread", image: unread,
            eased: 1, blobWidth: blobWidth, to: outputDir
        )
        if let opening = store.bottleOpening {
            try renderBottleSheet(
                name: "211-bottle-opening", image: opening,
                eased: 1, blobWidth: blobWidth, to: outputDir
            )
        }
        if let idle = store.bottleIdle {
            try renderBottleSheet(
                name: "212-bottle-idle", image: idle,
                eased: 1, blobWidth: blobWidth, to: outputDir
            )
        }
        try await renderReadingWindow(to: outputDir)

        // 3. Verification: the GIF must be a real multi-frame animation.
        guard let source = CGImageSourceCreateWithURL(gifURL as CFURL, nil) else {
            XCTFail("morph GIF could not be opened")
            return
        }
        let frameCount = CGImageSourceGetCount(source)
        XCTAssertGreaterThanOrEqual(frameCount, 30, "the morph preview must be animated")
        for name in ["200-morph.gif", "210-bottle-unread.png", "211-bottle-opening.png",
                     "212-bottle-idle.png", "212-reading.png"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: outputDir.appendingPathComponent(name).path),
                "missing bottle preview \(name)"
            )
        }
    }

    // MARK: - Scenes

    private func renderFrame(
        label: String,
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader,
        renderSize: CGSize, lift: CGFloat,
        eased: Double, bottleImage: NSImage, blobWidth: CGFloat,
        size: CGSize
    ) throws -> CGImage {
        let params = WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(
                state: .idle, bottleMorphProgress: CGFloat(eased)
            ),
            breathPhase: 0.25
        ))
        let content = ZStack {
            CheckerboardBackground()
            VStack(spacing: 8) {
                Text(label).font(.headline)
                ZStack {
                    WarawaraLayeredCharacterView(
                        rig: rig, rigLoader: rigLoader,
                        parameters: params, renderSize: renderSize
                    )
                    .position(
                        x: PetMetrics.visualCenter.x,
                        y: PetMetrics.size.height - lift - renderSize.height / 2
                    )
                    BottleArtStateView(
                        image: bottleImage,
                        progress: eased,
                        blobWidth: blobWidth,
                        blend: 1
                    )
                    .position(
                        x: PetMetrics.visualCenter.x,
                        y: BottleMetrics.artBottomY - BottleMetrics.artHeight / 2
                    )
                }
                .frame(width: PetMetrics.size.width, height: PetMetrics.size.height)
            }
        }
        return try renderImage(content, size: size, scale: 1)
    }

    private func renderBottleSheet(
        name: String, image: NSImage, eased: Double, blobWidth: CGFloat, to dir: URL
    ) throws {
        let content = ZStack {
            CheckerboardBackground()
            VStack(spacing: 8) {
                Text(name).font(.headline)
                ZStack {
                    BottleArtStateView(
                        image: image, progress: eased,
                        blobWidth: blobWidth, blend: 1
                    )
                    .position(
                        x: PetMetrics.visualCenter.x,
                        y: BottleMetrics.artBottomY - BottleMetrics.artHeight / 2
                    )
                }
                .frame(width: PetMetrics.size.width, height: PetMetrics.size.height)
            }
        }
        try renderPNG(content, size: CGSize(width: 420, height: 520), scale: 1,
                      to: dir.appendingPathComponent("\(name).png"))
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

        let content = BottleReadingView(coordinator: coordinator, visual: visual)
            .frame(width: 560, height: 640)
        try renderPNG(content, size: CGSize(width: 560, height: 640), scale: 1,
                      to: outputDir.appendingPathComponent("212-reading.png"))
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

    private func renderPNG(_ view: some View, size: CGSize, scale: CGFloat, to url: URL) throws {
        let cgImage = try renderImage(view, size: size, scale: scale)
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "preview", code: 2)
        }
        try png.write(to: url)
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
