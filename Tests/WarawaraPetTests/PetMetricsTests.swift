import XCTest
@testable import WarawaraPet

final class PetMetricsTests: XCTestCase {
    func testVisualCenterMapsToZero() {
        let grab = PetMetrics.normalizedGrabVector(grabPoint: PetMetrics.visualCenter)
        XCTAssertEqual(grab.dx, 0, accuracy: 0.0001)
        XCTAssertEqual(grab.dy, 0, accuracy: 0.0001)
    }

    func testTopEdgeClampsToOne() {
        let grab = PetMetrics.normalizedGrabVector(grabPoint: CGPoint(x: 80, y: 160))
        XCTAssertEqual(grab.dx, 0, accuracy: 0.0001)
        XCTAssertEqual(grab.dy, 1, accuracy: 0.0001)
    }

    func testCornerClampsToUnitSquare() {
        let grab = PetMetrics.normalizedGrabVector(grabPoint: CGPoint(x: 160, y: 160))
        XCTAssertEqual(grab.dx, 1, accuracy: 0.0001)
        XCTAssertEqual(grab.dy, 1, accuracy: 0.0001)
    }

    func testLeftOfCenterMapsToNegativeX() {
        let grab = PetMetrics.normalizedGrabVector(grabPoint: CGPoint(x: 0, y: 65))
        XCTAssertEqual(grab.dx, -1, accuracy: 0.0001)
        XCTAssertEqual(grab.dy, 0, accuracy: 0.0001)
    }

    func testInteriorPointIsNormalizedByHalfSize() {
        let grab = PetMetrics.normalizedGrabVector(grabPoint: CGPoint(x: 120, y: 105))
        XCTAssertEqual(grab.dx, 0.5, accuracy: 0.0001)
        XCTAssertEqual(grab.dy, 0.5, accuracy: 0.0001)
    }
}
