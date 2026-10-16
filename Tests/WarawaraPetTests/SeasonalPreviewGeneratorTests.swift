import AppKit
import SwiftUI
import XCTest
@testable import WarawaraPet

/// Seasonal & daily previews using the production rig and the real v1
/// CelFilm props. Static compositions for art QA — motion still needs
/// real-Mac testing.
@MainActor
final class SeasonalPreviewGeneratorTests: XCTestCase {
    func testGenerateSeasonalPreviews() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["SEASONAL_PREVIEW_OUT"] else {
            throw XCTSkip("SEASONAL_PREVIEW_OUT not set; skipping preview generation")
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
        let store = SeasonalAssetStore.shared
        store.reset()
        guard store.verifyAllRequiredAssets().ok else {
            throw XCTSkip("seasonal assets unavailable")
        }

        let scenes: [(String, SeasonalEventKind)] = [
            ("60-cny-present", .cny),
            ("61-cny-decor", .cny),
            ("62-christmas-gift", .christmas),
            ("63-newyear-calendar", .newYear),
            ("64-daily-umbrella", .umbrella),
            ("65-daily-cocoa", .hotCocoa),
            ("66-daily-sprout", .sprout),
            ("67-daily-airplane", .paperAirplane)
        ]

        for (name, kind) in scenes {
            let prop = SeasonalPropView(
                kind: kind, store: store,
                primarySize: kind.primaryDisplayPoints,
                showSecondary: kind == .cny
            )
            .frame(width: 220, height: 220)
            let content = ZStack {
                CheckerboardBackground()
                VStack(spacing: 6) {
                    Text("\(kind.rawValue) scene").font(.headline)
                    HStack(spacing: 30) {
                        rigView(rig, rigLoader, mainSize)
                        prop
                    }
                }
            }
            try render(content, size: CGSize(width: 620, height: 400), scale: 1,
                       to: outputDir.appendingPathComponent("\(name).png"))
        }

        // Light/dark for the CNY scene.
        for (background, caption, suffix) in [
            (Color(white: 0.93), Color.black, "light"),
            (Color(white: 0.18), Color.white, "dark")
        ] {
            let content = ZStack {
                background
                VStack(spacing: 6) {
                    Text("cny present (\(suffix))").font(.headline).foregroundColor(caption)
                    HStack(spacing: 30) {
                        rigView(rig, rigLoader, mainSize)
                        SeasonalPropView(kind: .cny, store: store, primarySize: 55, showSecondary: true)
                            .frame(width: 220, height: 220)
                    }
                }
            }
            try render(content, size: CGSize(width: 620, height: 400), scale: 1,
                       to: outputDir.appendingPathComponent("68-cny-\(suffix).png"))
        }

        for name in ["60-cny-present.png", "61-cny-decor.png", "62-christmas-gift.png",
                     "63-newyear-calendar.png", "64-daily-umbrella.png",
                     "65-daily-cocoa.png", "66-daily-sprout.png", "67-daily-airplane.png",
                     "68-cny-light.png", "68-cny-dark.png"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: outputDir.appendingPathComponent(name).path),
                "missing seasonal preview \(name)"
            )
        }
    }

    private func rigView(_ rig: WarawaraRigManifest, _ loader: WarawaraRigLoader,
                         _ size: CGSize) -> some View {
        let params = WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(state: .idle), breathPhase: 0.25
        ))
        return WarawaraLayeredCharacterView(rig: rig, rigLoader: loader, parameters: params, renderSize: size)
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
