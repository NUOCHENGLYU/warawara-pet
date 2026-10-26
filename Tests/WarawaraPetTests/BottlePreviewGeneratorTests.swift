import AppKit
import SwiftUI
import XCTest
@testable import WarawaraPet

/// Phase 8C visual QA: continuous morph frames of the REAL rig with
/// the procedural bottle layers, the sealed/open bottle states, and the
/// reading window surface. Gated by BOTTLE_PREVIEW_OUT (CI sets it).
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

        let lift = max(0, PetMetrics.visualCenter.y - renderSize.height / 2)
        for (index, progress) in [0.0, 0.15, 0.3, 0.45, 0.6, 0.8, 1.0].enumerated() {
            try renderScene(
                name: String(format: "200-morph-%02d", index),
                rig: rig, rigLoader: rigLoader, renderSize: renderSize, lift: lift,
                progress: progress, opening: 0, to: outputDir
            )
        }
        try renderScene(
            name: "210-bottle-idle",
            rig: rig, rigLoader: rigLoader, renderSize: renderSize, lift: lift,
            progress: 1, opening: 0, to: outputDir
        )
        try renderScene(
            name: "211-bottle-open",
            rig: rig, rigLoader: rigLoader, renderSize: renderSize, lift: lift,
            progress: 1, opening: 1, to: outputDir
        )
        try await renderReadingWindow(to: outputDir)

        for name in ["200-morph-00", "200-morph-03", "200-morph-06",
                     "210-bottle-idle", "211-bottle-open", "212-reading"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: outputDir.appendingPathComponent("\(name).png").path),
                "missing bottle preview \(name)"
            )
        }
    }

    private func renderScene(
        name: String,
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader,
        renderSize: CGSize, lift: CGFloat,
        progress: Double, opening: Double,
        to outputDir: URL
    ) throws {
        let params = WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(
                state: .idle, bottleMorphProgress: CGFloat(progress)
            ),
            breathPhase: 0.25
        ))
        let content = ZStack {
            CheckerboardBackground()
            VStack(spacing: 8) {
                Text(name).font(.headline)
                ZStack {
                    BottleGlassBodyView(progress: progress)
                        .position(x: PetMetrics.visualCenter.x, y: PetMetrics.visualCenter.y)
                    WarawaraLayeredCharacterView(
                        rig: rig, rigLoader: rigLoader,
                        parameters: params, renderSize: renderSize
                    )
                    .position(
                        x: PetMetrics.visualCenter.x,
                        y: PetMetrics.size.height - lift - renderSize.height / 2
                    )
                    BottleExtrasView(progress: progress, openingProgress: opening)
                        .position(
                            x: PetMetrics.visualCenter.x,
                            y: PetMetrics.visualCenter.y
                                - BottleMetrics.glassHeight / 2
                                - BottleMetrics.extrasContainerHeight / 2
                        )
                }
                .frame(width: PetMetrics.size.width, height: PetMetrics.size.height)
            }
        }
        try render(content, size: CGSize(width: 420, height: 520), scale: 1,
                   to: outputDir.appendingPathComponent("\(name).png"))
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
        try render(content, size: CGSize(width: 560, height: 640), scale: 1,
                   to: outputDir.appendingPathComponent("212-reading.png"))
    }

    private func render(_ view: some View, size: CGSize, scale: CGFloat, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = scale
        guard let cgImage = renderer.cgImage else {
            throw NSError(domain: "preview", code: 1)
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "preview", code: 2)
        }
        try png.write(to: url)
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
