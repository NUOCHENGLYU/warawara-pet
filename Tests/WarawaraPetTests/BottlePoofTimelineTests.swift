import CoreGraphics
import XCTest
@testable import WarawaraPet

/// The poof transition choreography: phase boundaries, the hidden
/// asset swap, the OCCLUSION invariant (smoke covers both silhouettes
/// at the switch), the landing wobble, and Reduce Motion behavior.
final class BottlePoofTimelineTests: XCTestCase {
    func testPhaseOrderingAndDuration() {
        XCTAssertEqual(BottlePoofTimeline.duration, 1.35)
        XCTAssertGreaterThan(BottlePoofTimeline.poofPoint, 0)
        XCTAssertGreaterThan(BottlePoofTimeline.switchPoint, BottlePoofTimeline.poofPoint)
        XCTAssertGreaterThan(BottlePoofTimeline.descentEnd, BottlePoofTimeline.switchPoint)
        XCTAssertLessThan(BottlePoofTimeline.descentEnd, 1)
    }

    func testJumpArcForward() {
        // Rest, anticipation, hop peak (26-32 pt), hidden hold drop,
        // gentle descent, grounded.
        XCTAssertEqual(BottlePoofTimeline.jumpOffsetY(t: 0, reduceMotion: false), 0, accuracy: 0.01)
        let peak = BottlePoofTimeline.jumpOffsetY(t: 0.35, reduceMotion: false)
        XCTAssertGreaterThanOrEqual(peak, 26)
        XCTAssertLessThanOrEqual(peak, 32)
        XCTAssertEqual(peak, 30, accuracy: 0.5)
        XCTAssertEqual(
            BottlePoofTimeline.jumpOffsetY(t: BottlePoofTimeline.switchPoint, reduceMotion: false),
            BottlePoofTimeline.switchHoldHeight, accuracy: 0.01
        )
        XCTAssertEqual(BottlePoofTimeline.jumpOffsetY(t: 1, reduceMotion: false), 0, accuracy: 0.01)

        // Rise is monotonic to the peak; descent is monotonic after the
        // hidden switch.
        var previous = -CGFloat.infinity
        var t = 0.0
        while t <= BottlePoofTimeline.poofPoint {
            let y = BottlePoofTimeline.jumpOffsetY(t: t, reduceMotion: false)
            XCTAssertGreaterThanOrEqual(y, previous)
            previous = y
            t += 0.01
        }
        previous = .infinity
        t = BottlePoofTimeline.switchPoint + 0.001
        while t <= 1.0 {
            let y = BottlePoofTimeline.jumpOffsetY(t: t, reduceMotion: false)
            XCTAssertLessThanOrEqual(y, previous + 0.01)
            previous = y
            t += 0.01
        }
    }

    func testJumpArcReducedMotionIsSmaller() {
        let peak = BottlePoofTimeline.jumpOffsetY(t: 0.35, reduceMotion: true)
        XCTAssertEqual(peak, BottlePoofTimeline.reducedJumpHeight, accuracy: 0.5)
        XCTAssertEqual(
            BottlePoofTimeline.jumpOffsetY(t: BottlePoofTimeline.switchPoint, reduceMotion: true),
            BottlePoofTimeline.reducedSwitchHoldHeight, accuracy: 0.01
        )
        XCTAssertEqual(BottlePoofTimeline.jumpOffsetY(t: 1, reduceMotion: true), 0, accuracy: 0.01)
        // The decorative smoke spread is reduced; the core occlusion
        // stays full (checked in the occlusion tests below).
        let full = BottlePoofTimeline.decorativeSmokeScale(t: 0.6, reduceMotion: false)
        let reduced = BottlePoofTimeline.decorativeSmokeScale(t: 0.6, reduceMotion: true)
        XCTAssertLessThan(reduced, full)
    }

    func testSquashChoreography() {
        // Anticipation: squashed down, wider.
        XCTAssertLessThan(BottlePoofTimeline.squashY(t: 0.1), 0.9)
        XCTAssertGreaterThan(BottlePoofTimeline.squashX(t: 0.1), 1.05)
        // Mid-flight: stretched tall, narrower.
        XCTAssertGreaterThan(BottlePoofTimeline.squashY(t: 0.3), 1.0)
        XCTAssertLessThan(BottlePoofTimeline.squashX(t: 0.3), 1.0)
        // Landing squash then settle to neutral.
        XCTAssertLessThan(BottlePoofTimeline.squashY(t: 0.85), 1.0)
        XCTAssertEqual(BottlePoofTimeline.squashY(t: 1), 1, accuracy: 0.01)
        XCTAssertEqual(BottlePoofTimeline.squashX(t: 1), 1, accuracy: 0.01)
    }

    func testLandingWobbleDecaysToZero() {
        XCTAssertEqual(BottlePoofTimeline.landingWobble(t: 0.5), 0)
        XCTAssertEqual(BottlePoofTimeline.landingWobble(t: 1), 0, accuracy: 0.0001)
        // Peaks shortly after landing and stays tiny.
        var peak = 0.0
        var t = BottlePoofTimeline.descentEnd
        while t <= 1.0 {
            peak = max(peak, abs(BottlePoofTimeline.landingWobble(t: t)))
            t += 0.005
        }
        XCTAssertGreaterThan(peak, 0.004)
        XCTAssertLessThan(peak, 0.03)
    }

    // MARK: - Hidden swap + occlusion

    func testFormStepsExactlyAtTheSwitch() {
        XCTAssertEqual(BottlePoofTimeline.formProgress(at: 0), 0)
        XCTAssertEqual(BottlePoofTimeline.formProgress(at: BottlePoofTimeline.switchPoint - 0.001), 0)
        XCTAssertEqual(BottlePoofTimeline.formProgress(at: BottlePoofTimeline.switchPoint), 1)
        XCTAssertEqual(BottlePoofTimeline.formProgress(at: 1), 1)
    }

    func testSmokeIsFullyOpaqueAtTheSwitch() {
        XCTAssertEqual(
            BottlePoofTimeline.coreSmokeOpacity(t: BottlePoofTimeline.switchPoint), 1, accuracy: 0.001
        )
        // And stays full while the hidden swap lands.
        var t = BottlePoofTimeline.switchPoint
        while t <= 0.46 {
            XCTAssertGreaterThanOrEqual(
                BottlePoofTimeline.coreSmokeOpacity(t: t), 0.999,
                "smoke must stay opaque across the swap window (t=\(t))"
            )
            t += 0.005
        }
        XCTAssertEqual(BottlePoofTimeline.coreSmokeOpacity(t: 0), 0)
        XCTAssertEqual(BottlePoofTimeline.coreSmokeOpacity(t: 1), 0)
    }

    /// The machine-checked occlusion rule: from the switch through the
    /// hold, the core smoke's OPAQUE region contains the union envelope
    /// of both silhouettes — the asset swap can never be seen.
    func testOcclusionCoversBothSilhouettesAtTheSwitch() {
        for reduceMotion in [false, true] {
            var t = BottlePoofTimeline.switchPoint
            while t <= 0.46 {
                let envelope = BottlePoofTimeline.envelopeRect(t: t, reduceMotion: reduceMotion)
                let covered = BottlePoofTimeline.occludedRect(t: t, reduceMotion: reduceMotion)
                XCTAssertTrue(
                    covered.contains(envelope),
                    "reduceMotion=\(reduceMotion) t=\(t): covered \(covered) does not contain envelope \(envelope)"
                )
                t += 0.01
            }
        }
    }

    func testEnvelopeStaysInsideTheWindow() {
        // The bottle's painted content must stay inside the window from
        // the switch onward (no cork clipping).
        var t = BottlePoofTimeline.switchPoint
        while t <= 1.0 {
            let envelope = BottlePoofTimeline.envelopeRect(t: t, reduceMotion: false)
            XCTAssertGreaterThanOrEqual(envelope.minY, 0, "bottle top clipped at t=\(t)")
            XCTAssertLessThanOrEqual(
                envelope.maxY, PetMetrics.size.height + 0.01,
                "envelope below the window at t=\(t)"
            )
            t += 0.01
        }
    }

    func testPoofJumpAndStretchFitInsideTopDrawingMargin() {
        // Both directions share the same choreography, so covering the
        // full timeline covers forward and reverse. The wrapper is
        // bottom-anchored: its upward overhang is the jump plus the
        // stretch beyond the 226 pt canvas.
        let canvasHeight = PetMetrics.size.height
        var maxOverhang: CGFloat = 0
        var t = 0.0
        while t <= 1.0 {
            let stretchOverhang = max(
                0,
                canvasHeight * (BottlePoofTimeline.squashY(t: t) - 1)
            )
            let overhang = stretchOverhang
                + BottlePoofTimeline.jumpOffsetY(t: t, reduceMotion: false)
            maxOverhang = max(maxOverhang, overhang)
            t += 0.005
        }
        XCTAssertGreaterThan(maxOverhang, 0)
        XCTAssertLessThanOrEqual(
            maxOverhang, PetMetrics.topDrawingMargin + 0.01,
            "the poof must stay inside the window's transparent top margin"
        )
    }

    func testSmokeVisibleWindowSpansTheTransition() {
        XCTAssertFalse(BottlePoofTimeline.smokeVisible(t: 0))
        XCTAssertTrue(BottlePoofTimeline.smokeVisible(t: BottlePoofTimeline.switchPoint))
        XCTAssertTrue(BottlePoofTimeline.smokeVisible(t: 0.8))
        XCTAssertFalse(BottlePoofTimeline.smokeVisible(t: 1))
    }

    func testSmokeOnsetIsDirectionAware() {
        // Forward: the poof sound fires exactly where the smoke bursts in.
        XCTAssertEqual(
            BottlePoofTimeline.smokeOnset(for: .toBottle),
            BottlePoofTimeline.poofPoint
        )
        XCTAssertLessThan(
            BottlePoofTimeline.smokeOnset(for: .toBottle),
            BottlePoofTimeline.switchPoint
        )
        // Reverse: the mirrored fade-in starts at the reversed
        // dissipation tail — AFTER the switch point, never at poofPoint.
        XCTAssertEqual(
            BottlePoofTimeline.smokeOnset(for: .toNormal),
            BottlePoofTimeline.smokeFadeEnd
        )
        XCTAssertGreaterThan(
            BottlePoofTimeline.smokeOnset(for: .toNormal),
            BottlePoofTimeline.switchPoint
        )
        // The reverse onset really is the first instant the smoke
        // appears: zero just above it (later in reverse time), non-zero
        // just below it.
        let reverseOnset = BottlePoofTimeline.smokeOnset(for: .toNormal)
        XCTAssertEqual(BottlePoofTimeline.coreSmokeOpacity(t: reverseOnset + 0.01), 0)
        XCTAssertGreaterThan(BottlePoofTimeline.coreSmokeOpacity(t: reverseOnset - 0.01), 0)
        // And the forward onset matches the forward smoke appearance.
        let forwardOnset = BottlePoofTimeline.smokeOnset(for: .toBottle)
        XCTAssertEqual(BottlePoofTimeline.coreSmokeOpacity(t: forwardOnset - 0.01), 0)
        XCTAssertGreaterThan(BottlePoofTimeline.coreSmokeOpacity(t: forwardOnset + 0.01), 0)
    }

    func testCoreSmokeFillsEnvelopeInsideWindowWidth() {
        // The core smoke at the switch covers the envelope, and its
        // soft edges simply fade past the window sides — the opaque
        // region never needs to be cut off for coverage.
        let covered = BottlePoofTimeline.occludedRect(t: BottlePoofTimeline.switchPoint, reduceMotion: false)
        XCTAssertLessThan(covered.midX - PetMetrics.visualCenter.x, 1)
        XCTAssertGreaterThanOrEqual(covered.width, BottleMetrics.artWidth)
        XCTAssertGreaterThanOrEqual(covered.height, BottleMetrics.artHeight)
    }
}
