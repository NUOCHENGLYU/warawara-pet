import XCTest
@testable import WarawaraPet

final class PetMetricsTests: XCTestCase {
    func testVisualCenterMapsToZero() {
        let grab = PetMetrics.normalizedGrabVector(grabPoint: PetMetrics.visualCenter)
        XCTAssertEqual(grab.dx, 0, accuracy: 0.0001)
        XCTAssertEqual(grab.dy, 0, accuracy: 0.0001)
    }

    func testBeyondWindowEdgesClampToUnitSquare() {
        let grab = PetMetrics.normalizedGrabVector(
            grabPoint: CGPoint(x: PetMetrics.size.width, y: PetMetrics.size.height + 100)
        )
        XCTAssertEqual(grab.dx, 1, accuracy: 0.0001)
        XCTAssertEqual(grab.dy, 1, accuracy: 0.0001)

        let left = PetMetrics.normalizedGrabVector(
            grabPoint: CGPoint(x: -100, y: PetMetrics.visualCenter.y)
        )
        XCTAssertEqual(left.dx, -1, accuracy: 0.0001)
        XCTAssertEqual(left.dy, 0, accuracy: 0.0001)
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
        let tuning = DeformationTuning.default
        let extensionAmount = PetMetrics.worstCaseVerticalExtension(
            maxStretch: tuning.maxStretch,
            maxLean: tuning.maxRotation
        )
        XCTAssertLessThanOrEqual(
            extensionAmount,
            PetMetrics.bottomClearance,
            "fast drags must not clip the blob bottom"
        )
        XCTAssertGreaterThan(extensionAmount, 0)
    }

    func testWorstCaseUpwardExtensionFitsInsideWindow() {
        let tuning = DeformationTuning.default
        let extensionAmount = PetMetrics.worstCaseVerticalExtension(
            maxStretch: tuning.maxStretch,
            maxLean: tuning.maxRotation
        )
        XCTAssertLessThanOrEqual(
            extensionAmount,
            PetMetrics.topClearance,
            "fast drags must not clip the blob top"
        )
        XCTAssertGreaterThan(extensionAmount, 0)
    }

    func testBlobBottomPaddingIsStableAcrossGeometryChanges() {
        // The blob's bottom offset is fixed so persisted window origins
        // keep restoring to the same apparent position.
        XCTAssertEqual(PetMetrics.blobBottomPadding, 54)
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
        XCTAssertLessThanOrEqual(PetMetrics.blobWidth, PetMetrics.size.width)
    }

    func testRenderAnchorClampConfinesAnchorToBlob() {
        let extreme = CGVector(dx: 5, dy: 5)
        let anchor = DeformationMath.blobClampedAnchor(extreme)
        XCTAssertLessThanOrEqual(abs(anchor.dy), 0.523)
        XCTAssertLessThanOrEqual(abs(anchor.dx), 0.481)
        // Anchor extremes map onto the blob's own vertical extent.
        let topUnit = 0.5 - 0.5 * anchor.dy
        let topViewY = PetMetrics.size.height * (1 - topUnit)
        XCTAssertEqual(topViewY, PetMetrics.blobBottomPadding + PetMetrics.blobHeight, accuracy: 0.001)
    }
}
