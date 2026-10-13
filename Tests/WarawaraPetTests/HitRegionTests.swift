import XCTest
@testable import WarawaraPet

final class HitRegionTests: XCTestCase {
    private let region = EllipseHitRegion(
        center: CGPoint(x: 80, y: 65),
        radiusX: 55,
        radiusY: 62
    )

    func testContainsCenter() {
        XCTAssertTrue(region.contains(CGPoint(x: 80, y: 65)))
    }

    func testContainsPointInside() {
        XCTAssertTrue(region.contains(CGPoint(x: 100, y: 70)))
    }

    func testRejectsFarCorner() {
        XCTAssertFalse(region.contains(CGPoint(x: 5, y: 5)))
        XCTAssertFalse(region.contains(CGPoint(x: 155, y: 155)))
    }

    func testRejectsJustOutsideAlongXAxis() {
        XCTAssertFalse(region.contains(CGPoint(x: 80 + 55.5, y: 65)))
    }

    func testBoundaryPointsAreIncluded() {
        XCTAssertTrue(region.contains(CGPoint(x: 80 + 55, y: 65)))
        XCTAssertTrue(region.contains(CGPoint(x: 80, y: 65 + 62)))
        XCTAssertTrue(region.contains(CGPoint(x: 80, y: 65 - 62)))
    }

    func testDefaultRegionMatchesWindowBounds() {
        let bounds = CGRect(
            x: 0, y: 0,
            width: PetMetrics.size.width, height: PetMetrics.size.height
        )
        let petRegion = EllipseHitRegion.petDefault(in: bounds)
        XCTAssertTrue(petRegion.contains(PetMetrics.visualCenter))
        XCTAssertFalse(petRegion.contains(CGPoint(x: 4, y: bounds.height - 4)))
        XCTAssertFalse(petRegion.contains(CGPoint(x: bounds.width - 4, y: 4)))
        // The region stays well inside the enlarged window so the enlarged
        // transparent areas never intercept unrelated clicks.
        XCTAssertFalse(petRegion.contains(CGPoint(x: bounds.midX, y: 1)))
        XCTAssertFalse(petRegion.contains(CGPoint(x: 1, y: bounds.midY)))
    }

    func testDefaultRegionCoversInstalledNeutralArtworkBody() {
        // The Phase 4B neutral artwork body (bodyBounds [[0.10,0.09],
        // [0.80,0.82]] on a 1024 canvas) renders ~115 x 118 pt centered
        // on the visual center. The hit region must cover the whole body.
        let canvas = CGSize(width: 1024, height: 1024)
        let bodyBounds = CGRect(x: 0.10, y: 0.09, width: 0.80, height: 0.82)
        let renderSize = WarawaraAnimationMapper.renderSize(
            canvas: canvas,
            bodyHeightInCanvas: bodyBounds.height * canvas.height,
            targetBodyHeight: PetMetrics.blobHeight
        )
        let halfWidth = bodyBounds.width * renderSize.width / 2
        let halfHeight = bodyBounds.height * renderSize.height / 2
        let region = EllipseHitRegion.petDefault(in: CGRect(origin: .zero, size: PetMetrics.size))
        for point in [
            CGPoint(x: PetMetrics.visualCenter.x + halfWidth, y: PetMetrics.visualCenter.y),
            CGPoint(x: PetMetrics.visualCenter.x - halfWidth, y: PetMetrics.visualCenter.y),
            CGPoint(x: PetMetrics.visualCenter.x, y: PetMetrics.visualCenter.y + halfHeight),
            CGPoint(x: PetMetrics.visualCenter.x, y: PetMetrics.visualCenter.y - halfHeight)
        ] {
            XCTAssertTrue(region.contains(point), "hit region misses body edge \(point)")
        }
    }
}
