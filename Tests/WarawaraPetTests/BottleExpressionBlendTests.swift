import Foundation
import XCTest
@testable import WarawaraPet

/// The expression-mapper side of the bottle morph: the face must
/// dissolve (the bottle is strictly non-anthropomorphic), the body
/// raster hands over to the art, and the silhouette compresses before
/// stretching — for ANY base state.
final class BottleExpressionBlendTests: XCTestCase {
    private func parameters(at progress: CGFloat, state: PetState = .idle) -> WarawaraPerformanceParameters {
        WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(state: state, bottleMorphProgress: progress),
            breathPhase: 0.25
        ))
    }

    func testNoProgressLeavesEverythingUntouched() {
        let p = parameters(at: 0)
        XCTAssertEqual(p.faceOpacity, 1)
        XCTAssertEqual(p.bodyOpacity, 1)
        XCTAssertEqual(p.bodySquashX, 1)
        XCTAssertEqual(p.bodySquashY, 1)
    }

    func testFaceAndBodyDissolveTowardTheBottle() {
        let mid = parameters(at: 0.4)
        XCTAssertLessThan(mid.faceOpacity, 1)
        XCTAssertGreaterThan(mid.faceOpacity, 0)
        XCTAssertLessThan(mid.bodyOpacity, 1)
        let full = parameters(at: 1)
        XCTAssertEqual(full.faceOpacity, 0, "the bottle must never keep eyes/mouth")
        XCTAssertEqual(full.bodyOpacity, 0, "the body raster hands over to the art")
    }

    func testFaceFadesEvenWhileSleepy() {
        // A dozing pet that receives mail still loses its face during
        // the morph — no anthropomorphic bottle regardless of state.
        let full = parameters(at: 1, state: .sleeping)
        XCTAssertEqual(full.faceOpacity, 0)
        let sleepy = parameters(at: 1, state: .sleepy)
        XCTAssertEqual(sleepy.faceOpacity, 0)
    }

    func testSilhouetteCompressesThenStretches() {
        // Early: the body dips below neutral height (compression).
        let early = parameters(at: 0.22)
        XCTAssertLessThan(early.bodySquashY, 1)
        XCTAssertGreaterThan(early.bodySquashX, 1)
        // Late: stretched taller and slightly narrower (bottle growth).
        let late = parameters(at: 1)
        XCTAssertGreaterThan(late.bodySquashY, 1)
        XCTAssertLessThan(late.bodySquashX, 1)
    }

    func testBlendIsContinuousAcrossProgress() {
        var previous = parameters(at: 0)
        var p: CGFloat = 0.01
        while p <= 1.001 {
            let current = parameters(at: p)
            // No abrupt jumps anywhere in the blend channels. The
            // fastest legitimate slope (the face fade) moves < 0.08 per
            // 0.01 of progress; a discrete jump (e.g. a style flip)
            // would register as >= 1.
            XCTAssertLessThan(
                current.distance(to: previous), 0.1,
                "blend jumped between p=\(p - 0.01) and p=\(p)"
            )
            previous = current
            p += 0.01
        }
    }

    func testCuriousStateKeepsGazeButLosesFace() {
        let base = WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(state: .curious, gaze: CGVector(dx: 0.6, dy: 0.2)),
            breathPhase: 0.25
        ))
        XCTAssertGreaterThan(abs(base.gazeX), 0.4)
        let full = parameters(at: 1, state: .curious)
        XCTAssertEqual(full.faceOpacity, 0)
        XCTAssertEqual(full.bodyOpacity, 0)
    }
}
