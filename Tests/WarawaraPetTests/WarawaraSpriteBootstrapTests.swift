import AppKit
import XCTest
@testable import WarawaraPet

/// Tests for the app's real sprite startup path (the same call
/// `AppDelegate.applicationDidFinishLaunching` makes) and for the actual
/// rendering decision `WarawaraCharacterView` uses. These are the paths
/// that were previously untested and allowed the app to silently render
/// the procedural placeholder forever.
final class WarawaraSpriteBootstrapTests: XCTestCase {
    private var baseURL: URL!

    override func setUp() {
        super.setUp()
        baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WarawaraSpriteBootstrapTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: baseURL)
        baseURL = nil
        super.tearDown()
    }

    // MARK: - Fixtures (bundle-like layout: manifest + flat PNG)

    private func writeTestPNG(named name: String) throws {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 8,
            pixelsHigh: 8,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 32,
            bitsPerPixel: 32
        )!
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "test", code: 1)
        }
        try data.write(to: baseURL.appendingPathComponent(name))
    }

    private func writeManifest() throws {
        let manifest = WarawaraSpriteManifest(
            version: 1,
            layout: .init(
                canvas: CGSize(width: 1024, height: 1024),
                anchor: CGPoint(x: 0.5, y: 0.5),
                bodyBounds: CGRect(x: 0.10, y: 0.09, width: 0.80, height: 0.82)
            ),
            animations: [
                "idle": .init(frames: ["warawara_neutral.png"], frameDuration: 0.6, loop: true),
                "hop": .init(frames: ["warawara_neutral.png"], frameDuration: 0.1, loop: false),
                "float": .init(frames: ["warawara_neutral.png"], frameDuration: 0.15, loop: true),
                "curious": .init(frames: ["warawara_neutral.png"], frameDuration: 0.1, loop: false),
                "clicked": .init(frames: ["warawara_neutral.png"], frameDuration: 0.1, loop: false),
                "dragged": .init(frames: ["warawara_neutral.png"], frameDuration: 0.1, loop: false),
                "settling": .init(frames: ["warawara_neutral.png"], frameDuration: 0.1, loop: false),
                "sleepy": .init(frames: ["warawara_neutral.png"], frameDuration: 0.1, loop: false),
                "sleeping": .init(frames: ["warawara_neutral.png"], frameDuration: 0.1, loop: false),
                "wake": .init(frames: ["warawara_neutral.png"], frameDuration: 0.1, loop: false)
            ]
        )
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: baseURL.appendingPathComponent("sprites.json"))
    }

    private func makeLoader() -> WarawaraSpriteLoader {
        WarawaraSpriteLoader()
    }

    // MARK: - Startup bootstrap

    func testStartupBootstrapLoadsManifestFromBundleLikeDirectory() throws {
        try writeManifest()
        try writeTestPNG(named: "warawara_neutral.png")

        let loader = makeLoader()
        XCTAssertTrue(loader.loadDefaultResources(candidateBaseURLs: [baseURL]))
        XCTAssertNotNil(loader.manifest)
        XCTAssertTrue(loader.hasSprites)
        XCTAssertNil(loader.lastErrorDescription)
        XCTAssertEqual(loader.attemptedBaseURLs, [baseURL])
        XCTAssertEqual(loader.loadedBaseURL, baseURL)
    }

    func testStartupBootstrapRecordsAttemptedPathsAndReasonOnFailure() {
        let missing = baseURL.appendingPathComponent("no-such-bundle")
        let loader = makeLoader()
        XCTAssertFalse(loader.loadDefaultResources(candidateBaseURLs: [missing]))
        XCTAssertFalse(loader.hasSprites)
        XCTAssertNotNil(loader.lastErrorDescription)
        XCTAssertTrue(
            loader.lastErrorDescription?.contains(missing.path) == true,
            "failure must include the attempted path, got: \(loader.lastErrorDescription ?? "nil")"
        )
        XCTAssertEqual(loader.attemptedBaseURLs, [missing])
    }

    func testStartupBootstrapIsIdempotent() throws {
        try writeManifest()
        let loader = makeLoader()
        XCTAssertTrue(loader.loadDefaultResources(candidateBaseURLs: [baseURL]))
        XCTAssertTrue(loader.loadDefaultResources(candidateBaseURLs: [baseURL]))
        XCTAssertTrue(loader.hasSprites)
    }

    func testStartupBootstrapClearsPreviousErrorOnSuccess() throws {
        let loader = makeLoader()
        XCTAssertFalse(loader.loadDefaultResources(candidateBaseURLs: [baseURL.appendingPathComponent("missing")]))
        XCTAssertNotNil(loader.lastErrorDescription)

        try writeManifest()
        try writeTestPNG(named: "warawara_neutral.png")
        XCTAssertTrue(loader.loadDefaultResources(candidateBaseURLs: [baseURL]))
        XCTAssertNil(loader.lastErrorDescription)
    }

    func testAppCandidateURLsLoadInTestEnvironmentOrSkip() {
        // Exercises the real app-side URL list (Bundle.module etc.). In
        // the SwiftPM test environment this is the same bundle the
        // packaged app resolves; skip only where no bundle exists.
        let candidates = WarawaraSpriteLoader.candidateBaseURLs()
        let anyManifest = candidates.contains {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("sprites.json").path)
        }
        guard anyManifest else {
            throw XCTSkip("no sprite bundle available in this environment")
        }
        let loader = makeLoader()
        let loaded = loader.loadDefaultResources()
        guard loaded else {
            // Documented failure path; failing here means the release app
            // would fall back to the placeholder.
            XCTFail("app-style bootstrap failed: \(loader.lastErrorDescription ?? "unknown")")
            return
        }
        XCTAssertNotNil(loader.manifest)
        XCTAssertNil(loader.lastErrorDescription)
    }

    // MARK: - Real rendering decision (WarawaraCharacterView path)

    func testEveryPetStateResolvesToSpriteWithLoadedAssets() throws {
        try writeManifest()
        try writeTestPNG(named: "warawara_neutral.png")
        let loader = makeLoader()
        XCTAssertTrue(loader.loadDefaultResources(candidateBaseURLs: [baseURL]))

        for petState in [PetState.idle, .hop, .float, .curious, .clicked,
                         .dragged, .settling, .sleepy, .sleeping] {
            let content = WarawaraCharacterContent.resolve(
                visualState: WarawaraVisualState.state(for: petState),
                loader: loader,
                baseURL: baseURL,
                placeholderSizeClass: .main,
                scale: 1
            )
            guard case .sprite(let image, let animation, let renderSize, let anchor) = content else {
                XCTFail("state \(petState) resolved to placeholder")
                continue
            }
            XCTAssertNotNil(image)
            XCTAssertFalse(animation.frames.isEmpty)
            XCTAssertEqual(renderSize.height, 143.9, accuracy: 1.0)
            XCTAssertEqual(anchor.x, 0.5, accuracy: 0.01)
        }
    }

    func testCompanionResolvesToSpriteWithCompanionSizing() throws {
        try writeManifest()
        try writeTestPNG(named: "warawara_neutral.png")
        let loader = makeLoader()
        XCTAssertTrue(loader.loadDefaultResources(candidateBaseURLs: [baseURL]))

        let content = WarawaraCharacterContent.resolve(
            visualState: .idle,
            loader: loader,
            baseURL: baseURL,
            placeholderSizeClass: .companion,
            scale: 1
        )
        guard case .sprite(_, _, let renderSize, _) = content else {
            XCTFail("companion resolved to placeholder")
            return
        }
        // 74 pt companion body height on the same canvas -> ~90 pt square.
        XCTAssertEqual(renderSize.height, 90.3, accuracy: 1.0)
    }

    func testMissingManifestResolvesToPlaceholderWithError() throws {
        let loader = makeLoader()
        let missing = baseURL.appendingPathComponent("empty")
        XCTAssertFalse(loader.loadDefaultResources(candidateBaseURLs: [missing]))
        XCTAssertNotNil(loader.lastErrorDescription)

        let content = WarawaraCharacterContent.resolve(
            visualState: .idle,
            loader: loader,
            baseURL: missing,
            placeholderSizeClass: .main,
            scale: 1
        )
        guard case .placeholder = content else {
            XCTFail("expected placeholder")
            return
        }
    }

    func testCorruptManifestResolvesToPlaceholderAndRecordsDecodeError() throws {
        try Data("[not json".utf8).write(to: baseURL.appendingPathComponent("sprites.json"))
        let loader = makeLoader()
        XCTAssertFalse(loader.loadManifest(from: baseURL))
        XCTAssertTrue(
            loader.lastErrorDescription?.contains("decode error") == true,
            "expected decode error, got: \(loader.lastErrorDescription ?? "nil")"
        )

        let content = WarawaraCharacterContent.resolve(
            visualState: .idle,
            loader: loader,
            baseURL: baseURL,
            placeholderSizeClass: .main,
            scale: 1
        )
        guard case .placeholder = content else {
            XCTFail("expected placeholder for corrupt manifest")
            return
        }
    }

    func testMissingImageFileResolvesToPlaceholderAndRecordsPath() throws {
        try writeManifest() // references warawara_neutral.png, not written
        let loader = makeLoader()
        XCTAssertTrue(loader.loadManifest(from: baseURL))

        let content = WarawaraCharacterContent.resolve(
            visualState: .idle,
            loader: loader,
            baseURL: baseURL,
            placeholderSizeClass: .main,
            scale: 1
        )
        guard case .placeholder = content else {
            XCTFail("expected placeholder for missing image")
            return
        }
        XCTAssertNotNil(loader.lastErrorDescription)
        XCTAssertTrue(
            loader.lastErrorDescription?.contains("warawara_neutral.png") == true,
            "error must name the missing frame, got: \(loader.lastErrorDescription ?? "nil")"
        )
    }
}
