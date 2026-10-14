import AppKit
import Darwin
import Foundation

@main
enum WarawaraPetMain {
    private static let appDelegate = AppDelegate()

    static func main() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--verify-sprites") {
            // Headless self-check used by CI against the packaged .app:
            // runs the real startup loader against the real bundled
            // resources and reports the result. No window is created.
            let loader = WarawaraSpriteLoader.shared
            let loaded = loader.loadDefaultResources()
            let rigLoaded = WarawaraRigLoader.shared.loadDefaultRig()
            if loaded {
                let animationCount = loader.manifest?.animations.count ?? 0
                let basePath = loader.loadedBaseURL?.path ?? "unknown"
                print("SPRITES_OK animations=\(animationCount) base=\(basePath) rig=\(rigLoaded ? "loaded" : "absent")")
                exit(0)
            }
            print("SPRITES_FAIL \(loader.lastErrorDescription ?? "unknown error")")
            exit(1)
        }
        if let flagIndex = arguments.firstIndex(of: "--diagnose-expression") {
            // Opt-in runtime diagnostics: drives the PRODUCTION expression
            // model (same mapper, animator, blink waveform, compositing
            // math as the live pet) for a few seconds and prints throttled
            // 2 Hz observations. Real-Mac evidence for blink closure and
            // stationary-gaze holding.
            let seconds: Double
            if arguments.count > flagIndex + 1, let value = Double(arguments[flagIndex + 1]) {
                seconds = min(max(value, 1), 120)
            } else {
                seconds = 6
            }
            runExpressionDiagnostics(seconds: seconds)
            exit(0)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = appDelegate
        app.run()
    }

    /// Drives the production expression pipeline headlessly. Inputs: idle
    /// for the first half, then a stationary off-center curious gaze for
    /// the second half — exactly the scenarios the user reported.
    static func runExpressionDiagnostics(seconds: Double) {
        let model = WarawaraExpressionDriverModel()
        let tickInterval = 1.0 / 60.0
        var elapsed: Double = 0
        var tickCount = 0
        var minEffectiveOpenness: CGFloat = 1
        var maxClosedWeight: Double = 0

        print("t=state blink smoothOpen effectiveOpen closedW gazeX gazeY tilt")
        while elapsed < seconds {
            let now = Date()
            let inputs: WarawaraExpressionInputs = elapsed < seconds / 2
                ? WarawaraExpressionInputs(state: .idle)
                : WarawaraExpressionInputs(state: .curious, gaze: CGVector(dx: 0.6, dy: 0.2))
            model.tick(at: now, inputs: inputs)
            let p = model.parameters
            let effective = WarawaraLayeredGeometry.effectiveEyeOpenness(
                base: p.eyeOpenness, blink: p.blinkAmount
            )
            let weights = WarawaraLayeredGeometry.composedEyeWeights(
                openness: effective, focus: 0, press: 0
            )
            minEffectiveOpenness = min(minEffectiveOpenness, effective)
            let closedWeight = weights.lowerIsOpen ? 0 : weights.upperWeight
            maxClosedWeight = max(maxClosedWeight, closedWeight)

            if tickCount % 30 == 0 {
                print(String(
                    format: "%.2f %@ blink=%.2f smoothOpen=%.2f effectiveOpen=%.2f closedW=%.2f gazeX=%.2f gazeY=%.2f tilt=%.3f",
                    elapsed,
                    elapsed < seconds / 2 ? "idle" : "curious",
                    p.blinkAmount, p.eyeOpenness, effective, closedWeight,
                    p.gazeX, p.gazeY, p.bodyTilt
                ))
            }
            tickCount += 1
            elapsed += tickInterval
            Thread.sleep(forTimeInterval: tickInterval)
        }
        print(String(format: "RESULT minEffectiveOpenness=%.2f maxClosedWeight=%.2f", minEffectiveOpenness, maxClosedWeight))
        print(minEffectiveOpenness <= 0.1
            ? "BLINK_VISIBLE_CLOSURE=YES"
            : "BLINK_VISIBLE_CLOSURE=NO")
    }
}
