import SwiftUI
import XCTest
@testable import WarawaraPet

/// The morph reveal geometry: one interpolated region (width, height,
/// corner radius, inner image scale) plus the handover/blend curves.
/// All values must be continuous, monotonic and reversible by
/// construction — the same functions drive both directions.
final class BottleMorphGeometryTests: XCTestCase {
    func testRevealedSizeEndpointsAndContinuity() {
        let blobWidth: CGFloat = 96
        // Start = the Warawara blob silhouette.
        XCTAssertEqual(BottleMorphGeometry.revealedWidth(progress: 0, blobWidth: blobWidth), blobWidth, accuracy: 0.01)
        XCTAssertEqual(BottleMorphGeometry.revealedHeight(progress: 0), PetMetrics.blobHeight, accuracy: 0.01)
        // End = the full bottle envelope.
        XCTAssertEqual(BottleMorphGeometry.revealedWidth(progress: 1, blobWidth: blobWidth), BottleMetrics.artWidth, accuracy: 0.01)
        XCTAssertEqual(BottleMorphGeometry.revealedHeight(progress: 1), BottleMetrics.artHeight, accuracy: 0.01)

        var previousW = -CGFloat.infinity
        var previousH = -CGFloat.infinity
        var p = 0.0
        while p <= 1.001 {
            let w = BottleMorphGeometry.revealedWidth(progress: p, blobWidth: blobWidth)
            let h = BottleMorphGeometry.revealedHeight(progress: p)
            XCTAssertGreaterThanOrEqual(w, previousW)
            XCTAssertGreaterThanOrEqual(h, previousH)
            previousW = w
            previousH = h
            p += 0.01
        }
    }

    func testArtScaleTracksRevealedHeight() {
        XCTAssertEqual(
            BottleMorphGeometry.artScale(progress: 0),
            PetMetrics.blobHeight / BottleMetrics.artHeight, accuracy: 0.0001
        )
        XCTAssertEqual(BottleMorphGeometry.artScale(progress: 1), 1, accuracy: 0.0001)
        var previous = -CGFloat.infinity
        var p = 0.0
        while p <= 1.001 {
            let s = BottleMorphGeometry.artScale(progress: p)
            XCTAssertGreaterThanOrEqual(s, previous)
            previous = s
            p += 0.01
        }
    }

    func testCornerRadiusStartsAsCapsuleEndsAsBottle() {
        let width = BottleMetrics.artWidth
        XCTAssertEqual(
            BottleMorphGeometry.cornerRadius(progress: 0, width: width), width / 2, accuracy: 0.01
        )
        XCTAssertEqual(
            BottleMorphGeometry.cornerRadius(progress: 1, width: width), width * 0.10, accuracy: 0.01
        )
    }

    func testHandoverCurves() {
        XCTAssertEqual(BottleMorphGeometry.handoverOpacity(progress: 0), 0, accuracy: 0.001)
        XCTAssertEqual(BottleMorphGeometry.handoverOpacity(progress: 1), 1, accuracy: 0.001)
        XCTAssertEqual(BottleMorphGeometry.bodyHandoverOpacity(progress: 0), 1, accuracy: 0.001)
        XCTAssertEqual(BottleMorphGeometry.bodyHandoverOpacity(progress: 1), 0, accuracy: 0.001)
        XCTAssertEqual(BottleMorphGeometry.faceOpacity(progress: 0), 1, accuracy: 0.001)
        XCTAssertEqual(BottleMorphGeometry.faceOpacity(progress: 1), 0, accuracy: 0.001)
        // The face disappears early enough that the full bottle is
        // NEVER anthropomorphic.
        XCTAssertLessThanOrEqual(BottleMorphGeometry.faceOpacity(progress: 0.6), 0.05)
    }

    func testRevertBlendSwapsUnreadForIdle() {
        XCTAssertEqual(BottleMorphGeometry.revertBlend(progress: 1), 0, accuracy: 0.001)
        XCTAssertEqual(BottleMorphGeometry.revertBlend(progress: 0.5), 1, accuracy: 0.001)
        XCTAssertEqual(BottleMorphGeometry.openingBlend(openingProgress: 0), 0, accuracy: 0.001)
        XCTAssertEqual(BottleMorphGeometry.openingBlend(openingProgress: 1), 1, accuracy: 0.001)
    }

    func testCompressThenStretchChoreography() {
        // Compress peaks early (midpoint of the first 45%)...
        XCTAssertEqual(BottleMorphGeometry.compressAmount(progress: 0.225), 1, accuracy: 0.01)
        XCTAssertEqual(BottleMorphGeometry.compressAmount(progress: 0), 0, accuracy: 0.001)
        XCTAssertEqual(BottleMorphGeometry.compressAmount(progress: 0.5), 0, accuracy: 0.001)
        // ...then the stretch takes over toward the end.
        XCTAssertEqual(BottleMorphGeometry.stretchAmount(progress: 0.4), 0, accuracy: 0.01)
        XCTAssertEqual(BottleMorphGeometry.stretchAmount(progress: 1), 1, accuracy: 0.001)
    }

    func testMaskShapeStaysInsideItsFrame() {
        let rect = CGRect(x: 0, y: 0, width: BottleMetrics.artHeight, height: BottleMetrics.artHeight)
        for p in stride(from: 0.0, through: 1.0, by: 0.2) {
            let w = BottleMorphGeometry.revealedWidth(progress: p, blobWidth: 96)
            let h = BottleMorphGeometry.revealedHeight(progress: p)
            let r = BottleMorphGeometry.cornerRadius(progress: p, width: w)
            let shape = BottleMorphMaskShape(width: w, height: h, cornerRadius: r)
            let bounds = shape.path(in: rect).boundingRect
            XCTAssertGreaterThanOrEqual(bounds.minX, -0.01)
            XCTAssertGreaterThanOrEqual(bounds.minY, -0.01)
            XCTAssertLessThanOrEqual(bounds.maxX, rect.maxX + 0.01)
            XCTAssertLessThanOrEqual(bounds.maxY, rect.maxY + 0.01)
            // Bottom-anchored.
            XCTAssertEqual(bounds.maxY, rect.maxY, accuracy: 0.01)
        }
    }

    func testArtEnvelopeFitsTheWindowTop() {
        // Bottle bottom sits on the body baseline; the painted envelope
        // must never cross the window top even with bob + sway slack.
        XCTAssertTrue(BottleMetrics.fitsInWindow())
        XCTAssertLessThanOrEqual(BottleMetrics.artTopReach(), PetMetrics.visualCenter.y)
        XCTAssertLessThanOrEqual(BottleMetrics.proceduralTopReach(), PetMetrics.visualCenter.y)
        // The art envelope stays within the pet window frame.
        XCTAssertGreaterThanOrEqual(BottleMetrics.artTopY, 0)
        XCTAssertLessThanOrEqual(BottleMetrics.artBottomY, PetMetrics.size.height)
    }
}
