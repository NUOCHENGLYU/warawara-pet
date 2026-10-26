import Foundation
import XCTest
@testable import WarawaraPet

/// Pure morph math: one reversible parameter, no visual jumps on
/// direction changes, easing endpoints.
final class BottleMorphMathTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let duration: TimeInterval = 1.5

    func testEasedEndpointsAndMidpoint() {
        XCTAssertEqual(BottleMorphMath.eased(0), 0)
        XCTAssertEqual(BottleMorphMath.eased(1), 1)
        XCTAssertEqual(BottleMorphMath.eased(-5), 0)
        XCTAssertEqual(BottleMorphMath.eased(9), 1)
        // Smoothstep midpoint is 0.5; easing is slower than linear at
        // the edges (0.25 -> 0.15625).
        XCTAssertEqual(BottleMorphMath.eased(0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(BottleMorphMath.eased(0.25), 0.15625, accuracy: 0.0001)
    }

    func testEasedIsMonotonic() {
        var previous = -1.0
        var value = 0.0
        while value <= 1.0001 {
            let eased = BottleMorphMath.eased(value)
            XCTAssertGreaterThanOrEqual(eased, previous)
            previous = eased
            value += 0.01
        }
    }

    func testRawProgressAdvancesAndClamps() {
        let forward = BottleMorphMath.rawProgress(
            at: start.addingTimeInterval(duration / 2),
            startedAt: start, direction: .toBottle, duration: duration
        )
        XCTAssertEqual(forward, 0.5, accuracy: 0.0001)
        XCTAssertEqual(
            BottleMorphMath.rawProgress(
                at: start.addingTimeInterval(duration * 3),
                startedAt: start, direction: .toBottle, duration: duration
            ),
            1
        )
        XCTAssertEqual(
            BottleMorphMath.rawProgress(
                at: start.addingTimeInterval(-3),
                startedAt: start, direction: .toBottle, duration: duration
            ),
            0
        )
        let backward = BottleMorphMath.rawProgress(
            at: start.addingTimeInterval(duration / 2),
            startedAt: start, direction: .toNormal, duration: duration
        )
        XCTAssertEqual(backward, 0.5, accuracy: 0.0001)
    }

    func testReversalKeepsCurrentProgressContinuous() {
        // Forward to 40%, then reverse: the progress at the reversal
        // instant must be identical (no visual jump).
        let half = start.addingTimeInterval(0.4 * duration)
        let forward = BottleMorphMath.rawProgress(
            at: half, startedAt: start, direction: .toBottle, duration: duration
        )
        XCTAssertEqual(forward, 0.4, accuracy: 0.0001)

        let reversedStart = BottleMorphMath.startDate(
            forCurrentProgress: forward, at: half,
            direction: .toNormal, duration: duration
        )
        let afterReversal = BottleMorphMath.rawProgress(
            at: half, startedAt: reversedStart, direction: .toNormal, duration: duration
        )
        XCTAssertEqual(afterReversal, 0.4, accuracy: 0.0001)

        // It keeps moving toward 0 afterwards.
        let later = BottleMorphMath.rawProgress(
            at: half.addingTimeInterval(0.2 * duration),
            startedAt: reversedStart, direction: .toNormal, duration: duration
        )
        XCTAssertEqual(later, 0.2, accuracy: 0.0001)
    }

    func testReversalBothWaysRoundTrips() {
        // toBottle reversal continuity mirrors toNormal.
        let at = start.addingTimeInterval(0.7)
        let back = BottleMorphMath.rawProgress(
            at: at, startedAt: start, direction: .toNormal, duration: duration
        )
        let restart = BottleMorphMath.startDate(
            forCurrentProgress: back, at: at, direction: .toBottle, duration: duration
        )
        XCTAssertEqual(
            BottleMorphMath.rawProgress(
                at: at, startedAt: restart, direction: .toBottle, duration: duration
            ),
            back, accuracy: 0.0001
        )
    }

    func testBottleEnvelopeAlwaysFitsThePetWindow() {
        // The neck/cork/paper must never be clipped by the window top:
        // the headroom above the resting body center absorbs the full
        // envelope including sway and bob slack.
        XCTAssertTrue(BottleMetrics.fitsInWindow(), "bottle top would be clipped")
        XCTAssertLessThanOrEqual(
            BottleMetrics.maximumTopReach(), PetMetrics.visualCenter.y
        )
        // Sanity: the glass body bottom also stays above the window
        // bottom (the body never exceeds the established blob envelope).
        XCTAssertLessThanOrEqual(
            BottleMetrics.glassHeight / 2 + PetMetrics.blobBottomPadding / 2,
            PetMetrics.visualCenter.y + PetMetrics.blobHeight / 2
        )
    }
}
