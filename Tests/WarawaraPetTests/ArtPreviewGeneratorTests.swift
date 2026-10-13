import AppKit
import SwiftUI
import XCTest
@testable import WarawaraPet

/// Offline artwork preview generator. When ART_PREVIEW_OUT is set (CI),
/// renders inspectable PNG contact sheets into that directory using the
/// real placeholder views and pose math. All output uses the procedural
/// PLACEHOLDER artwork — it is not a fidelity claim.
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

    // MARK: - Phase 5A layered rig previews (development verification)

    /// Renders representative layered-rig state sheets (idle, curious,
    /// sleepy, sleeping, pressed) using the layered renderer with
    /// mapper-produced parameters. The eye/mouth layers here are
    /// PROCEDURAL PREVIEW SCAFFOLDING generated inside this test — they
    /// are never shipped and are replaced by user-provided rig art.
    func testGenerateRigStatePreviews() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["ART_PREVIEW_OUT"] else {
            throw XCTSkip("ART_PREVIEW_OUT not set; skipping preview generation")
        }
        let outputDir = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let rigDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RigPreview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rigDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rigDir) }

        let rig = try buildPreviewRig(at: rigDir)
        try JSONEncoder().encode(rig).write(to: rigDir.appendingPathComponent("manifest.json"))
        let rigLoader = WarawaraRigLoader()
        guard rigLoader.loadManifest(from: rigDir) else {
            throw XCTSkip("could not build preview rig: \(rigLoader.lastErrorDescription ?? "")")
        }
        guard let renderSize = WarawaraExpressionDriver.renderSize(
            rig: rig, targetBodyHeight: PetMetrics.blobHeight
        ) else {
            throw XCTSkip("preview rig has no render size")
        }

        let states: [(String, WarawaraExpressionContext)] = [
            ("idle", WarawaraExpressionContext(
                inputs: WarawaraExpressionInputs(state: .idle), breathPhase: 0.25)),
            ("curious", WarawaraExpressionContext(
                inputs: WarawaraExpressionInputs(state: .curious, gaze: CGVector(dx: 0.7, dy: 0.2)),
                breathPhase: 0.1)),
            ("sleepy", WarawaraExpressionContext(
                inputs: WarawaraExpressionInputs(state: .sleepy), breathPhase: 0.5)),
            ("sleeping", WarawaraExpressionContext(
                inputs: WarawaraExpressionInputs(state: .sleeping), breathPhase: 0.75)),
            ("pressed", WarawaraExpressionContext(
                inputs: WarawaraExpressionInputs(state: .clicked), breathPhase: 0.25))
        ]

        for (index, (name, context)) in states.enumerated() {
            let parameters = WarawaraExpressionMapper.targetParameters(for: context)
            let content = ZStack {
                CheckerboardBackground()
                WarawaraLayeredCharacterView(
                    rig: rig,
                    rigLoader: rigLoader,
                    parameters: parameters,
                    renderSize: renderSize
                )
                VStack {
                    HStack {
                        Text("rig preview: \(name)")
                            .font(.headline)
                            .padding(4)
                            .background(Color.white.opacity(0.8))
                        Spacer()
                    }
                    Spacer()
                }
            }
            let sheetName = "\(18 + index)-rig-\(name).png"
            try render(content, size: mainCanvas, scale: 2,
                       to: outputDir.appendingPathComponent(sheetName))
        }

        for name in ["18-rig-idle.png", "19-rig-curious.png", "20-rig-sleepy.png",
                     "21-rig-sleeping.png", "22-rig-pressed.png"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: outputDir.appendingPathComponent(name).path),
                "missing rig preview \(name)"
            )
        }
    }

    /// Builds an in-memory rig: the committed neutral artwork as the body
    /// layer plus procedurally drawn eye/mouth layers (PREVIEW ONLY —
    /// clearly not shipped artwork, replaced by the user's rig assets).
    @MainActor
    private func buildPreviewRig(at dir: URL) throws -> WarawaraRigManifest {
        let repoPNG = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/WarawaraPet/Resources/Sprites/warawara_neutral.png")
        guard FileManager.default.fileExists(atPath: repoPNG.path) else {
            throw XCTSkip("committed neutral artwork missing; cannot build preview rig")
        }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("body"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: repoPNG, to: dir.appendingPathComponent("body/base.png")
        )
        try writePreviewEyesLayer(at: dir.appendingPathComponent("eyes"))
        try writePreviewMouthLayer(at: dir.appendingPathComponent("mouth"))

        return WarawaraRigManifest(
            version: 1,
            canvas: CGSize(width: 1024, height: 1024),
            anchor: CGPoint(x: 0.5, y: 0.5),
            bodyBounds: CGRect(x: 0.10, y: 0.09, width: 0.80, height: 0.82),
            layers: [
                "body": .init(
                    kind: .body,
                    images: ["base": "body/base.png"],
                    anchor: CGPoint(x: 0.5, y: 0.5),
                    gazeRange: nil
                ),
                "eyes": .init(
                    kind: .eyes,
                    images: ["open": "eyes/open.png", "closed": "eyes/closed.png"],
                    anchor: CGPoint(x: 0.5, y: 0.41),
                    gazeRange: CGSize(width: 0.06, height: 0.03)
                ),
                "mouth": .init(
                    kind: .mouth,
                    images: [
                        "soft": "mouth/soft.png",
                        "neutral": "mouth/neutral.png",
                        "relaxed": "mouth/relaxed.png",
                        "open": "mouth/open.png",
                        "pressed": "mouth/pressed.png",
                        "sleepy": "mouth/sleepy.png"
                    ],
                    anchor: CGPoint(x: 0.5, y: 0.50),
                    gazeRange: nil
                )
            ],
            optionalLayers: ["limbs"]
        )
    }

    /// Two dark eye dots + closed-eye arcs, drawn on transparent 256x256
    /// canvases so the rig renderer has real layers to compose. PREVIEW
    /// SCAFFOLDING ONLY.
    @MainActor
    private func writePreviewEyesLayer(at dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let size = 256
        let open = try previewBitmap(size: size) { ctx in
            let eyeRadius = CGFloat(20)
            let centerY = CGFloat(size) * 0.59 // 1 - 0.41 anchor
            let gap = CGFloat(44)
            for x in [CGFloat(size) / 2 - gap, CGFloat(size) / 2 + gap] {
                NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
                NSBezierPath(
                    ovalIn: NSRect(x: x - eyeRadius, y: centerY - eyeRadius,
                                   width: eyeRadius * 2, height: eyeRadius * 2)
                ).fill()
            }
        }
        let closed = try previewBitmap(size: size) { ctx in
            let width = CGFloat(44)
            let centerY = CGFloat(size) * 0.59
            let gap = CGFloat(44)
            NSColor(calibratedWhite: 0.12, alpha: 1).setStroke()
            let pen = NSBezierPath()
            pen.lineWidth = 7
            pen.lineCapStyle = .round
            for x in [CGFloat(size) / 2 - gap, CGFloat(size) / 2 + gap] {
                pen.appendArc(
                    withCenter: NSPoint(x: x, y: centerY - 4),
                    radius: width / 2, startAngle: 200, endAngle: 340
                )
            }
            pen.stroke()
        }
        try open.write(to: dir.appendingPathComponent("open.png"))
        try closed.write(to: dir.appendingPathComponent("closed.png"))
    }

    /// Simple mouth style shapes. PREVIEW SCAFFOLDING ONLY.
    @MainActor
    private func writePreviewMouthLayer(at dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let size = 256
        let centerX = CGFloat(size) / 2
        let centerY = CGFloat(size) * 0.5 // 1 - 0.50 anchor
        let color = NSColor(calibratedWhite: 0.12, alpha: 1)

        let styles: [(String, (NSGraphicsContext) -> Void)] = [
            ("soft", { ctx in
                color.setStroke()
                let path = NSBezierPath()
                path.lineWidth = 8
                path.lineCapStyle = .round
                path.move(to: NSPoint(x: centerX - 34, y: centerY - 2))
                path.curve(to: NSPoint(x: centerX + 34, y: centerY - 2),
                           controlPoint1: NSPoint(x: centerX - 12, y: centerY + 14),
                           controlPoint2: NSPoint(x: centerX + 12, y: centerY + 14))
                path.stroke()
            }),
            ("neutral", { ctx in
                color.setStroke()
                let path = NSBezierPath()
                path.lineWidth = 8
                path.lineCapStyle = .round
                path.move(to: NSPoint(x: centerX - 26, y: centerY))
                path.line(to: NSPoint(x: centerX + 26, y: centerY))
                path.stroke()
            }),
            ("relaxed", { ctx in
                color.setFill()
                NSBezierPath(
                    ovalIn: NSRect(x: centerX - 20, y: centerY - 10, width: 40, height: 18)
                ).fill()
            }),
            ("open", { ctx in
                color.setFill()
                NSBezierPath(
                    ovalIn: NSRect(x: centerX - 24, y: centerY - 18, width: 48, height: 34)
                ).fill()
            }),
            ("pressed", { ctx in
                color.setStroke()
                let path = NSBezierPath()
                path.lineWidth = 9
                path.lineCapStyle = .round
                path.move(to: NSPoint(x: centerX - 30, y: centerY))
                path.line(to: NSPoint(x: centerX + 30, y: centerY))
                path.stroke()
            }),
            ("sleepy", { ctx in
                color.setFill()
                NSBezierPath(
                    ovalIn: NSRect(x: centerX - 10, y: centerY - 8, width: 20, height: 16)
                ).fill()
            })
        ]
        for (name, draw) in styles {
            let image = try previewBitmap(size: size, draw: draw)
            try image.write(to: dir.appendingPathComponent("\(name).png"))
        }
    }

    @MainActor
    private func previewBitmap(
        size: Int,
        draw: (NSGraphicsContext) -> Void
    ) throws -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: size * 4,
            bitsPerPixel: 32
        ) else { throw NSError(domain: "preview", code: 1) }
        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            throw NSError(domain: "preview", code: 2)
        }
        NSGraphicsContext.current = context
        draw(context)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "preview", code: 3)
        }
        return png
    }

    @MainActor
    private func renderComparisonNote(to dir: URL) throws {        let content = ZStack {
            CheckerboardBackground()
            VStack(spacing: 14) {
                placeholderMain
                Text("CANDIDATE — awaiting visual approval")
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
        They demonstrate the sprite pipeline, pose math, and composition —
        they make no claim of fidelity to the film design.

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
