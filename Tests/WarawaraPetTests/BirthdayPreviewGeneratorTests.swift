import AppKit
import SwiftUI
import XCTest
@testable import WarawaraPet

/// Birthday preview generator: renders the PRODUCTION views (approved
/// rig, v2 props, letter surface) into inspectable contact sheets.
/// Gated by BIRTHDAY_PREVIEW_OUT (CI sets it).
@MainActor
final class BirthdayPreviewGeneratorTests: XCTestCase {
    private let mainCanvas = CGSize(width: 200, height: 226)

    func testGenerateBirthdayPreviews() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["BIRTHDAY_PREVIEW_OUT"] else {
            throw XCTSkip("BIRTHDAY_PREVIEW_OUT not set; skipping preview generation")
        }
        let outputDir = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let rigRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/WarawaraPet/Resources/Assets/WarawaraRig")
        let rigLoader = WarawaraRigLoader()
        guard rigLoader.loadManifest(from: rigRoot), let rig = rigLoader.rig else {
            throw XCTSkip("rig unavailable: \(rigLoader.lastErrorDescription ?? "")")
        }
        guard let mainSize = WarawaraExpressionDriver.renderSize(rig: rig, targetBodyHeight: PetMetrics.blobHeight),
              let companionSize = WarawaraExpressionDriver.renderSize(rig: rig, targetBodyHeight: CompanionMetrics.blobHeight) else {
            throw XCTSkip("no render sizes")
        }
        let store = BirthdayAssetStore.shared
        store.reset()
        guard store.verifyAllRequiredAssets().ok else {
            throw XCTSkip("birthday assets unavailable")
        }

        try renderSurprise(rig: rig, rigLoader: rigLoader, mainSize: mainSize, to: outputDir)
        try renderGathering(rig: rig, rigLoader: rigLoader, mainSize: mainSize, companionSize: companionSize, to: outputDir)
        try renderCakeAndCelebration(rig: rig, rigLoader: rigLoader, mainSize: mainSize, companionSize: companionSize, store: store, to: outputDir)
        try renderAscent(rig: rig, rigLoader: rigLoader, companionSize: companionSize, to: outputDir)
        try renderEnvelopeReveal(store: store, to: outputDir)
        try renderLetterWindow(store: store, to: outputDir)
        try renderFinalEnvelope(rig: rig, rigLoader: rigLoader, mainSize: mainSize, store: store, to: outputDir)

        for name in ["46-birthday-surprise.png", "47-birthday-gathering.png",
                     "48-birthday-cake.png", "49-birthday-celebration.png",
                     "50-birthday-ascent.png", "51-birthday-envelope-reveal.png",
                     "52-birthday-letter.png", "53-birthday-final-envelope-light.png",
                     "54-birthday-final-envelope-dark.png"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: outputDir.appendingPathComponent(name).path),
                "missing birthday preview \(name)"
            )
        }
    }

    private func rigView(_ rig: WarawaraRigManifest, _ loader: WarawaraRigLoader,
                         _ params: WarawaraPerformanceParameters, _ size: CGSize) -> some View {
        WarawaraLayeredCharacterView(rig: rig, rigLoader: loader, parameters: params, renderSize: size)
    }

    private func idleParams() -> WarawaraPerformanceParameters {
        WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(state: .idle), breathPhase: 0.25
        ))
    }

    private func curiousParams(yaw: CGFloat) -> WarawaraPerformanceParameters {
        WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(
                state: .curious,
                gaze: CGVector(dx: yaw / WarawaraTurnGeometry.maxYawDegrees, dy: 0)
            ),
            breathPhase: 0.25
        ))
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

    // MARK: - Sheets

    private func renderSurprise(rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader, mainSize: CGSize, to dir: URL) throws {
        // The surprise: curious turn toward the side + a light hop squash.
        var turned = curiousParams(yaw: 18)
        turned.bodySquashY = 0.92
        turned.bodySquashX = 1.06
        let content = ZStack {
            CheckerboardBackground()
            VStack(spacing: 6) {
                Text("1. surprise reaction (curious turn + hop squash)").font(.headline)
                HStack(spacing: 60) {
                    rigView(rig, rigLoader, idleParams(), mainSize)
                    rigView(rig, rigLoader, turned, mainSize)
                }
            }
        }
        try render(content, size: CGSize(width: 700, height: 420), scale: 1,
                   to: dir.appendingPathComponent("46-birthday-surprise.png"))
    }

    private func renderGathering(rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader, mainSize: CGSize, companionSize: CGSize, to dir: URL) throws {
        // Companions positioned with the production formation offsets.
        var rng = SystemRandomSource()
        let offsets = GroupMotionMath.formationOffsets(
            count: 4,
            mainCenter: CGPoint(x: 250, y: 220),
            visibleFrame: CGRect(x: 0, y: 0, width: 700, height: 460),
            using: &rng,
            tuning: .default
        )
        let content = ZStack {
            CheckerboardBackground()
            VStack(spacing: 6) {
                Text("2. companion gathering (production formation math)").font(.headline)
                ZStack {
                    rigView(rig, rigLoader, idleParams(), mainSize)
                        .position(x: 250, y: 230)
                    ForEach(Array(offsets.enumerated()), id: \.offset) { _, vector in
                        rigView(rig, rigLoader, idleParams(), companionSize)
                            .position(x: 250 + vector.dx, y: 230 + vector.dy)
                    }
                }
                .frame(width: 700, height: 460)
            }
        }
        try render(content, size: CGSize(width: 700, height: 520), scale: 1,
                   to: dir.appendingPathComponent("47-birthday-gathering.png"))
    }

    private func renderCakeAndCelebration(
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader,
        mainSize: CGSize, companionSize: CGSize,
        store: BirthdayAssetStore, to dir: URL
    ) throws {
        let cakeView = CakePropView(store: store, cakeSize: 85)
            .frame(width: 200, height: 230)
        let cakeContent = ZStack {
            CheckerboardBackground()
            VStack(spacing: 6) {
                Text("3. cake appears (85pt, baked-in flame, sparse sparkles)").font(.headline)
                HStack(spacing: 40) {
                    rigView(rig, rigLoader, idleParams(), mainSize)
                    cakeView
                }
            }
        }
        try render(cakeContent, size: CGSize(width: 620, height: 420), scale: 1,
                   to: dir.appendingPathComponent("48-birthday-cake.png"))

        let celebration = ZStack {
            CheckerboardBackground()
            VStack(spacing: 6) {
                Text("4. celebration (staggered companions + cake)").font(.headline)
                ZStack {
                    cakeView.position(x: 250, y: 190)
                    rigView(rig, rigLoader, idleParams(), mainSize).position(x: 250, y: 240)
                    rigView(rig, rigLoader, idleParams(), companionSize).position(x: 140, y: 180)
                    rigView(rig, rigLoader, idleParams(), companionSize).position(x: 360, y: 185)
                }
                .frame(width: 620, height: 420)
            }
        }
        try render(celebration, size: CGSize(width: 620, height: 480), scale: 1,
                   to: dir.appendingPathComponent("49-birthday-celebration.png"))
    }

    private func renderAscent(rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader, companionSize: CGSize, to dir: URL) throws {
        let content = ZStack {
            CheckerboardBackground()
            VStack(spacing: 6) {
                Text("5. companion ascent (staggered upward paths)").font(.headline)
                ZStack {
                    rigView(rig, rigLoader, idleParams(), companionSize).position(x: 180, y: 300)
                    rigView(rig, rigLoader, idleParams(), companionSize).position(x: 300, y: 220)
                    rigView(rig, rigLoader, idleParams(), companionSize).position(x: 420, y: 140)
                    rigView(rig, rigLoader, idleParams(), companionSize).position(x: 520, y: 60)
                }
                .frame(width: 700, height: 420)
            }
        }
        try render(content, size: CGSize(width: 700, height: 480), scale: 1,
                   to: dir.appendingPathComponent("50-birthday-ascent.png"))
    }

    private func renderEnvelopeReveal(store: BirthdayAssetStore, to dir: URL) throws {
        let content = ZStack {
            CheckerboardBackground()
            VStack(spacing: 6) {
                Text("6. envelope reveal (closed -> open crossfade)").font(.headline)
                HStack(spacing: 50) {
                    if let closed = store.image(named: "envelope_closed.png") {
                        Image(nsImage: closed).resizable().frame(width: 62, height: 62)
                    }
                    if let open = store.image(named: "envelope_open.png") {
                        Image(nsImage: open).resizable().frame(width: 62, height: 62)
                    }
                }
            }
        }
        try render(content, size: CGSize(width: 420, height: 320), scale: 1,
                   to: dir.appendingPathComponent("51-birthday-envelope-reveal.png"))
    }

    private func renderLetterWindow(store: BirthdayAssetStore, to dir: URL) throws {
        let text = store.letterText() ?? ""
        let content = LetterView(text: text, store: store)
            .frame(width: 520, height: 600)
        try render(content, size: CGSize(width: 520, height: 600), scale: 1,
                   to: dir.appendingPathComponent("52-birthday-letter.png"))
    }

    private func renderFinalEnvelope(
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader,
        mainSize: CGSize, store: BirthdayAssetStore, to dir: URL
    ) throws {
        func sheet(background: Color, named: String, caption: Color) throws {
            let content = ZStack {
                background
                VStack(spacing: 6) {
                    Text("7. final persistent envelope (desktop size)").font(.headline).foregroundColor(caption)
                    HStack(spacing: 30) {
                        rigView(rig, rigLoader, idleParams(), mainSize)
                        if let envelope = store.image(named: "envelope_closed.png") {
                            Image(nsImage: envelope)
                                .resizable()
                                .frame(width: 62, height: 62)
                        }
                    }
                }
            }
            try render(content, size: CGSize(width: 560, height: 360), scale: 1,
                       to: dir.appendingPathComponent(named))
        }
        try sheet(background: Color(white: 0.93), named: "53-birthday-final-envelope-light.png", caption: .black)
        try sheet(background: Color(white: 0.18), named: "54-birthday-final-envelope-dark.png", caption: .white)
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
                    let rect = CGRect(
                        x: CGFloat(col) * tile,
                        y: CGFloat(row) * tile,
                        width: tile,
                        height: tile
                    )
                    context.fill(
                        Path(rect),
                        with: .color(light ? Color(white: 0.86) : Color(white: 0.64))
                    )
                }
            }
        }
    }
}
