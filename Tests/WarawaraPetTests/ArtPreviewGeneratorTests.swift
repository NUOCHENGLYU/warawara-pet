import AppKit
import SwiftUI
import XCTest
@testable import WarawaraPet

/// Offline artwork preview generator. When ART_PREVIEW_OUT is set (CI),
/// renders inspectable PNG contact sheets into that directory using the
/// real placeholder views and pose math. All output uses the procedural
/// PLACEHOLDER artwork 鈥?it is not a fidelity claim.
@MainActor
final class ArtPreviewGeneratorTests: XCTestCase {
    private let mainCanvas = CGSize(width: 200, height: 226)

    func testGenerateArtPreviews() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["ART_PREVIEW_OUT"] else {
            throw XCTSkip("ART_PREVIEW_OUT not set; skipping preview generation")
        }
        let outputDir = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        try renderNeutralPreview(to: outputDir)
        try renderIdleContactSheet(to: outputDir)
        try renderHopContactSheet(to: outputDir)
        try renderFloatContactSheet(to: outputDir)
        try renderStateSamples(to: outputDir)
        try renderDragExtremes(to: outputDir)
        try renderGroupPreview(to: outputDir)
        try renderActualSizePreview(to: outputDir)
        try renderComparisonNote(to: outputDir)

        let expected = [
            "01-neutral-main.png", "01-neutral-main-4x.png",
            "02-contact-idle.png", "03-contact-hop.png", "04-contact-float.png",
            "05-states.png", "06-drag-extremes.png", "07-group.png",
            "08-actual-size.png", "09-comparison-note.png", "README.txt"
        ]
        for name in expected {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: outputDir.appendingPathComponent(name).path),
                "missing preview output \(name)"
            )
        }
    }

    // MARK: - Candidate sprite previews (when sprites.json + PNGs exist)

    func testGenerateCandidateSpritePreviews() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["ART_PREVIEW_OUT"] else {
            throw XCTSkip("ART_PREVIEW_OUT not set; skipping preview generation")
        }
        let loader = WarawaraSpriteLoader.shared
        var baseURL: URL?
        if !loader.hasSprites {
            let repoResources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/WarawaraPet/Resources/Sprites")
            let candidates: [URL] = [repoResources, WarawaraSpriteLoader.defaultResourceURL]
                .compactMap { $0 }
            for url in candidates {
                loader.reset()
                if loader.loadManifest(from: url) {
                    baseURL = url
                    break
                }
            }
        }
        guard loader.hasSprites,
              let baseURL,
              let manifest = loader.manifest else {
            var detail = loader.lastErrorDescription ?? "unknown error"
            let manifestFile = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/WarawaraPet/Resources/Sprites/sprites.json")
            if let data = try? Data(contentsOf: manifestFile) {
                let head = data.prefix(48).map { String(format: "%02X", $0) }.joined(separator: " ")
                detail += " | bytes=\(data.count) head=\(head)"
            } else {
                detail += " | manifest file missing at \(manifestFile.path)"
            }
            throw XCTSkip("no sprite manifest available (\(detail))")
        }
        let outputDir = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        try renderCandidateNeutral(loader: loader, baseURL: baseURL, manifest: manifest, to: outputDir)
        try renderCandidateAnimationFrames(loader: loader, baseURL: baseURL, manifest: manifest, to: outputDir)
        try renderCandidateStates(loader: loader, baseURL: baseURL, manifest: manifest, to: outputDir)
        try renderCandidateDragExtremes(loader: loader, baseURL: baseURL, manifest: manifest, to: outputDir)
        try renderCandidateGroup(loader: loader, baseURL: baseURL, manifest: manifest, to: outputDir)

        for name in ["10-candidate-neutral.png", "10-candidate-neutral-4x.png",
                     "11-candidate-idle-frames.png", "12-candidate-hop-frames.png",
                     "13-candidate-float-frames.png", "14-candidate-states.png",
                     "15-candidate-drag-extremes.png", "16-candidate-group.png",
                     "17-candidate-actual-size.png"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: outputDir.appendingPathComponent(name).path),
                "missing candidate preview \(name)"
            )
        }
    }

    @MainActor
    private func candidateFrameView(
        _ path: String,
        loader: WarawaraSpriteLoader,
        baseURL: URL,
        manifest: WarawaraSpriteManifest,
        targetBodyHeight: CGFloat
    ) -> WarawaraSpriteFrameView? {
        guard let image = loader.image(forRelativePath: path, baseURL: baseURL) else { return nil }
        let bodyHeightInCanvas = manifest.layout.bodyBounds.height * manifest.layout.canvas.height
        let renderSize = WarawaraAnimationMapper.renderSize(
            canvas: manifest.layout.canvas,
            bodyHeightInCanvas: bodyHeightInCanvas,
            targetBodyHeight: targetBodyHeight
        )
        return WarawaraSpriteFrameView(
            image: image,
            renderSize: renderSize,
            anchor: manifest.layout.anchor
        )
    }

    @MainActor
    private func renderCandidateNeutral(
        loader: WarawaraSpriteLoader, baseURL: URL, manifest: WarawaraSpriteManifest, to dir: URL
    ) throws {
        guard let frame = candidateFrameView("idle/idle_00.png", loader: loader, baseURL: baseURL,
                                             manifest: manifest, targetBodyHeight: PetMetrics.blobHeight) else {
            throw NSError(
                domain: "ArtPreviewGenerator",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "cannot render idle_00 from \(baseURL.path): \(loader.lastErrorDescription ?? "unknown")"
                ]
            )
        }
        let content = ZStack { CheckerboardBackground(); frame }
        try render(content, size: mainCanvas, scale: 1, to: dir.appendingPathComponent("10-candidate-neutral.png"))
        try render(content, size: mainCanvas, scale: 4, to: dir.appendingPathComponent("10-candidate-neutral-4x.png"))
        try render(content, size: mainCanvas, scale: 1, to: dir.appendingPathComponent("17-candidate-actual-size.png"))
    }

    @MainActor
    private func renderCandidateAnimationFrames(
        loader: WarawaraSpriteLoader, baseURL: URL, manifest: WarawaraSpriteManifest, to dir: URL
    ) throws {
        func sheet(animation: String, output: String) throws {
            guard let anim = manifest.animations[animation] else { return }
            let frames = anim.frames.compactMap {
                candidateFrameView($0, loader: loader, baseURL: baseURL, manifest: manifest,
                                   targetBodyHeight: PetMetrics.blobHeight)
            }
            guard !frames.isEmpty else { return }
            let content = ZStack {
                CheckerboardBackground()
                HStack(spacing: 24) {
                    ForEach(frames.indices, id: \.self) { index in
                        VStack {
                            frames[index]
                            Text("\(animation) \(index)").font(.caption)
                        }
                    }
                }
            }
            try render(content, size: CGSize(width: 1500, height: 400), scale: 1,
                       to: dir.appendingPathComponent(output))
        }
        try sheet(animation: "idle", output: "11-candidate-idle-frames.png")
        try sheet(animation: "hop", output: "12-candidate-hop-frames.png")
        try sheet(animation: "float", output: "13-candidate-float-frames.png")
    }

    @MainActor
    private func renderCandidateStates(
        loader: WarawaraSpriteLoader, baseURL: URL, manifest: WarawaraSpriteManifest, to dir: URL
    ) throws {
        func view(_ path: String) -> WarawaraSpriteFrameView? {
            candidateFrameView(path, loader: loader, baseURL: baseURL, manifest: manifest,
                               targetBodyHeight: PetMetrics.blobHeight)
        }
        let content = ZStack {
            CheckerboardBackground()
            HStack(spacing: 28) {
                VStack { view("clicked/clicked_00.png"); Text("clicked").font(.caption) }
                VStack { view("sleepy/sleepy_00.png"); Text("sleepy").font(.caption) }
                VStack { view("sleeping/sleeping_00.png"); Text("sleeping").font(.caption) }
                VStack { view("curious/curious_00.png"); Text("curious").font(.caption) }
            }
        }
        try render(content, size: CGSize(width: 1300, height: 420), scale: 1,
                   to: dir.appendingPathComponent("14-candidate-states.png"))
    }

    @MainActor
    private func renderCandidateDragExtremes(
        loader: WarawaraSpriteLoader, baseURL: URL, manifest: WarawaraSpriteManifest, to dir: URL
    ) throws {
        guard let frame = candidateFrameView("dragged/dragged_00.png", loader: loader, baseURL: baseURL,
                                             manifest: manifest, targetBodyHeight: PetMetrics.blobHeight) else {
            throw NSError(domain: "ArtPreviewGenerator", code: 4)
        }
        let content = ZStack {
            CheckerboardBackground()
            HStack(spacing: 28) {
                VStack { frame.scaleEffect(x: 1.35, y: 1 / 1.35, anchor: .center); Text("stretch h 1.35").font(.caption) }
                VStack { frame.scaleEffect(x: 1 / 1.35, y: 1.35, anchor: .center); Text("stretch v 1.35").font(.caption) }
                VStack { frame.rotationEffect(.radians(0.12), anchor: .center); Text("lean +0.12").font(.caption) }
                VStack { frame.rotationEffect(.radians(-0.12), anchor: .center); Text("lean -0.12").font(.caption) }
            }
        }
        try render(content, size: CGSize(width: 1400, height: 420), scale: 1,
                   to: dir.appendingPathComponent("15-candidate-drag-extremes.png"))
    }

    @MainActor
    private func renderCandidateGroup(
        loader: WarawaraSpriteLoader, baseURL: URL, manifest: WarawaraSpriteManifest, to dir: URL
    ) throws {
        guard let mainFrame = candidateFrameView("idle/idle_00.png", loader: loader, baseURL: baseURL,
                                                 manifest: manifest, targetBodyHeight: PetMetrics.blobHeight),
              let companionFrame = candidateFrameView("idle/idle_00.png", loader: loader, baseURL: baseURL,
                                                      manifest: manifest, targetBodyHeight: CompanionMetrics.blobHeight)
        else {
            throw NSError(domain: "ArtPreviewGenerator", code: 5)
        }
        let content = ZStack {
            CheckerboardBackground()
            HStack(spacing: 26) {
                mainFrame
                companionFrame
                companionFrame.scaleEffect(0.85)
                companionFrame
                companionFrame.scaleEffect(0.95)
            }
        }
        try render(content, size: CGSize(width: 1500, height: 420), scale: 1,
                   to: dir.appendingPathComponent("16-candidate-group.png"))
    }

    // MARK: - Renderer

    @MainActor
    private func render(_ view: some View, size: CGSize, scale: CGFloat, to url: URL) throws {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = scale
        renderer.isOpaque = false
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ArtPreviewGenerator", code: 1)
        }
        try png.write(to: url)
    }

    private func writeNote(_ text: String, to url: URL) throws {
        try text.data(using: .utf8)?.write(to: url)
    }

    // MARK: - Content

    private var placeholderMain: some View {
        PlaceholderWarawaraView(sizeClass: .main)
    }

    private var placeholderCompanion: some View {
        PlaceholderWarawaraView(sizeClass: .companion, scale: 0.9)
    }

    @MainActor
    private func renderNeutralPreview(to dir: URL) throws {
        let content = ZStack {
            CheckerboardBackground()
            placeholderMain
        }
        try render(content, size: mainCanvas, scale: 1, to: dir.appendingPathComponent("01-neutral-main.png"))
        try render(content, size: mainCanvas, scale: 4, to: dir.appendingPathComponent("01-neutral-main-4x.png"))
    }

    @MainActor
    private func renderIdleContactSheet(to dir: URL) throws {
        let offsets: [CGFloat] = [-6, -3, 0, 3, 6]
        let content = ZStack {
            CheckerboardBackground()
            HStack(spacing: 24) {
                ForEach(offsets, id: \.self) { offset in
                    VStack {
                        self.placeholderMain.offset(y: offset)
                        Text("bob \(Int(offset))").font(.caption)
                    }
                }
            }
        }
        try render(content, size: CGSize(width: 1400, height: 400), scale: 1,
                   to: dir.appendingPathComponent("02-contact-idle.png"))
    }

    @MainActor
    private func renderHopContactSheet(to dir: URL) throws {
        let samples: [CGFloat] = [0, 0.2, 0.4, 0.6, 0.85, 1]
        let content = ZStack {
            CheckerboardBackground()
            HStack(spacing: 24) {
                ForEach(samples, id: \.self) { t in
                    VStack {
                        let stretch = HopCurve.stretchFactor(at: t)
                        let squash = HopCurve.squashAtLanding(at: t)
                        let sx = 1 - 0.08 * stretch + 0.15 * squash
                        let sy = 1 + 0.12 * stretch - 0.3 * squash
                        self.placeholderMain
                            .scaleEffect(x: sx, y: sy, anchor: .bottom)
                            .offset(y: -HopCurve.offsetY(at: t, height: 80))
                        Text(String(format: "t=%.2f", t)).font(.caption)
                    }
                }
            }
        }
        try render(content, size: CGSize(width: 1500, height: 460), scale: 1,
                   to: dir.appendingPathComponent("03-contact-hop.png"))
    }

    @MainActor
    private func renderFloatContactSheet(to dir: URL) throws {
        let samples: [CGFloat] = [0.1, 0.35, 0.6, 0.85]
        let content = ZStack {
            CheckerboardBackground()
            HStack(spacing: 24) {
                ForEach(samples, id: \.self) { t in
                    VStack {
                        let stretch = sin(.pi * t)
                        self.placeholderMain
                            .scaleEffect(x: 1 - 0.05 * stretch, y: 1 + 0.08 * stretch, anchor: .bottom)
                            .offset(y: -FloatCurve.offsetY(at: t, height: 100, tuning: PersonalityTuning.default))
                        Text(String(format: "t=%.2f", t)).font(.caption)
                    }
                }
            }
        }
        try render(content, size: CGSize(width: 1100, height: 460), scale: 1,
                   to: dir.appendingPathComponent("04-contact-float.png"))
    }

    @MainActor
    private func renderStateSamples(to dir: URL) throws {
        let content = ZStack {
            CheckerboardBackground()
            HStack(spacing: 28) {
                VStack {
                    placeholderMain.scaleEffect(x: 1.04, y: 0.78, anchor: .bottom)
                    Text("clicked").font(.caption)
                }
                VStack {
                    placeholderMain.scaleEffect(x: 1.02, y: 0.93, anchor: .bottom)
                    Text("sleepy").font(.caption)
                }
                VStack {
                    ZStack {
                        placeholderMain.scaleEffect(x: 1.03, y: 0.88, anchor: .bottom)
                        Text("Z").font(.system(size: 14, weight: .bold)).offset(x: 26, y: -60)
                    }
                    Text("sleeping").font(.caption)
                }
                VStack {
                    placeholderMain
                        .rotationEffect(.radians(-0.08), anchor: .bottom)
                        .scaleEffect(x: 1 / 1.05, y: 1.05, anchor: .bottom)
                    Text("curious").font(.caption)
                }
            }
        }
        try render(content, size: CGSize(width: 1300, height: 420), scale: 1,
                   to: dir.appendingPathComponent("05-states.png"))
    }

    @MainActor
    private func renderDragExtremes(to dir: URL) throws {
        let content = ZStack {
            CheckerboardBackground()
            HStack(spacing: 28) {
                VStack {
                    placeholderMain.scaleEffect(x: 1.35, y: 1 / 1.35, anchor: .bottom)
                    Text("stretch h 1.35").font(.caption)
                }
                VStack {
                    placeholderMain.scaleEffect(x: 1 / 1.35, y: 1.35, anchor: .bottom)
                    Text("stretch v 1.35").font(.caption)
                }
                VStack {
                    placeholderMain.rotationEffect(.radians(0.12), anchor: .bottom)
                    Text("lean +0.12").font(.caption)
                }
                VStack {
                    placeholderMain.rotationEffect(.radians(-0.12), anchor: .bottom)
                    Text("lean -0.12").font(.caption)
                }
                VStack {
                    placeholderMain
                        .rotationEffect(.radians(Double.pi / 4), anchor: .bottom)
                        .scaleEffect(x: 1.35, y: 1 / 1.35, anchor: .bottom)
                        .rotationEffect(.radians(-Double.pi / 4), anchor: .bottom)
                    Text("diagonal 1.35").font(.caption)
                }
            }
        }
        try render(content, size: CGSize(width: 1600, height: 420), scale: 1,
                   to: dir.appendingPathComponent("06-drag-extremes.png"))
    }

    @MainActor
    private func renderGroupPreview(to dir: URL) throws {
        let content = ZStack {
            CheckerboardBackground()
            HStack(spacing: 26) {
                placeholderMain
                placeholderCompanion
                placeholderCompanion.scaleEffect(0.85)
                placeholderCompanion.scaleEffect(1.0)
                placeholderCompanion.scaleEffect(0.95)
            }
        }
        try render(content, size: CGSize(width: 1500, height: 400), scale: 1,
                   to: dir.appendingPathComponent("07-group.png"))
    }

    @MainActor
    private func renderActualSizePreview(to dir: URL) throws {
        let content = ZStack {
            CheckerboardBackground(tile: 4)
            placeholderMain
        }
        try render(content, size: mainCanvas, scale: 1,
                   to: dir.appendingPathComponent("08-actual-size.png"))
    }

    // MARK: - Phase 5B layered rig previews (real supplied assets)

    /// Renders layered-rig state sheets using the REAL handoff assets
    /// (Assets/WarawaraRig). Multi-sample sequences show continuous
    /// expression behavior: gaze, blink, openness, sleep/wake, press
    /// rebound, drag, mouth styles, and main/companion scaling.
    func testGenerateRigStatePreviews() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["ART_PREVIEW_OUT"] else {
            throw XCTSkip("ART_PREVIEW_OUT not set; skipping preview generation")
        }
        let outputDir = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let repoRigRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/WarawaraPet/Resources/Assets/WarawaraRig")
        let rigLoader = WarawaraRigLoader()
        guard rigLoader.loadManifest(from: repoRigRoot),
              let rig = rigLoader.rig else {
            throw XCTSkip("real rig not available: \(rigLoader.lastErrorDescription ?? "unknown")")
        }
        guard let renderSize = WarawaraExpressionDriver.renderSize(
            rig: rig, targetBodyHeight: PetMetrics.blobHeight
        ) else {
            throw XCTSkip("rig has no render size")
        }

        try renderRigNeutralAndComparison(rig: rig, rigLoader: rigLoader, renderSize: renderSize, to: outputDir)
        try renderRigGazeSamples(rig: rig, rigLoader: rigLoader, renderSize: renderSize, to: outputDir)
        try renderRigBlinkProgression(rig: rig, rigLoader: rigLoader, renderSize: renderSize, to: outputDir)
        try renderRigOpennessProgression(rig: rig, rigLoader: rigLoader, renderSize: renderSize, to: outputDir)
        try renderRigSleepAndWake(rig: rig, rigLoader: rigLoader, renderSize: renderSize, to: outputDir)
        try renderRigPressRebound(rig: rig, rigLoader: rigLoader, renderSize: renderSize, to: outputDir)
        try renderRigDragReaction(rig: rig, rigLoader: rigLoader, renderSize: renderSize, to: outputDir)
        try renderRigMouthStyles(rig: rig, rigLoader: rigLoader, renderSize: renderSize, to: outputDir)
        try renderRigMainVsCompanion(rig: rig, rigLoader: rigLoader, renderSize: renderSize, to: outputDir)

        for name in ["18-rig-neutral.png", "19-rig-old-vs-recomposed.png",
                     "20-rig-gaze.png", "21-rig-blink.png", "22-rig-openness.png",
                     "23-rig-sleep-wake.png", "24-rig-wake.png",
                     "25-rig-press-rebound.png", "26-rig-drag.png",
                     "27-rig-mouth-styles.png", "28-rig-main-vs-companion.png"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: outputDir.appendingPathComponent(name).path),
                "missing rig preview \(name)"
            )
        }
    }

    @MainActor
    private func rigView(
        _ rig: WarawaraRigManifest,
        _ rigLoader: WarawaraRigLoader,
        _ parameters: WarawaraPerformanceParameters,
        _ renderSize: CGSize
    ) -> some View {
        WarawaraLayeredCharacterView(
            rig: rig,
            rigLoader: rigLoader,
            parameters: parameters,
            renderSize: renderSize
        )
    }

    @MainActor
    private func rigSampleSheet(
        samples: [(String, WarawaraPerformanceParameters)],
        rig: WarawaraRigManifest,
        rigLoader: WarawaraRigLoader,
        renderSize: CGSize,
        title: String,
        to outputDir: URL,
        named fileName: String
    ) throws {
        let content = ZStack {
            CheckerboardBackground()
            VStack(spacing: 6) {
                Text(title).font(.headline)
                HStack(spacing: 28) {
                    ForEach(samples.indices, id: \.self) { index in
                        VStack(spacing: 4) {
                            self.rigView(rig, rigLoader, samples[index].1, renderSize)
                            Text(samples[index].0).font(.caption)
                        }
                    }
                }
            }
        }
        try render(content, size: CGSize(width: 1500, height: 460), scale: 1,
                   to: outputDir.appendingPathComponent(fileName))
    }

    @MainActor
    private func rigSingleSheet(
        rig: WarawaraRigManifest,
        rigLoader: WarawaraRigLoader,
        parameters: WarawaraPerformanceParameters,
        renderSize: CGSize,
        title: String,
        to outputDir: URL,
        named fileName: String
    ) throws {
        let content = ZStack {
            CheckerboardBackground()
            VStack(spacing: 8) {
                Text(title).font(.headline)
                rigView(rig, rigLoader, parameters, renderSize)
            }
        }
        try render(content, size: mainCanvas, scale: 2,
                   to: outputDir.appendingPathComponent(fileName))
    }

    @MainActor
    private func idleParameters(blink: CGFloat = 0, breath: CGFloat = 0.25) -> WarawaraPerformanceParameters {
        WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(state: .idle),
            breathPhase: breath,
            blink: blink
        ))
    }

    @MainActor
    private func renderRigNeutralAndComparison(
        rig: WarawaraRigManifest,
        rigLoader: WarawaraRigLoader,
        renderSize: CGSize,
        to dir: URL
    ) throws {
        let neutral = idleParameters()
        try rigSingleSheet(rig: rig, rigLoader: rigLoader, parameters: neutral,
                           renderSize: renderSize, title: "rig neutral (idle)",
                           to: dir, named: "18-rig-neutral.png")

        // Old (single sprite) vs recomposed (rig neutral): they must match
        // the accepted Phase 4B appearance.
        let spriteLoader = WarawaraSpriteLoader()
        let spriteRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/WarawaraPet/Resources/Sprites")
        guard spriteLoader.loadManifest(from: spriteRoot),
              let spriteManifest = spriteLoader.manifest,
              let oldImage = spriteLoader.image(
                forRelativePath: "warawara_neutral.png", baseURL: spriteRoot
              ) else {
            throw XCTSkip("single sprite unavailable for comparison")
        }
        let oldRenderSize = WarawaraAnimationMapper.renderSize(
            canvas: spriteManifest.layout.canvas,
            bodyHeightInCanvas: spriteManifest.layout.bodyBounds.height * spriteManifest.layout.canvas.height,
            targetBodyHeight: PetMetrics.blobHeight
        )
        let content = ZStack {
            CheckerboardBackground()
            HStack(spacing: 60) {
                VStack(spacing: 4) {
                    WarawaraSpriteFrameView(
                        image: oldImage,
                        renderSize: oldRenderSize,
                        anchor: spriteManifest.layout.anchor
                    )
                    Text("Phase 4B single sprite").font(.caption)
                }
                VStack(spacing: 4) {
                    rigView(rig, rigLoader, neutral, renderSize)
                    Text("rig recomposed neutral").font(.caption)
                }
            }
        }
        try render(content, size: CGSize(width: 800, height: 420), scale: 1,
                   to: dir.appendingPathComponent("19-rig-old-vs-recomposed.png"))
    }

    @MainActor
    private func renderRigGazeSamples(
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader, renderSize: CGSize, to dir: URL
    ) throws {
        let samples: [(String, WarawaraPerformanceParameters)] = [
            ("left", WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
                inputs: WarawaraExpressionInputs(state: .curious, gaze: CGVector(dx: -0.7, dy: 0)), breathPhase: 0.2))),
            ("center", idleParameters()),
            ("right", WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
                inputs: WarawaraExpressionInputs(state: .curious, gaze: CGVector(dx: 0.7, dy: 0)), breathPhase: 0.2)))
        ]
        try rigSampleSheet(samples: samples, rig: rig, rigLoader: rigLoader, renderSize: renderSize,
                           title: "gaze: left / center / right", to: dir, named: "20-rig-gaze.png")
    }

    @MainActor
    private func renderRigBlinkProgression(
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader, renderSize: CGSize, to dir: URL
    ) throws {
        let samples: [(String, WarawaraPerformanceParameters)] = [
            ("open", idleParameters(blink: 0)),
            ("closing", idleParameters(blink: 0.4)),
            ("half", idleParameters(blink: 0.75)),
            ("closed", idleParameters(blink: 1)),
            ("reopening", idleParameters(blink: 0.5))
        ]
        try rigSampleSheet(samples: samples, rig: rig, rigLoader: rigLoader, renderSize: renderSize,
                           title: "blink progression (continuous)", to: dir, named: "21-rig-blink.png")
    }

    @MainActor
    private func renderRigOpennessProgression(
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader, renderSize: CGSize, to dir: URL
    ) throws {
        let samples: [(String, WarawaraPerformanceParameters)] = [1.0, 0.7, 0.45, 0.2, 0.05].map { openness in
            var p = self.idleParameters()
            p.eyeOpenness = openness
            p.mouthStyle = .relaxed
            return ("\(Int(openness * 100))%", p)
        }
        try rigSampleSheet(samples: samples, rig: rig, rigLoader: rigLoader, renderSize: renderSize,
                           title: "eye openness progression", to: dir, named: "22-rig-openness.png")
    }

    @MainActor
    private func renderRigSleepAndWake(
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader, renderSize: CGSize, to dir: URL
    ) throws {
        let frameDT = 1.0 / 30.0
        var animator = WarawaraParameterAnimator()
        animator.set(idleParameters())

        let sleepyTarget = WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(state: .sleepy), breathPhase: 0.5))
        var sleepySamples: [(String, WarawaraPerformanceParameters)] = []
        for step in [10, 40] {
            for _ in 0..<step { animator.step(toward: sleepyTarget, dt: frameDT) }
            sleepySamples.append(("sleepy +\(step)f", animator.parameters))
        }
        let sleepingTarget = WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(state: .sleeping), breathPhase: 0.6))
        for step in [20, 80] {
            for _ in 0..<step { animator.step(toward: sleepingTarget, dt: frameDT) }
            sleepySamples.append(("sleeping +\(step)f", animator.parameters))
        }
        try rigSampleSheet(samples: sleepySamples, rig: rig, rigLoader: rigLoader, renderSize: renderSize,
                           title: "sleepy -> sleeping (continuous)", to: dir, named: "23-rig-sleep-wake.png")

        // Wake: sleeping back to idle 鈥?continuous reopening.
        let wakeTarget = idleParameters()
        var wakeSamples: [(String, WarawaraPerformanceParameters)] = []
        var wakeAnimator = WarawaraParameterAnimator()
        wakeAnimator.set(sleepingTarget)
        for step in [8, 25, 60, 120] {
            for _ in 0..<step { wakeAnimator.step(toward: wakeTarget, dt: frameDT) }
            wakeSamples.append(("wake +\(step)f", wakeAnimator.parameters))
        }
        try rigSampleSheet(samples: wakeSamples, rig: rig, rigLoader: rigLoader, renderSize: renderSize,
                           title: "wake progression (continuous reopening)", to: dir, named: "24-rig-wake.png")
    }

    @MainActor
    private func renderRigPressRebound(
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader, renderSize: CGSize, to dir: URL
    ) throws {
        let frameDT = 1.0 / 30.0
        var animator = WarawaraParameterAnimator()
        animator.set(idleParameters())
        let pressedTarget = WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(state: .clicked), breathPhase: 0.3))
        var samples: [(String, WarawaraPerformanceParameters)] = []
        for _ in 0..<3 { animator.step(toward: pressedTarget, dt: frameDT) }
        samples.append(("pressed +3f", animator.parameters))
        for _ in 0..<8 { animator.step(toward: pressedTarget, dt: frameDT) }
        samples.append(("pressed +11f", animator.parameters))
        let idleTarget = idleParameters()
        for step in [6, 20, 60] {
            for _ in 0..<step { animator.step(toward: idleTarget, dt: frameDT) }
            samples.append(("rebound +\(step)f", animator.parameters))
        }
        try rigSampleSheet(samples: samples, rig: rig, rigLoader: rigLoader, renderSize: renderSize,
                           title: "pressed / rebound (soft recovery)", to: dir, named: "25-rig-press-rebound.png")
    }

    @MainActor
    private func renderRigDragReaction(
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader, renderSize: CGSize, to dir: URL
    ) throws {
        func dragContext(_ direction: CGVector) -> WarawaraExpressionContext {
            let limit = DeformationTuning.default.grabAnchorLimit
            return WarawaraExpressionContext(
                inputs: WarawaraExpressionInputs(
                    state: .dragged,
                    dragDeformation: PetDeformation(
                        stretchAngle: 0,
                        stretchScale: 1 + DeformationTuning.default.maxStretch * 0.7,
                        perpendicularScale: 1,
                        rotation: 0,
                        anchor: CGVector(dx: direction.dx * limit, dy: direction.dy * limit)
                    )
                ),
                breathPhase: 0.3
            )
        }
        let samples: [(String, WarawaraPerformanceParameters)] = [
            ("drag left", WarawaraExpressionMapper.targetParameters(for: dragContext(CGVector(dx: -1, dy: 0.2)))),
            ("drag right", WarawaraExpressionMapper.targetParameters(for: dragContext(CGVector(dx: 1, dy: 0.2)))),
            ("drag up", WarawaraExpressionMapper.targetParameters(for: dragContext(CGVector(dx: 0, dy: 1))))
        ]
        try rigSampleSheet(samples: samples, rig: rig, rigLoader: rigLoader, renderSize: renderSize,
                           title: "drag facial reaction", to: dir, named: "26-rig-drag.png")
    }

    @MainActor
    private func renderRigMouthStyles(
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader, renderSize: CGSize, to dir: URL
    ) throws {
        var samples: [(String, WarawaraPerformanceParameters)] = []
        for style in WarawaraMouthStyle.allCases {
            var p = idleParameters()
            p.mouthStyle = style
            samples.append((style.rawValue, p))
        }
        var openSample = idleParameters()
        openSample.mouthStyle = .open
        openSample.mouthOpenAmount = 0.7
        samples.append(("open x0.7", openSample))
        try rigSampleSheet(samples: samples, rig: rig, rigLoader: rigLoader, renderSize: renderSize,
                           title: "mouth styles + open scaling", to: dir, named: "27-rig-mouth-styles.png")
    }

    @MainActor
    private func renderRigMainVsCompanion(
        rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader, renderSize: CGSize, to dir: URL
    ) throws {
        guard let companionSize = WarawaraExpressionDriver.renderSize(
            rig: rig, targetBodyHeight: CompanionMetrics.blobHeight
        ) else {
            throw XCTSkip("rig has no companion render size")
        }
        let content = ZStack {
            CheckerboardBackground()
            HStack(spacing: 80) {
                VStack(spacing: 4) {
                    rigView(rig, rigLoader, idleParameters(), renderSize)
                    Text("main 118 pt").font(.caption)
                }
                VStack(spacing: 4) {
                    rigView(rig, rigLoader, idleParameters(), companionSize)
                    Text("companion 74 pt").font(.caption)
                }
            }
        }
        try render(content, size: CGSize(width: 800, height: 420), scale: 1,
                   to: dir.appendingPathComponent("28-rig-main-vs-companion.png"))
    }

    private func renderComparisonNote(to dir: URL) throws {
        let content = ZStack {
            CheckerboardBackground()
            VStack(spacing: 14) {
                placeholderMain
                Text("CANDIDATE 鈥?awaiting visual approval")
                    .font(.headline)
                Text("Placeholder artwork only. Compare against official stills listed in")
                    .font(.caption)
                Text("docs/art/WARAWARA_REFERENCE_SPEC.md (references are not bundled).")
                    .font(.caption)
            }
        }
        try render(content, size: CGSize(width: 700, height: 500), scale: 1,
                   to: dir.appendingPathComponent("09-comparison-note.png"))

        let note = """
        WarawaraPet art preview (generated by ArtPreviewGeneratorTests)

        All images in this artifact use the PROCEDURAL PLACEHOLDER artwork.
        They demonstrate the sprite pipeline, pose math, and composition 鈥?        they make no claim of fidelity to the film design.

        Reference material:
        - Official film page: https://www.ghibli.jp/works/kimitachi/
        - Official stills: https://www.ghibli.jp/gallery/kimitachiNNN.jpg
        - See docs/art/WARAWARA_REFERENCE_SPEC.md for the review checklist.

        No film frames or thumbnails are included in this artifact.
        """
        try writeNote(note, to: dir.appendingPathComponent("README.txt"))
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
