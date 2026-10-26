import Foundation
import XCTest
@testable import WarawaraPet

/// The expression-mapper side of the poof transition: the form input is
/// a HARD STEP (0 = Warawara, 1 = bottle) — the swap is hidden behind
/// full occlusion smoke, so the face/body handover flips instantly and
/// the bottle is strictly non-anthropomorphic. The jump/squash
/// choreography lives in BottlePoofTimeline, not in the mapper.
final class BottleExpressionBlendTests: XCTestCase {
    private func parameters(at progress: CGFloat, state: PetState = .idle) -> WarawaraPerformanceParameters {
        WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(state: state, bottleMorphProgress: progress),
            breathPhase: 0.25
        ))
    }

    func testWarawaraFormKeepsFaceAndBody() {
        let p = parameters(at: 0)
        XCTAssertEqual(p.faceOpacity, 1)
        XCTAssertEqual(p.bodyOpacity, 1)
        XCTAssertEqual(p.bodySquashX, 1)
        XCTAssertEqual(p.bodySquashY, 1)
    }

    func testBottleFormHidesFaceAndBodyCompletely() {
        let full = parameters(at: 1)
        XCTAssertEqual(full.faceOpacity, 0, "the bottle must never keep eyes/mouth")
        XCTAssertEqual(full.bodyOpacity, 0, "the body raster hands over to the bottle art")
        // The step boundary: at and above the midpoint the form is the
        // bottle (the input is the coordinator's formProgress step).
        let boundary = parameters(at: 0.5)
        XCTAssertEqual(boundary.faceOpacity, 0)
        XCTAssertEqual(boundary.bodyOpacity, 0)
        let below = parameters(at: 0.49)
        XCTAssertEqual(below.faceOpacity, 1)
        XCTAssertEqual(below.bodyOpacity, 1)
    }

    func testSquashIsNotDoubledByTheMapper() {
        // The poof choreography (anticipation/flight/landing squash) is
        // applied by the VIEW layer; the mapper must stay neutral so the
        // two never stack.
        let full = parameters(at: 1, state: .sleeping)
        XCTAssertEqual(full.bodySquashX, 1, "mapper must not apply bottle squash")
        XCTAssertEqual(full.bodySquashY, 1)
        XCTAssertEqual(full.faceOpacity, 0)
    }

    func testAnimatorPassesTheHandoverThroughInstantly() {
        // The hidden swap demands INSTANT face/body handover: a smoothed
        // fade would leak a semi-transparent overlap as the smoke
        // clears. One step must land exactly on the target.
        var animator = WarawaraParameterAnimator()
        let target = WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(state: .idle, bottleMorphProgress: 1),
            breathPhase: 0.25
        ))
        XCTAssertEqual(target.faceOpacity, 0)
        XCTAssertEqual(target.bodyOpacity, 0)
        animator.step(toward: target, dt: 1.0 / 30.0)
        XCTAssertEqual(animator.parameters.faceOpacity, 0, accuracy: 0.0001)
        XCTAssertEqual(animator.parameters.bodyOpacity, 0, accuracy: 0.0001)
        // And back in one step (the reverse swap is hidden too).
        let back = WarawaraExpressionMapper.targetParameters(for: WarawaraExpressionContext(
            inputs: WarawaraExpressionInputs(state: .idle, bottleMorphProgress: 0),
            breathPhase: 0.25
        ))
        animator.step(toward: back, dt: 1.0 / 30.0)
        XCTAssertEqual(animator.parameters.faceOpacity, 1, accuracy: 0.0001)
        XCTAssertEqual(animator.parameters.bodyOpacity, 1, accuracy: 0.0001)
    }

    func testCuriousStateLosesFaceAtBottleForm() {
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
