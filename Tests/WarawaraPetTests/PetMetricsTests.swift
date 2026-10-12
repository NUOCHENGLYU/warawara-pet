import XCTest
@testable import WarawaraPet

final class PetMetricsTests: XCTestCase {
    func testVisualCenterMapsToZero() {
        let grab = PetMetrics.normalizedGrabVector(grabPoint: PetMetrics.visualCenter)
        XCTAssertEqual(grab.dx, 0, accuracy: 0.0001)
        XCTAssertEqual(grab.dy, 0, accuracy: 0.0001)
    }

    func testTopEdgeClampsToOne() {
        let grab = PetMetrics.normalizedGrabVector(
            grabPoint: CGPoint(x: PetMetrics.size.width / 2, y: PetMetrics.size.height)
        )
        XCTAssertEqual(grab.dx, 0, accuracy: 0.0001)
        XCTAssertEqual(grab.dy, 1, accuracy: 0.0001)
    }

    func testCornerClampsToUnitSquare() {
        let grab = PetMetrics.normalizedGrabVector(
            grabPoint: CGPoint(x: PetMetrics.size.width, y: PetMetrics.size.height)
        )
        XCTAssertEqual(grab.dx, 1, accuracy: 0.0001)
        XCTAssertEqual(grab.dy, 1, accuracy: 0.0001)
    }

    func testLeftOfCenterMapsToNegativeX() {
        let grab = PetMetrics.normalizedGrabVector(
            grabPoint: CGPoint(x: 0, y: PetMetrics.visualCenter.y)
        )
        XCTAssertEqual(grab.dx, -1, accuracy: 0.0001)
        XCTAssertEqual(grab.dy, 0, accuracy: 0.0001)
    }

    func testInteriorPointIsNormalizedByHalfSize() {
        let half = PetMetrics.size.width / 2
        let grab = PetMetrics.normalizedGrabVector(
            grabPoint: CGPoint(x: PetMetrics.visualCenter.x + half / 2, y: PetMetrics.visualCenter.y + half / 2)
        )
        XCTAssertEqual(grab.dx, 0.5, accuracy: 0.0001)
        XCTAssertEqual(grab.dy, 0.5, accuracy: 0.0001)
    }

    // MARK: - Deformation envelope (drag clipping regression)

    func testWorstCaseDownwardExtensionFitsInsideWindow() {
        // Extreme-but-realistic deformation: max stretch about the highest
        // grab anchor must never push the blob bottom past the window edge.
        let tuning = DeformationTuning.default
        let extensionAmount = PetMetrics.worstCaseDownwardExtension(
            maxStretch: tuning.maxStretch,
            grabAnchorLimit: tuning.grabAnchorLimit
        )
        XCTAssertLessThanOrEqual(
            extensionAmount,
            PetMetrics.bottomClearance,
            "fast vertical drags must not clip the blob bottom"
        )
        XCTAssertGreaterThan(extensionAmount, 0)
    }

    func testVisualCenterIsDerivedFromPaddingAndHeight() {
        XCTAssertEqual(
            PetMetrics.visualCenter,
            CGPoint(
                x: PetMetrics.size.width / 2,
                y: PetMetrics.blobBottomPadding + PetMetrics.blobHeight / 2
            )
        )
    }

    func testBlobFitsInsideWindow() {
        XCTAssertLessThanOrEqual(
            PetMetrics.blobBottomPadding + PetMetrics.blobHeight,
            PetMetrics.size.height
        )
    }
}
