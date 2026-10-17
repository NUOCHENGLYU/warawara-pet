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
                showSecondary: kind.showsSecondaryDecor
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

        try renderInteractionSheets(
            rig: rig, rigLoader: rigLoader, mainSize: mainSize, store: store, to: outputDir
        )
        try renderGeometryQASheet(rig: rig, rigLoader: rigLoader, mainSize: mainSize, store: store, to: outputDir)
        for name in ["70-cny-held.png", "71-cny-open.png",
                     "72-christmas-inspect.png", "73-christmas-lid-lift.png",
                     "74-newyear-confetti.png", "75-umbrella-overhead.png",
                     "76-cocoa-sip.png", "77-sprout-sway.png",
                     "78-airplane-trail.png", "79-interaction-light.png",
                     "80-interaction-dark.png", "81-qa-bounds.png"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: outputDir.appendingPathComponent(name).path),
                "missing interaction preview \(name)"
            )
        }
    }

    // MARK: - Engineering QA: real panel/hosting bounds outlines

    /// Every prop drawn at its calibrated painted size, framed by the
    /// exact NSHostingView/NSPanel bounds the presenter will allocate —
    /// with the pet for scale. Compares directly to the QA reference.
    private func renderGeometryQASheet(
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader,
        mainSize: CGSize, store: SeasonalAssetStore, to dir: URL
    ) throws {
        let kinds: [SeasonalEventKind] = [
            .hotCocoa, .cny, .christmas, .umbrella, .sprout, .newYear, .paperAirplane
        ]
        let content = ZStack {
            CheckerboardBackground()
            VStack(spacing: 10) {
                Text("production QA: painted props at calibrated size inside their panel bounds (Hpet=118)").font(.headline)
                HStack(alignment: .bottom, spacing: 14) {
                    rigView(rig, rigLoader, mainSize)
                    ForEach(kinds, id: \.self) { kind in
                        qaCell(kind: kind, store: store)
                    }
                }
            }
        }
        try render(content, size: CGSize(width: 1720, height: 720), scale: 1,
                   to: dir.appendingPathComponent("81-qa-bounds.png"))
    }

    @MainActor
    private func qaCell(kind: SeasonalEventKind, store: SeasonalAssetStore) -> some View {
        let size = PropRenderGeometry.panelSize(for: kind)
        let model = SeasonalSceneModel()
        var pose = SeasonalPropPose()
        pose.asset = kind.primaryAsset
        pose.alpha = 1
        pose.scale = 1
        pose.rotationDegrees = 0
        if kind == .christmas {
            pose.lidLift = 0.8
        }
        if kind == .paperAirplane {
            pose.showTrail = true
        }
        model.pose = pose
        let painted = PropRenderGeometry.contentSizePt(asset: kind.primaryAsset)
        return VStack(spacing: 2) {
            Text("\(kind.replayArgument)")
                .font(.caption2)
            Text("\(Int(painted.width))pt")
                .font(.caption2)
                .foregroundColor(.secondary)
            SeasonalSceneView(kind: kind, store: store, model: model)
                .frame(width: size.width, height: size.height)
                .overlay(Rectangle().stroke(Color.red.opacity(0.55), lineWidth: 1))
        }
    }

    // MARK: - Production interaction sheets (real scene view + anchors)

    /// Pseudo-world pet frame; anchors are derived from it and flipped
    /// into sheet coordinates (world y-up -> sheet y-down).
    private let worldPetFrame = CGRect(x: 220, y: 40, width: 180, height: 226)
    private let sheetBaseY: CGFloat = 360

    private func sheetPoint(_ world: CGPoint) -> CGPoint {
        CGPoint(x: world.x + 40, y: sheetBaseY - world.y)
    }

    private func anchors() -> EventAnchorSystem {
        EventAnchorSystem(petFrame: worldPetFrame)
    }

    private func pose(
        kind: SeasonalEventKind, phase: SeasonalPhase, elapsedInPhase: TimeInterval,
        totalElapsed: TimeInterval
    ) -> SeasonalPropPose {
        SeasonalChoreography.pose(
            kind: kind, phase: phase, elapsedInPhase: elapsedInPhase,
            totalElapsed: totalElapsed, anchors: anchors(),
            visibleFrame: CGRect(x: 0, y: 0, width: 640, height: 400),
            timing: .forKind(kind)
        )
    }

    private func sceneView(
        kind: SeasonalEventKind, pose: SeasonalPropPose, store: SeasonalAssetStore
    ) -> some View {
        let model = SeasonalSceneModel()
        model.pose = pose
        let size = PropRenderGeometry.panelSize(for: kind)
        return SeasonalSceneView(kind: kind, store: store, model: model)
            .frame(width: size.width, height: size.height)
    }

    private func effectView(
        asset: String, alpha: CGFloat, store: SeasonalAssetStore
    ) -> some View {
        let model = SeasonalEffectModel()
        model.asset = asset
        model.alpha = alpha
        return SeasonalEffectView(store: store, model: model)
            .frame(width: 320, height: 320)
    }

    private func interactionSheet(
        title: String,
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader, mainSize: CGSize,
        propWorld: CGPoint?, prop: AnyView,
        effect: AnyView? = nil, background: Color = Color(white: 0.93),
        caption: Color = .black
    ) -> some View {
        let petCenter = anchors().bodyRect
        let petWorld = CGPoint(x: petCenter.midX, y: petCenter.midY)
        return ZStack {
            CheckerboardBackground()
            VStack(spacing: 4) {
                Text(title).font(.headline).foregroundColor(caption)
                ZStack {
                    if let propWorld {
                        prop.position(x: sheetPoint(propWorld).x, y: sheetPoint(propWorld).y)
                    }
                    if let effect {
                        effect.position(x: sheetPoint(CGPoint(x: petWorld.x, y: petWorld.y + 40)).x,
                                        y: sheetPoint(CGPoint(x: petWorld.x, y: petWorld.y + 40)).y)
                    }
                    rigView(rig, rigLoader, mainSize)
                        .position(x: sheetPoint(petWorld).x, y: sheetPoint(petWorld).y)
                }
                .frame(width: 640, height: 400)
            }
        }
        .frame(width: 640, height: 440)
    }

    private func renderInteractionSheets(
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader,
        mainSize: CGSize, store: SeasonalAssetStore, to dir: URL
    ) throws {
        let anchors = anchors()
        let timing = SeasonalTiming.forKind(.cny)

        // 70: hongbao caught and held in the paws.
        let held = pose(kind: .cny, phase: .present, elapsedInPhase: 1.2, totalElapsed: 5)
        let heldSheet = interactionSheet(
            title: "cny: envelope caught and held in front (anchor: handFront)",
            rig: rig, rigLoader: rigLoader, mainSize: mainSize,
            propWorld: anchors.handFront,
            prop: AnyView(sceneView(kind: .cny, pose: held, store: store))
        )
        try render(heldSheet, size: CGSize(width: 640, height: 440), scale: 1,
                   to: dir.appendingPathComponent("70-cny-held.png"))

        // 71: hongbao opened (v3 artwork) during celebrate.
        var openPose = pose(kind: .cny, phase: .celebrate, elapsedInPhase: 1.6, totalElapsed: 10.5)
        openPose.asset = "cny_hongbao_open.png"
        let openSheet = interactionSheet(
            title: "cny: flap opens (CelFilm v3 opened artwork, matching clasp/tassels)",
            rig: rig, rigLoader: rigLoader, mainSize: mainSize,
            propWorld: anchors.handFront,
            prop: AnyView(sceneView(kind: .cny, pose: openPose, store: store))
        )
        try render(openSheet, size: CGSize(width: 640, height: 440), scale: 1,
                   to: dir.appendingPathComponent("71-cny-open.png"))

        // 72: gift beside the pet, inspected.
        let giftPose = pose(kind: .christmas, phase: .present, elapsedInPhase: 2, totalElapsed: 7)
        let giftSheet = interactionSheet(
            title: "christmas: gift rests beside the pet (anchor: groundBesidePet)",
            rig: rig, rigLoader: rigLoader, mainSize: mainSize,
            propWorld: anchors.groundBesidePet,
            prop: AnyView(sceneView(kind: .christmas, pose: giftPose, store: store))
        )
        try render(giftSheet, size: CGSize(width: 640, height: 440), scale: 1,
                   to: dir.appendingPathComponent("72-christmas-inspect.png"))

        // 73: lid lift (v3 base + lid layers).
        var lidPose = pose(kind: .christmas, phase: .celebrate, elapsedInPhase: 1.0, totalElapsed: 11)
        lidPose.asset = "xmas_gift_open_base.png"
        lidPose.lidLift = 0.72
        let lidSheet = interactionSheet(
            title: "christmas: lid lifts from the open base (separate v3 layers)",
            rig: rig, rigLoader: rigLoader, mainSize: mainSize,
            propWorld: anchors.groundBesidePet,
            prop: AnyView(sceneView(kind: .christmas, pose: lidPose, store: store))
        )
        try render(lidSheet, size: CGSize(width: 640, height: 440), scale: 1,
                   to: dir.appendingPathComponent("73-christmas-lid-lift.png"))

        // 74: calendar + confetti.
        let calendarPose = pose(kind: .newYear, phase: .present, elapsedInPhase: 2, totalElapsed: 5)
        let confetti = effectView(asset: "newyear_confetti_overlay.png", alpha: 0.85, store: store)
        let calendarSheet = interactionSheet(
            title: "new year: calendar beside the baseline + confetti effect",
            rig: rig, rigLoader: rigLoader, mainSize: mainSize,
            propWorld: anchors.groundBesidePet,
            prop: AnyView(sceneView(kind: .newYear, pose: calendarPose, store: store)),
            effect: AnyView(confetti)
        )
        try render(calendarSheet, size: CGSize(width: 640, height: 440), scale: 1,
                   to: dir.appendingPathComponent("74-newyear-confetti.png"))

        // 75: umbrella raised overhead with drizzle.
        let umbrellaPose = pose(kind: .umbrella, phase: .present, elapsedInPhase: 1.4,
                                totalElapsed: timing.approachDuration + 1.4)
        let rain = effectView(asset: "rain_drops_overlay.png", alpha: 0.35, store: store)
        let umbrellaSheet = interactionSheet(
            title: "umbrella: handle at the grip, canopy above the head, fictional drizzle",
            rig: rig, rigLoader: rigLoader, mainSize: mainSize,
            propWorld: CGPoint(x: anchors.handFront.x + 4, y: anchors.handFront.y + 2),
            prop: AnyView(sceneView(kind: .umbrella, pose: umbrellaPose, store: store)),
            effect: AnyView(rain)
        )
        try render(umbrellaSheet, size: CGSize(width: 640, height: 440), scale: 1,
                   to: dir.appendingPathComponent("75-umbrella-overhead.png"))

        // 76: cocoa lifted toward the face.
        let cocoaPose = pose(kind: .hotCocoa, phase: .present,
                             elapsedInPhase: SeasonalTiming.forKind(.hotCocoa).presentDuration * 0.5,
                             totalElapsed: 6)
        let cocoaSheet = interactionSheet(
            title: "hot cocoa: mug lifted from the paw toward the face",
            rig: rig, rigLoader: rigLoader, mainSize: mainSize,
            propWorld: cocoaPose.position,
            prop: AnyView(sceneView(kind: .hotCocoa, pose: cocoaPose, store: store))
        )
        try render(cocoaSheet, size: CGSize(width: 640, height: 440), scale: 1,
                   to: dir.appendingPathComponent("76-cocoa-sip.png"))

        // 77: sprout swaying at the feet.
        let sproutPose = pose(kind: .sprout, phase: .present, elapsedInPhase: 2.2, totalElapsed: 6)
        let sproutSheet = interactionSheet(
            title: "sprout: grown beside the feet, leaf swaying",
            rig: rig, rigLoader: rigLoader, mainSize: mainSize,
            propWorld: anchors.nearLeftFoot,
            prop: AnyView(sceneView(kind: .sprout, pose: sproutPose, store: store))
        )
        try render(sproutSheet, size: CGSize(width: 640, height: 440), scale: 1,
                   to: dir.appendingPathComponent("77-sprout-sway.png"))

        // 78: airplane mid-flight with its trail.
        let planeTiming = SeasonalTiming.forKind(.paperAirplane)
        let flightDuration = planeTiming.approachDuration + planeTiming.presentDuration
            + planeTiming.celebrateDuration + planeTiming.departDuration
        let planePose = pose(kind: .paperAirplane, phase: .approach,
                             elapsedInPhase: flightDuration * 0.45,
                             totalElapsed: flightDuration * 0.45)
        let planeSheet = interactionSheet(
            title: "paper airplane: continuous flyby with trail, above the head",
            rig: rig, rigLoader: rigLoader, mainSize: mainSize,
            propWorld: planePose.position,
            prop: AnyView(sceneView(kind: .paperAirplane, pose: planePose, store: store))
        )
        try render(planeSheet, size: CGSize(width: 640, height: 440), scale: 1,
                   to: dir.appendingPathComponent("78-airplane-trail.png"))

        // 79/80: light/dark composite of held envelope + umbrella.
        for (background, caption, suffix) in [
            (Color(white: 0.93), Color.black, "light"),
            (Color(white: 0.18), Color.white, "dark")
        ] {
            let sheet = interactionSheet(
                title: "cny held + umbrella overhead (\(suffix))",
                rig: rig, rigLoader: rigLoader, mainSize: mainSize,
                propWorld: anchors.handFront,
                prop: AnyView(sceneView(kind: .cny, pose: held, store: store)),
                background: background, caption: caption
            )
            try render(sheet, size: CGSize(width: 640, height: 440), scale: 1,
                       to: dir.appendingPathComponent("79-interaction-\(suffix).png"))
            // Same composition with the umbrella raised instead.
            let umbrellaSheet = interactionSheet(
                title: "umbrella overhead (\(suffix))",
                rig: rig, rigLoader: rigLoader, mainSize: mainSize,
                propWorld: CGPoint(x: anchors.handFront.x + 4, y: anchors.handFront.y + 2),
                prop: AnyView(sceneView(kind: .umbrella, pose: umbrellaPose, store: store)),
                background: background, caption: caption
            )
            try render(umbrellaSheet, size: CGSize(width: 640, height: 440), scale: 1,
                       to: dir.appendingPathComponent("80-interaction-\(suffix).png"))
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
