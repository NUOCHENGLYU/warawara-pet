import AppKit
import SwiftUI
import XCTest
@testable import WarawaraPet

/// Sleep/mouth continuity QA previews: the REAL expression driver model
/// is ticked through idle → sleepy → sleeping → clicked → idle, then the
/// REAL layered character renderer draws sheets at each key moment plus
/// a full-breath strip during stable sleep, so the mouth size and body
/// breath continuity can be inspected visually.
@MainActor
final class SleepMouthPreviewGeneratorTests: XCTestCase {
    func testGenerateSleepMouthPreviews() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["SLEEP_PREVIEW_OUT"] else {
            throw XCTSkip("SLEEP_PREVIEW_OUT not set; skipping preview generation")
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

        let model = WarawaraExpressionDriverModel()
        let start = Date(timeIntervalSinceReferenceDate: 720_000_000)

        func tick(_ t: TimeInterval, _ state: PetState) {
            model.tick(at: start.addingTimeInterval(t), inputs: WarawaraExpressionInputs(state: state))
        }

        // 1) idle baseline, then drift into sleepy.
        for i in 0..<120 { tick(Double(i) / 60.0, .idle) }
        // 2) sleepy entry + hold.
        for i in 0..<240 { tick(2 + Double(i) / 60.0, .sleepy) }
        let sleepyParams = model.animatorParameters
        try renderSheet(name: "200-enter-sleepy", params: sleepyParams, caption: "sleepy (drowsy \(String(format: "%.2f", sleepyParams.drowsiness)))",
                        rig: rig, rigLoader: rigLoader, size: mainSize, to: outputDir)

        // 3) sleeping entry.
        for i in 0..<180 { tick(6 + Double(i) / 60.0, .sleeping) }
        let sleepingEntry = model.animatorParameters
        try renderSheet(name: "201-enter-sleeping", params: sleepingEntry, caption: "sleeping entry (mouthOpen \(String(format: "%.2f", sleepingEntry.mouthOpenAmount)))",
                        rig: rig, rigLoader: rigLoader, size: mainSize, to: outputDir)

        // 4) Stable sleep: 30 s more, then sample ONE FULL breath cycle
        //    (12 frames) for the continuity strip.
        for i in 0..<(30 * 60) { tick(9 + Double(i) / 60.0, .sleeping) }
        var stripFrames: [(String, WarawaraPerformanceParameters)] = []
        var sampledOpenAmounts: [CGFloat] = []
        for step in 0..<12 {
            for i in 0..<4 { tick(39 + Double(step * 4 + i) / 60.0, .sleeping) }
            let params = model.animatorParameters
            sampledOpenAmounts.append(params.mouthOpenAmount)
            stripFrames.append((String(format: "phase %.2f", params.breathPhase), params))
        }
        try renderStrip(name: "202-sleep-breath-strip", frames: stripFrames,
                        rig: rig, rigLoader: rigLoader, size: mainSize, to: outputDir)

        // Real assertion: the sleeping mouth visibly swells and shrinks
        // across one breath cycle (continuity, not two discrete sizes).
        let amplitude = (sampledOpenAmounts.max() ?? 0) - (sampledOpenAmounts.min() ?? 0)
        XCTAssertGreaterThan(amplitude, 0.05,
            "the sleeping mouth must visibly breathe across a cycle (amplitude \(amplitude))")

        // 5) Wake: click interrupts sleep, then the pet returns to idle.
        for i in 0..<60 { tick(45 + Double(i) / 60.0, .clicked) }
        let clickedParams = model.animatorParameters
        try renderSheet(name: "203-clicked-wake", params: clickedParams, caption: "clicked (waking)",
                        rig: rig, rigLoader: rigLoader, size: mainSize, to: outputDir)
        for i in 0..<120 { tick(46 + Double(i) / 60.0, .idle) }
        let awakeParams = model.animatorParameters
        try renderSheet(name: "204-awake-idle", params: awakeParams, caption: "idle after wake",
                        rig: rig, rigLoader: rigLoader, size: mainSize, to: outputDir)

        for name in ["200-enter-sleepy.png", "201-enter-sleeping.png",
                     "202-sleep-breath-strip.png", "203-clicked-wake.png", "204-awake-idle.png"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.appendingPathComponent(name).path),
                          "missing sleep preview \(name)")
        }
    }

    // MARK: - Rendering

    private func character(_ params: WarawaraPerformanceParameters,
                           rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader,
                           size: CGSize) -> some View {
        WarawaraLayeredCharacterView(
            rig: rig, rigLoader: rigLoader,
            parameters: params, renderSize: size
        )
        .frame(width: size.width, height: size.height)
    }

    private func renderSheet(name: String, params: WarawaraPerformanceParameters,
                             caption: String, rig: WarawaraRigManifest,
                             rigLoader: WarawaraRigLoader, size: CGSize, to dir: URL) throws {
        let content = ZStack {
            Color(white: 0.92).ignoresSafeArea()
            VStack(spacing: 6) {
                Text("\(name) — \(caption)").font(.system(size: 12, weight: .semibold))
                character(params, rig: rig, rigLoader: rigLoader, size: size)
            }
        }
        try render(content, size: CGSize(width: 560, height: 520), scale: 1,
                   to: dir.appendingPathComponent("\(name).png"))
    }

    private func renderStrip(name: String, frames: [(String, WarawaraPerformanceParameters)],
                             rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader,
                             size: CGSize, to dir: URL) throws {
        let content = ZStack {
            Color(white: 0.92).ignoresSafeArea()
            VStack(spacing: 2) {
                Text("\(name) — one full sleeping breath cycle (mouth + body)").font(.system(size: 11, weight: .semibold))
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                        VStack(spacing: 0) {
                            Text(frame.0).font(.system(size: 7))
                            character(frame.1, rig: rig, rigLoader: rigLoader, size: size)
                                .frame(width: 120, height: 120)
                        }
                    }
                }
            }
        }
        try render(content, size: CGSize(width: CGFloat(frames.count) * 124 + 8, height: 240), scale: 1,
                   to: dir.appendingPathComponent("\(name).png"))
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
