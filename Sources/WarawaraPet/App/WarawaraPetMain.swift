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
            if loaded {
                let animationCount = loader.manifest?.animations.count ?? 0
                let basePath = loader.loadedBaseURL?.path ?? "unknown"
                print("SPRITES_OK animations=\(animationCount) base=\(basePath)")
                exit(0)
            }
            print("SPRITES_FAIL \(loader.lastErrorDescription ?? "unknown error")")
            exit(1)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = appDelegate
        app.run()
    }
}
