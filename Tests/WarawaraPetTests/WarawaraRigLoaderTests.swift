import AppKit
import XCTest
@testable import WarawaraPet

/// Rig manifest decoding/validation, loader fallback behavior, and the
/// rendering resolution order (rig -> sprite -> placeholder).
final class WarawaraRigLoaderTests: XCTestCase {
    private var baseURL: URL!

    override func setUp() {
        super.setUp()
        baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WarawaraRigLoaderTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: baseURL)
        baseURL = nil
        super.tearDown()
    }

    private func writeTestPNG(named name: String) throws {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 16,
            pixelsHigh: 16,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 64,
            bitsPerPixel: 32
        )!
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "test", code: 1)
        }
        try data.write(to: baseURL.appendingPathComponent(name))
    }

    private func makeValidRig() -> WarawaraRigManifest {
        WarawaraRigManifest(
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
                        "open": "mouth/open.png",
                        "sleepy": "mouth/sleepy.png",
                        "pressed": "mouth/pressed.png",
                        "relaxed": "mouth/relaxed.png",
                        "neutral": "mouth/neutral.png"
                    ],
                    anchor: CGPoint(x: 0.5, y: 0.50),
                    gazeRange: nil
                )
            ],
            optionalLayers: ["limbs"]
        )
    }

    private func writeRigManifest(_ rig: WarawaraRigManifest) throws {
        let data = try JSONEncoder().encode(rig)
        try data.write(to: baseURL.appendingPathComponent("manifest.json"))
    }

    // MARK: - Manifest format

    func testHandwrittenRigManifestWithCGArrayFormatDecodes() throws {
        let json = """
        {"version":1,"canvas":[1024,1024],"anchor":[0.5,0.5],\
        "bodyBounds":[[0.10,0.09],[0.80,0.82]],\
        "layers":{"body":{"kind":"body","images":{"base":"body/base.png"},\
        "anchor":[0.5,0.5]},"eyes":{"kind":"eyes",\
        "images":{"open":"eyes/open.png","closed":"eyes/closed.png"},\
        "anchor":[0.5,0.41],"gazeRange":[0.06,0.03]},\
        "mouth":{"kind":"mouth","images":{"soft":"mouth/soft.png"},\
        "anchor":[0.5,0.5]}},"optionalLayers":["limbs"]}
        """
        let decoded = try JSONDecoder().decode(WarawaraRigManifest.self, from: Data(json.utf8))
        XCTAssertNotNil(WarawaraRigManifest.validated(decoded))
        XCTAssertEqual(decoded.bodyBounds.width, 0.80, accuracy: 0.001)
        XCTAssertEqual(decoded.eyesLayer?.gazeRange?.width ?? 0, 0.06, accuracy: 0.001)
    }

    func testInvalidRigManifestsAreRejected() {
        var rig = makeValidRig()
        rig.version = 2
        XCTAssertNil(WarawaraRigManifest.validated(rig))

        rig = makeValidRig()
        rig.anchor = CGPoint(x: 1.5, y: 0.5)
        XCTAssertNil(WarawaraRigManifest.validated(rig))

        rig = makeValidRig()
        var body = rig.layers["body"]!
        body.anchor = CGPoint(x: -0.2, y: 0.5)
        rig.layers["body"] = body
        XCTAssertNil(WarawaraRigManifest.validated(rig))

        rig = makeValidRig()
        rig.layers.removeValue(forKey: "body")
        XCTAssertNil(WarawaraRigManifest.validated(rig))

        rig = makeValidRig()
        rig.layers["eyes"] = nil
        rig.layers["eyesKeyMismatch"] = .init(
            kind: .eyes,
            images: ["open": "eyes/open.png"],
            anchor: CGPoint(x: 0.5, y: 0.5),
            gazeRange: nil
        )
        XCTAssertNil(WarawaraRigManifest.validated(rig), "layer key must equal kind")
    }

    // MARK: - Loader + resolution order

    func testRigLoadsAndLayeredRenderingIsPreferred() throws {
        try writeRigManifest(makeValidRig())
        try writeTestPNG(named: "base.png")

        let rigLoader = WarawaraRigLoader()
        XCTAssertTrue(rigLoader.loadDefaultRig(candidates: [baseURL]))
        XCTAssertTrue(rigLoader.hasRig)
        XCTAssertEqual(rigLoader.loadedBaseURL, baseURL)
        XCTAssertNil(rigLoader.lastErrorDescription)

        // Even with a loaded sprite pipeline, the rig wins.
        let spriteLoader = WarawaraSpriteLoader()
        let content = WarawaraCharacterContent.resolve(
            visualState: .idle,
            loader: spriteLoader,
            rigLoader: rigLoader,
            baseURL: baseURL,
            placeholderSizeClass: .main,
            scale: 1
        )
        guard case .layered(let rig, let loader, let renderSize) = content else {
            XCTFail("expected layered rendering when rig is present")
            return
        }
        XCTAssertEqual(rig.version, 1)
        XCTAssertTrue(loader === rigLoader)
        XCTAssertEqual(renderSize.height, 143.9, accuracy: 1.0)
    }

    func testMissingRigLogsAndFallsBackToSpritePipeline() throws {
        let rigLoader = WarawaraRigLoader()
        let missing = baseURL.appendingPathComponent("no-rig")
        XCTAssertFalse(rigLoader.loadDefaultRig(candidates: [missing]))
        XCTAssertTrue(rigLoader.didAttemptDefaultLoad)
        XCTAssertNotNil(rigLoader.lastErrorDescription)
        XCTAssertTrue(
            rigLoader.lastErrorDescription?.contains("no-rig") == true,
            "fallback must record the attempted path: \(rigLoader.lastErrorDescription ?? "nil")"
        )

        // Sprite pipeline with assets still resolves to .sprite.
        try writeTestPNG(named: "warawara_neutral.png")
        let manifest = WarawaraSpriteManifest(
            version: 1,
            layout: .init(
                canvas: CGSize(width: 1024, height: 1024),
                anchor: CGPoint(x: 0.5, y: 0.5),
                bodyBounds: CGRect(x: 0.10, y: 0.09, width: 0.80, height: 0.82)
            ),
            animations: ["idle": .init(frames: ["warawara_neutral.png"], frameDuration: 0.6, loop: true)]
        )
        try JSONEncoder().encode(manifest).write(to: baseURL.appendingPathComponent("sprites.json"))

        let spriteLoader = WarawaraSpriteLoader()
        XCTAssertTrue(spriteLoader.loadManifest(from: baseURL))
        let content = WarawaraCharacterContent.resolve(
            visualState: .idle,
            loader: spriteLoader,
            rigLoader: rigLoader,
            baseURL: baseURL,
            placeholderSizeClass: .main,
            scale: 1
        )
        guard case .sprite = content else {
            XCTFail("expected sprite fallback when rig is absent")
            return
        }
    }

    func testRigImageResolvesFlatBasenameLikeSpritePipeline() throws {
        try writeRigManifest(makeValidRig())
        try writeTestPNG(named: "base.png") // flat, as SwiftPM flattens

        let rigLoader = WarawaraRigLoader()
        XCTAssertTrue(rigLoader.loadManifest(from: baseURL))
        let body = rigLoader.rig?.bodyLayer
        XCTAssertNotNil(body)
        XCTAssertNotNil(body.flatMap { rigLoader.image(forLayer: $0, role: "base") })
    }

    func testRigCandidateURLsIncludeRigSubdirectory() {
        let spriteRoot = URL(fileURLWithPath: "/tmp/Resources")
        let rigCandidates = WarawaraRigLoader.candidateBaseURLs(spriteCandidates: [spriteRoot])
        XCTAssertEqual(rigCandidates, [spriteRoot.appendingPathComponent("Assets/WarawaraRig")])
    }

    func testCorruptRigManifestRecordsDecodeError() throws {
        try Data("[broken".utf8).write(to: baseURL.appendingPathComponent("manifest.json"))
        let rigLoader = WarawaraRigLoader()
        XCTAssertFalse(rigLoader.loadManifest(from: baseURL))
        XCTAssertTrue(
            rigLoader.lastErrorDescription?.contains("decode error") == true,
            "expected decode error, got: \(rigLoader.lastErrorDescription ?? "nil")"
        )
        XCTAssertFalse(rigLoader.hasRig)
    }

    func testRigLoaderResetClearsState() throws {
        try writeRigManifest(makeValidRig())
        let rigLoader = WarawaraRigLoader()
        XCTAssertTrue(rigLoader.loadManifest(from: baseURL))
        rigLoader.reset()
        XCTAssertFalse(rigLoader.hasRig)
        XCTAssertNil(rigLoader.loadedBaseURL)
        XCTAssertNil(rigLoader.lastErrorDescription)
    }
}
