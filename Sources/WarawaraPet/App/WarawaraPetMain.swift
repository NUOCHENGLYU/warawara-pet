import AppKit
import Darwin
import Foundation

@main
enum WarawaraPetMain {
    private static let appDelegate = AppDelegate()

    static func main() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--no-2d5-turn") {
            // Stable fallback: disable the experimental 2.5D body warp,
            // keeping the accepted gaze/face behavior.
            WarawaraTurnGeometry.turnDisabled = true
        }
        if arguments.contains("--verify-gift-assets") {
            // Headless check against the packaged .app: all Phase 7 gift
            // artwork (wearables + meteor + birthday) must resolve and
            // match their manifest hashes.
            let store = GiftAssetStore.shared
            store.reset()
            let required = store.verifyAllRequiredAssets()
            let hashes = store.verifySHA256()
            let splits = store.verifySplitIntegrity()
            let birthday = BirthdayAssetStore.shared
            birthday.reset()
            let birthdayRequired = birthday.verifyAllRequiredAssets()
            let birthdayHashes = birthday.verifySHA256()
            if required.ok && hashes.ok && splits.ok && birthdayRequired.ok && birthdayHashes.ok {
                print("GIFT_ASSETS_OK assets=\(GiftAssetStore.requiredFileNames.count) splits=ok birthday=ok")
                exit(0)
            }
            print("GIFT_ASSETS_FAIL required=[\(required.details)] hashes=[\(hashes.details)] splits=[\(splits.details)] birthday=[\(birthdayRequired.details)/\(birthdayHashes.details)]")
            exit(1)
        }
        if let flagIndex = arguments.firstIndex(of: "--verify-birthday") {
            // Headless check used by CI against the packaged .app:
            // verifies every v2 birthday asset and the letter text are
            // loadable from the real bundled resources.
            let store = BirthdayAssetStore.shared
            store.reset()
            let required = store.verifyAllRequiredAssets()
            let hashes = store.verifySHA256()
            let letterLength = store.letterText()?.count ?? -1
            if required.ok && hashes.ok && letterLength > 0 {
                print("BIRTHDAY_OK assets=\(BirthdayAssetStore.requiredFileNames.count) letterChars=\(letterLength)")
                exit(0)
            }
            print("BIRTHDAY_FAIL required=[\(required.details)] hashes=[\(hashes.details)] letterChars=\(letterLength)")
            exit(1)
        }
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
        if arguments.contains("--replay-birthday") {
            // Manual replay: runs the genuine sequence on any date and
            // never consumes annual eligibility.
            appDelegate.requestBirthdayReplay()
        }
        if arguments.contains("--replay-meteor") {
            EventDiagnostics.smokeMode = false
            appDelegate.requestMeteorReplay()
        }
        if arguments.contains("--replay-smoke") {
            // Packaged-app CI smoke: replay the meteor and exit after the
            // scene completes.
            EventDiagnostics.smokeMode = true
            appDelegate.requestMeteorReplay()
        }
        if arguments.contains("--debug-wear") {
            let kind = arguments.firstIndex(of: "--debug-wear")
                .flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil } ?? ""
            if let wearable = WearableKind(debugArgument: kind) {
                appDelegate.requestWearableDebug(wearable)
            } else {
                print("WEARABLE_DEBUG_UNKNOWN id=\(kind)")
                print("valid: birthday-hat | christmas-hat | headphones | red-scarf")
                exit(2)
            }
        }
        if arguments.contains("--help-events") {
            print(EventCommandLine.usage)
            exit(0)
        }
        if arguments.contains("--show-letter") {
            appDelegate.requestShowLetter()
        }
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
