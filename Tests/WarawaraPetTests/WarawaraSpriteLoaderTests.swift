import AppKit
import XCTest
@testable import WarawaraPet

final class WarawaraSpriteLoaderTests: XCTestCase {
    private var baseURL: URL!

    override func setUp() {
        super.setUp()
        baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WarawaraSpriteLoaderTests-\(UUID().uuidString)")
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
            pixelsWide: 4,
            pixelsHigh: 4,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 16,
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
                canvas: CGSize(width: 200, height: 226),
                anchor: CGPoint(x: 0.5, y: 0.5),
                bodyBounds: CGRect(x: 0.26, y: 0.24, width: 0.48, height: 0.52)
            ),
            animations: [
                "idle": .init(frames: ["idle_00.png"], frameDuration: 0.5, loop: true)
            ]
        )
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: baseURL.appendingPathComponent("sprites.json"))
    }

    func testLoadsValidManifestAndCachesImages() throws {
        try writeTestPNG(named: "idle_00.png")
        try writeManifest()

        let loader = WarawaraSpriteLoader()
        XCTAssertTrue(loader.loadManifest(from: baseURL))
        XCTAssertTrue(loader.hasSprites)
        XCTAssertNotNil(loader.animation(named: "idle"))

        let first = loader.image(forRelativePath: "idle_00.png", baseURL: baseURL)
        let second = loader.image(forRelativePath: "idle_00.png", baseURL: baseURL)
        XCTAssertNotNil(first)
        XCTAssertTrue(first === second, "images must be cached, not re-decoded")
    }

    func testMissingManifestFallsBack() {
        let loader = WarawaraSpriteLoader()
        XCTAssertFalse(loader.loadManifest(from: baseURL))
        XCTAssertFalse(loader.hasSprites)
        XCTAssertNil(loader.animation(named: "idle"))
    }

    func testMissingImageReturnsNil() throws {
        try writeManifest()
        let loader = WarawaraSpriteLoader()
        XCTAssertTrue(loader.loadManifest(from: baseURL))
        XCTAssertNil(loader.image(forRelativePath: "missing.png", baseURL: baseURL))
    }

    func testInvalidManifestFileFallsBack() throws {
        try Data("[not json".utf8).write(to: baseURL.appendingPathComponent("sprites.json"))
        let loader = WarawaraSpriteLoader()
        XCTAssertFalse(loader.loadManifest(from: baseURL))
        XCTAssertNil(loader.manifest)
    }

    func testResetClearsState() throws {
        try writeTestPNG(named: "idle_00.png")
        try writeManifest()
        let loader = WarawaraSpriteLoader()
        XCTAssertTrue(loader.loadManifest(from: baseURL))
        _ = loader.image(forRelativePath: "idle_00.png", baseURL: baseURL)
        loader.reset()
        XCTAssertFalse(loader.hasSprites)
        XCTAssertNil(loader.manifest)
        XCTAssertNil(loader.animation(named: "idle"))
        // image() re-loads on demand after a reset — that is intentional.
        XCTAssertNotNil(loader.image(forRelativePath: "idle_00.png", baseURL: baseURL))
    }
}
