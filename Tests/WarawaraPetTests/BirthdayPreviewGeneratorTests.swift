import AppKit
import SwiftUI
import XCTest
@testable import WarawaraPet

/// Birthday preview generator: renders the PRODUCTION views (approved
/// rig, v3 props, letter surface) into inspectable contact sheets.
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

        try renderNoticing(rig: rig, rigLoader: rigLoader, mainSize: mainSize, to: outputDir)
        try renderCarriedProps(rig: rig, rigLoader: rigLoader, mainSize: mainSize, companionSize: companionSize, store: store, to: outputDir)
        try renderPlacedProps(rig: rig, rigLoader: rigLoader, mainSize: mainSize, store: store, to: outputDir)
        try renderCelebration(rig: rig, rigLoader: rigLoader, mainSize: mainSize, companionSize: companionSize, store: store, to: outputDir)
        try renderAscent(rig: rig, rigLoader: rigLoader, companionSize: companionSize, to: outputDir)
        try renderEnvelopeReveal(store: store, to: outputDir)
        try renderLetterWindow(store: store, to: outputDir)
        try renderFinalEnvelope(rig: rig, rigLoader: rigLoader, mainSize: mainSize, store: store, to: outputDir)
        try renderSecondFixSheets(rig: rig, rigLoader: rigLoader, mainSize: mainSize, companionSize: companionSize, store: store, to: outputDir)

        for name in ["46-birthday-noticing.png", "47-birthday-carried-gifts.png",
                     "48-birthday-gifts-placed.png", "49-birthday-celebration.png",
                     "50-birthday-ascent.png", "51-birthday-envelope-reveal.png",
                     "52-birthday-letter.png", "53-birthday-final-envelope-light.png",
                     "54-birthday-final-envelope-dark.png",
                     "55-birthday-cake-carried.png", "56-birthday-envelope-carried.png",
                     "57-birthday-envelope-retired.png", "58-birthday-double-click-reopen.png"] {
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

    /// Event-attention performance: the pet turns toward the arriving
    /// companions (down-left), exactly like the production noticing beat.
    private func noticingParams() -> WarawaraPerformanceParameters {
        WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(
                state: .curious,
                gaze: CGVector(dx: -0.5, dy: -0.18)
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

    private func renderSecondFixSheets(
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader,
        mainSize: CGSize, companionSize: CGSize, store: BirthdayAssetStore, to dir: URL
    ) throws {
        // 55: cake carried at the carrier anchor (held, not pasted).
        let cakeCarried = ZStack {
            CheckerboardBackground()
            VStack(spacing: 6) {
                Text("cake carried by the lead companion (carry anchor)").font(.headline)
                ZStack {
                    rigView(rig, rigLoader, idleParams(), companionSize).position(x: 250, y: 270)
                    CakePropView(store: store, cakeSize: 85)
                        .frame(width: 200, height: 230)
                        .position(x: 250, y: 260)
                }
                .frame(width: 560, height: 400)
            }
        }
        try render(cakeCarried, size: CGSize(width: 560, height: 460), scale: 1,
                   to: dir.appendingPathComponent("55-birthday-cake-carried.png"))

        // 56: envelope carried beside its companion.
        let envelopeCarried = ZStack {
            CheckerboardBackground()
            VStack(spacing: 6) {
                Text("envelope carried by its companion (carry anchor)").font(.headline)
                ZStack {
                    rigView(rig, rigLoader, idleParams(), companionSize).position(x: 200, y: 270)
                    if let envelope = store.image(named: "envelope_closed.png") {
                        Image(nsImage: envelope)
                            .resizable()
                            .frame(width: 62, height: 62)
                            .position(x: 270, y: 290)
                    }
                }
                .frame(width: 560, height: 400)
            }
        }
        try render(envelopeCarried, size: CGSize(width: 560, height: 460), scale: 1,
                   to: dir.appendingPathComponent("56-birthday-envelope-carried.png"))

        // 57: retired state — just the pet, no intrusive envelope.
        let retired = ZStack {
            CheckerboardBackground()
            VStack(spacing: 6) {
                Text("after first read: envelope retired, desktop clean").font(.headline)
                rigView(rig, rigLoader, idleParams(), mainSize)
            }
        }
        try render(retired, size: CGSize(width: 460, height: 380), scale: 1,
                   to: dir.appendingPathComponent("57-birthday-envelope-retired.png"))

        // 58: double-click reopen composition (pet + letter window).
        let letterText = store.letterText() ?? ""
        let reopen = ZStack {
            CheckerboardBackground()
            HStack(spacing: 30) {
                rigView(rig, rigLoader, idleParams(), mainSize)
                LetterView(text: letterText, store: store)
                    .frame(width: 320, height: 360)
                    .cornerRadius(8)
            }
        }
        try render(reopen, size: CGSize(width: 760, height: 400), scale: 1,
                   to: dir.appendingPathComponent("58-birthday-double-click-reopen.png"))
    }

    private func renderNoticing(rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader, mainSize: CGSize, to dir: URL) throws {
        let content = ZStack {
            CheckerboardBackground()
            VStack(spacing: 6) {
                Text("1. noticing: event attention turns the pet toward the companions").font(.headline)
                HStack(spacing: 60) {
                    rigView(rig, rigLoader, idleParams(), mainSize)
                    rigView(rig, rigLoader, noticingParams(), mainSize)
                }
            }
        }
        try render(content, size: CGSize(width: 700, height: 420), scale: 1,
                   to: dir.appendingPathComponent("46-birthday-noticing.png"))
    }

    private func renderCarriedProps(
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader,
        mainSize: CGSize, companionSize: CGSize, store: BirthdayAssetStore, to dir: URL
    ) throws {
        // Props ride with carrier companions during entry.
        let cakeView = CakePropView(store: store, cakeSize: 85).frame(width: 200, height: 230)
        let content = ZStack {
            CheckerboardBackground()
            VStack(spacing: 6) {
                Text("2. companions enter carrying the gifts").font(.headline)
                ZStack {
                    rigView(rig, rigLoader, noticingParams(), mainSize).position(x: 300, y: 250)
                    rigView(rig, rigLoader, idleParams(), companionSize).position(x: 160, y: 300)
                    rigView(rig, rigLoader, idleParams(), companionSize).position(x: 430, y: 305)
                    cakeView.position(x: 160, y: 130)
                    if let envelope = store.image(named: "envelope_closed.png") {
                        Image(nsImage: envelope)
                            .resizable()
                            .frame(width: 62, height: 62)
                            .position(x: 450, y: 210)
                    }
                }
                .frame(width: 700, height: 420)
            }
        }
        try render(content, size: CGSize(width: 700, height: 480), scale: 1,
                   to: dir.appendingPathComponent("47-birthday-carried-gifts.png"))
    }

    private func renderPlacedProps(
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader,
        mainSize: CGSize, store: BirthdayAssetStore, to dir: URL
    ) throws {
        // The stable front-of-pet layout from BirthdayPropLayout.
        let cakePanel = CGSize(width: 200, height: 230)
        let envelopePanel = CGSize(width: 100, height: 100)
        let origins = BirthdayPropLayout.deliveryOrigins(
            petFrame: CGRect(x: 250, y: 80, width: 200, height: 226),
            cakePanelSize: cakePanel,
            envelopePanelSize: envelopePanel,
            visibleFrame: CGRect(x: 0, y: 0, width: 700, height: 460)
        )
        let content = ZStack {
            CheckerboardBackground()
            VStack(spacing: 6) {
                Text("3. gifts placed in front of the pet (stable desktop layout)").font(.headline)
                ZStack {
                    rigView(rig, rigLoader, idleParams(), mainSize)
                        .position(x: 350, y: 193)
                    CakePropView(store: store, cakeSize: 85)
                        .frame(width: cakePanel.width, height: cakePanel.height)
                        .position(x: origins.cake.x + cakePanel.width / 2, y: origins.cake.y + cakePanel.height / 2)
                    if let envelope = store.image(named: "envelope_closed.png") {
                        Image(nsImage: envelope)
                            .resizable()
                            .frame(width: 62, height: 62)
                            .position(x: origins.envelope.x + envelopePanel.width / 2, y: origins.envelope.y + envelopePanel.height / 2)
                    }
                }
                .frame(width: 700, height: 460)
            }
        }
        try render(content, size: CGSize(width: 700, height: 520), scale: 1,
                   to: dir.appendingPathComponent("48-birthday-gifts-placed.png"))
    }

    private func renderCelebration(
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader,
        mainSize: CGSize, companionSize: CGSize, store: BirthdayAssetStore, to dir: URL
    ) throws {
        let content = ZStack {
            CheckerboardBackground()
            VStack(spacing: 6) {
                Text("4. celebration around the placed gifts").font(.headline)
                ZStack {
                    rigView(rig, rigLoader, idleParams(), mainSize).position(x: 300, y: 250)
                    rigView(rig, rigLoader, idleParams(), companionSize).position(x: 140, y: 200)
                    rigView(rig, rigLoader, idleParams(), companionSize).position(x: 360, y: 205)
                    CakePropView(store: store, cakeSize: 85).frame(width: 200, height: 230)
                        .position(x: 230, y: 150)
                }
                .frame(width: 620, height: 420)
            }
        }
        try render(content, size: CGSize(width: 620, height: 480), scale: 1,
                   to: dir.appendingPathComponent("49-birthday-celebration.png"))
    }

    private func renderAscent(rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader, companionSize: CGSize, to dir: URL) throws {
        let content = ZStack {
            CheckerboardBackground()
            VStack(spacing: 6) {
                Text("5. continuous ascent and exit").font(.headline)
                ZStack {
                    rigView(rig, rigLoader, idleParams(), companionSize).position(x: 160, y: 320)
                    rigView(rig, rigLoader, idleParams(), companionSize).position(x: 300, y: 240)
                    rigView(rig, rigLoader, idleParams(), companionSize).position(x: 420, y: 160)
                    rigView(rig, rigLoader, idleParams(), companionSize).position(x: 520, y: 70)
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
                Text("6. envelope reveal (v3, closed -> open crossfade)").font(.headline)
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
                    Text("7. final stationary envelope (desktop size)").font(.headline).foregroundColor(caption)
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
