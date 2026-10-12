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
}
