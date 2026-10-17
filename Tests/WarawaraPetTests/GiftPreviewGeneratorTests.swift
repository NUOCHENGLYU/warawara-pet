import AppKit
import SwiftUI
import XCTest
@testable import WarawaraPet

/// Phase 7 production visual QA: the REAL rig + wearable compositor at
/// realistic desktop size. Not concept art — these are the actual
/// production views the app renders.
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

        let sheets: [(String, WarawaraWearableState, WarawaraPerformanceParameters, WearableRenderParameters)] = [
            ("90-neutral", .none, idleParams(), .default),
            ("91-christmas-hat", WarawaraWearableState(headwear: .christmasHat), idleParams(), .default),
            ("92-birthday-hat", WarawaraWearableState(headwear: .birthdayHat), idleParams(), .default),
            ("93-headphones-front", WarawaraWearableState(headwear: .headphones), idleParams(), .default),
            ("94-headphones-yaw-left", WarawaraWearableState(headwear: .headphones), curiousParams(gaze: CGVector(dx: -0.7, dy: 0.05)), .default),
            ("95-headphones-yaw-right", WarawaraWearableState(headwear: .headphones), curiousParams(gaze: CGVector(dx: 0.7, dy: 0.05)), .default),
            ("96-headphones-drag", WarawaraWearableState(headwear: .headphones), dragParams(), .default),
            ("97-scarf-front", WarawaraWearableState(scarf: true), idleParams(), .default),
            ("98-scarf-curious", WarawaraWearableState(scarf: true), curiousParams(gaze: CGVector(dx: -0.55, dy: -0.15)), WearableRenderParameters(tasselSway: 2.5)),
            ("99-scarf-hop", WarawaraWearableState(scarf: true), hopParams(), WearableRenderParameters(tasselSway: 4))
        ]
        for (name, wearables, params, motion) in sheets {
            let content = sceneSheet(
                rig: rig, rigLoader: rigLoader, mainSize: mainSize,
                wearables: wearables, params: params, motion: motion,
                title: name
            )
            try render(content, size: CGSize(width: 560, height: 480), scale: 1,
                       to: outputDir.appendingPathComponent("\(name).png"))
        }

        try renderMeteorSheets(rig: rig, rigLoader: rigLoader, mainSize: mainSize, to: outputDir)
        try renderLetterSheet(store: .shared, to: outputDir)

        for name in ["90-neutral.png", "91-christmas-hat.png", "92-birthday-hat.png",
                     "93-headphones-front.png", "94-headphones-yaw-left.png",
                     "95-headphones-yaw-right.png", "96-headphones-drag.png",
                     "97-scarf-front.png", "98-scarf-curious.png", "99-scarf-hop.png",
                     "100-meteor-entrance.png", "101-meteor-mid.png",
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

    private func curiousParams(gaze: CGVector) -> WarawaraPerformanceParameters {
        WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(state: .curious, gaze: gaze), breathPhase: 0.25
        ))
    }

    private func dragParams() -> WarawaraPerformanceParameters {
        WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(
                state: .dragged,
                dragDeformation: PetDeformation(stretchScale: 1.12, anchor: CGVector(dx: 0.5, dy: -0.2))
            ),
            breathPhase: 0.25
        ))
    }

    private func hopParams() -> WarawaraPerformanceParameters {
        WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(state: .hop, hopProgress: 0.5), breathPhase: 0.25
        ))
    }

    private func sceneSheet(
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader, mainSize: CGSize,
        wearables: WarawaraWearableState,
        params: WarawaraPerformanceParameters,
        motion: WearableRenderParameters,
        title: String
    ) -> some View {
        ZStack {
            CheckerboardBackground()
            VStack(spacing: 8) {
                Text(title).font(.headline)
                WarawaraLayeredCharacterView(
                    rig: rig, rigLoader: rigLoader,
                    parameters: params, renderSize: mainSize,
                    wearables: wearables, wearableMotion: motion
                )
                .frame(width: mainSize.width, height: mainSize.height)
            }
        }
    }

    private func renderMeteorSheets(
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader,
        mainSize: CGSize, to dir: URL
    ) throws {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let trajectory = MeteorTrajectory.fixed(in: visible)
        guard let image = GiftAssetStore.shared.image(named: "meteor_celfilm.png") else {
            throw XCTSkip("meteor asset unavailable")
        }
        let state = MeteorViewState()
        state.image = image
        let canvasPt: CGFloat = 150 / (881.0 / 1024)
        state.canvasSize = CGSize(width: canvasPt, height: canvasPt)

        for (name, t) in [("100-meteor-entrance", 0.06), ("101-meteor-mid", 0.5), ("102-meteor-exit", 0.94)] {
            let position = trajectory.position(at: CGFloat(t))
            state.rotationDegrees = trajectory.heading(at: CGFloat(t)) * 180 / .pi + 15
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
                        MeteorView(state: state)
                            .position(
                                x: position.x / 1440 * 760,
                                y: 900 - position.y * 0.75
                            )
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
