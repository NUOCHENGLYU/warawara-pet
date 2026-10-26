import AppKit
import XCTest
@testable import WarawaraPet

/// Phase 8C v3 art store: loading from the source tree (development/CI),
/// the content-bounds measurement, the missing-asset fallback and the
/// art-vs-procedural resolver.
final class BottleMailArtStoreTests: XCTestCase {
    override func setUpWithError() throws {
        BottleMailArtStore.shared.resetFully()
    }

    func testLoadsAllV3AssetsFromSourceTree() throws {
        let store = BottleMailArtStore()
        let state = store.verifyAllRequiredAssets()
        XCTAssertTrue(state.ok, state.details)
        XCTAssertNotNil(store.bottleIdle)
        XCTAssertNotNil(store.bottleUnread)
        XCTAssertNotNil(store.bottleOpening)
        XCTAssertNotNil(store.scrollSealed)
        XCTAssertNotNil(store.letterPaper)
        XCTAssertTrue(store.hasBottleArt)
        // The official images are transparent 1024 canvases.
        for name in BottleMailArtStore.requiredFileNames {
            let image = store.image(named: name)
            XCTAssertEqual(image?.size.width, 1024, name)
            XCTAssertEqual(image?.size.height, 1024, name)
        }
    }

    func testContentBoundsAreSaneAndWithinCanvas() throws {
        let store = BottleMailArtStore()
        guard let bounds = store.contentBounds(named: "bottle_unread.png") else {
            throw XCTSkip("assets unavailable")
        }
        XCTAssertGreaterThan(bounds.width, 0.4)
        XCTAssertGreaterThan(bounds.height, 0.5)
        XCTAssertGreaterThanOrEqual(bounds.minX, 0)
        XCTAssertGreaterThanOrEqual(bounds.minY, 0)
        XCTAssertLessThanOrEqual(bounds.maxX, 1)
        XCTAssertLessThanOrEqual(bounds.maxY, 1)
        // The scroll is a wide horizontal element (manifest + layout
        // depend on it being wide, not tall).
        if let scroll = store.contentBounds(named: "scroll_sealed.png") {
            XCTAssertGreaterThan(scroll.width, scroll.height)
        }
    }

    func testMissingAssetsFailVerificationAndFallBackToProcedural() throws {
        let emptyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BottleArtMissing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyDir) }

        let store = BottleMailArtStore()
        store.baseURLOverride = emptyDir
        let state = store.verifyAllRequiredAssets()
        XCTAssertFalse(state.ok)
        XCTAssertEqual(store.missingFileNames.count,
                       BottleMailArtStore.requiredFileNames.count + BottleMailArtStore.poofFileNames.count)
        XCTAssertNil(store.bottleUnread)
        XCTAssertFalse(store.hasBottleArt)
        XCTAssertFalse(store.hasPoofAssets)
        XCTAssertEqual(BottleVisualContent.resolve(store: store), .procedural)

        // The real store resolves to the full poof path.
        let real = BottleMailArtStore()
        if real.verifyAllRequiredAssets().ok {
            XCTAssertEqual(BottleVisualContent.resolve(store: real), .poofArt)
        }
    }

    func testArtWithoutPoofPackResolvesToTheRevealFallback() throws {
        // A directory with the five v3 bottle images but no smoke pack:
        // the safe geometric-reveal fallback must be chosen (the poof
        // mode cannot hide the swap without the occlusion smoke).
        guard let sourceBase = BottleMailArtStore.shared.resolveBaseURL() else {
            throw XCTSkip("assets unavailable")
        }
        let partialDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BottleArtPartial-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: partialDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: partialDir) }
        for name in BottleMailArtStore.requiredFileNames {
            try FileManager.default.copyItem(
                at: sourceBase.appendingPathComponent(name),
                to: partialDir.appendingPathComponent(name)
            )
        }

        let store = BottleMailArtStore()
        store.baseURLOverride = partialDir
        XCTAssertTrue(store.hasBottleArt)
        XCTAssertFalse(store.hasPoofAssets)
        XCTAssertEqual(BottleVisualContent.resolve(store: store), .revealArt)
    }
}
