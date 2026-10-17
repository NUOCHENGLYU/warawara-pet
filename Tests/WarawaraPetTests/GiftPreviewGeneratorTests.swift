import AppKit
import SwiftUI
import XCTest
@testable import WarawaraPet

/// Phase 7 production visual QA: the REAL rig + birthday-hat compositor,
/// the meteor at keyframes, and the letter reading surface.
@MainActor
final class GiftPreviewGeneratorTests: XCTestCase {
    func testGenerateGiftPreviews() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["GIFT_PREVIEW_OUT"] else {
            throw XCTSkip("GIFT_PREVIEW_OUT not set; skipping preview generation")
        }
        let outputDir = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let rigRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/WarawaraPet/Resources/Assets/WarawaraRig")
        let rigLoader = WarawaraRigLoader()
        guard rigLoader.loadManifest(from: rigRoot), let rig = rigLoader.rig else {
            throw XCTSkip("rig unavailable")
        }
        guard let mainSize = WarawaraExpressionDriver.renderSize(
            rig: rig, targetBodyHeight: PetMetrics.blobHeight
        ) else { throw XCTSkip("no render size") }
        GiftAssetStore.shared.reset()
        guard GiftAssetStore.shared.verifyAllRequiredAssets().ok else {
            throw XCTSkip("gift assets unavailable")
        }
        BirthdayAssetStore.shared.reset()

        // Neutral pet sheet.
        try renderSceneSheet(
            name: "90-neutral", rig: rig, rigLoader: rigLoader, mainSize: mainSize,
            params: idleParams()
        )

        try renderMeteorSheets(rig: rig, rigLoader: rigLoader, mainSize: mainSize, to: outputDir)
        try renderLetterSheet(store: .shared, to: outputDir)

        for name in ["90-neutral.png", "100-meteor-entrance.png", "101-meteor-mid.png",
                     "102-meteor-exit.png", "103-letter.png"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: outputDir.appendingPathComponent(name).path),
                "missing gift preview \(name)"
            )
        }
    }

    // MARK: - Sheets

    private func idleParams() -> WarawaraPerformanceParameters {
        WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(state: .idle), breathPhase: 0.25
        ))
    }

    private func renderSceneSheet(
        name: String,
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader, mainSize: CGSize,
        params: WarawaraPerformanceParameters
    ) throws {
        let outputDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["GIFT_PREVIEW_OUT"]!)
        let content = ZStack {
            CheckerboardBackground()
            VStack(spacing: 8) {
                Text(name).font(.headline)
                WarawaraLayeredCharacterView(
                    rig: rig, rigLoader: rigLoader,
                    parameters: params, renderSize: mainSize
                )
                .frame(width: mainSize.width, height: mainSize.height)
            }
        }
        try render(content, size: CGSize(width: 560, height: 480), scale: 1,
                   to: outputDir.appendingPathComponent("\(name).png"))
    }

    private func renderMeteorSheets(
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader,
        mainSize: CGSize, to dir: URL
    ) throws {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let trajectory = MeteorTrajectory.fixed(in: visible)
        guard let headImage = GiftAssetStore.shared.image(named: "meteor_head_from_approved.png") else {
            throw XCTSkip("meteor head asset unavailable")
        }
        let sparkleImage = GiftAssetStore.shared.image(named: "meteor_sparkle_from_approved.png")
        let sampler = MeteorTrajectorySampler(trajectory: trajectory)
        let headCanvas = CGSize(width: 1254.0 * 38.0 / 594.0, height: 1254.0 * 38.0 / 594.0)

        for (name, s) in [("100-meteor-entrance", 0.06), ("101-meteor-mid", 0.5), ("102-meteor-exit", 0.94)] {
            let progress = CGFloat(s)
            // Synthesize the exact scene the production renderer builds:
            // head at the trajectory position plus a short history tail.
            let sceneState = MeteorSceneState()
            var segments: [MeteorTrailSegment] = []
            for strand in 0..<5 {
                var pts: [CGPoint] = []
                for step in 0..<10 {
                    let sp = max(0.0, progress - Double(strand * 2 + step) * 0.012)
                    let world = sampler.position(atArcLength: CGFloat(sp))
                    pts.append(CGPoint(x: 60 + (world.x - trajectory.entry.x) * 0.5,
                                       y: 320 - (world.y - trajectory.entry.y) * 0.5))
                }
                segments.append(MeteorTrailSegment(
                    id: strand, points: pts,
                    opacity: 0.2 + 0.08 * CGFloat(strand),
                    width: 2.6 - 0.35 * CGFloat(strand),
                    colorIndex: strand % 2
                ))
            }
            let headPosition = sampler.position(atArcLength: progress)
            let panelCenter = CGPoint(x: 60 + (headPosition.x - trajectory.entry.x) * 0.5,
                                      y: 320 - (headPosition.y - trajectory.entry.y) * 0.5)
            sceneState.frame = MeteorSceneFrame(
                headRotation: sampler.heading(atArcLength: progress) * 180 / .pi + 15,
                headAlpha: 1,
                trailSegments: segments,
                sparkles: []
            )
            let content = ZStack {
                NightSkyBackground()
                VStack(spacing: 6) {
                    Text("meteor \(name)").font(.headline).foregroundColor(.white)
                    ZStack {
                        WarawaraLayeredCharacterView(
                            rig: rig, rigLoader: rigLoader,
                            parameters: idleParams(), renderSize: mainSize
                        )
                        .frame(width: mainSize.width, height: mainSize.height)
                        .position(x: 300, y: 380)
                        MeteorSceneView(
                            state: sceneState,
                            headImage: headImage,
                            sparkleImage: sparkleImage,
                            headCanvasSize: headCanvas
                        )
                        .position(x: panelCenter.x, y: panelCenter.y)
                    }
                    .frame(width: 760, height: 480)
                }
            }
            try render(content, size: CGSize(width: 760, height: 520), scale: 1,
                       to: dir.appendingPathComponent("\(name).png"))
        }
    }

    private func renderLetterSheet(store: BirthdayAssetStore, to dir: URL) throws {
        let text = store.letterText() ?? ""
        let content = LetterView(text: text, store: store)
            .frame(width: 520, height: 600)
        try render(content, size: CGSize(width: 520, height: 600), scale: 1,
                   to: dir.appendingPathComponent("103-letter.png"))
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

private struct NightSkyBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(white: 0.10), Color(white: 0.22)],
            startPoint: .top, endPoint: .bottom
        )
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
