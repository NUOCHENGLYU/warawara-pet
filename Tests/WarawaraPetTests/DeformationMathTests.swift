import XCTest
@testable import WarawaraPet

final class DeformationMathTests: XCTestCase {
    private let tuning = DeformationTuning.default

    private func deformation(velocity: CGVector, grab: CGVector) -> PetDeformation {
        DeformationMath.deformation(forVelocity: velocity, grabVector: grab, tuning: tuning)
    }

    func testZeroVelocityYieldsNeutralDeformation() {
        let d = deformation(velocity: .zero, grab: CGVector(dx: 0, dy: 1))
        XCTAssertEqual(d.stretchScale, 1, accuracy: 0.0001)
        XCTAssertEqual(d.perpendicularScale, 1, accuracy: 0.0001)
        XCTAssertEqual(d.rotation, 0, accuracy: 0.0001)
    }

    func testBelowMinimumSpeedYieldsNeutralDeformation() {
        let d = deformation(velocity: CGVector(dx: 10, dy: 0), grab: CGVector(dx: 0, dy: 1))
        XCTAssertEqual(d.stretchScale, 1, accuracy: 0.0001)
        XCTAssertEqual(d.rotation, 0, accuracy: 0.0001)
    }

    func testHorizontalDragStretchesHorizontally() {
        let d = deformation(velocity: CGVector(dx: 600, dy: 0), grab: .zero)
        XCTAssertEqual(d.stretchAngle, 0, accuracy: 0.001)
        XCTAssertEqual(d.stretchScale, 1 + tuning.maxStretch, accuracy: 0.0001)
        XCTAssertEqual(d.perpendicularScale, 1 / (1 + tuning.maxStretch), accuracy: 0.0001)
        XCTAssertEqual(d.rotation, 0, accuracy: 0.0001)
    }

    func testVerticalDragStretchesVertically() {
        let d = deformation(velocity: CGVector(dx: 0, dy: 600), grab: .zero)
        XCTAssertEqual(d.stretchAngle, .pi / 2, accuracy: 0.001)
        XCTAssertEqual(d.stretchScale, 1 + tuning.maxStretch, accuracy: 0.0001)
    }

    func testDiagonalDragAxisMatchesDirection() {
        let speed: CGFloat = 424.264
        let d = deformation(velocity: CGVector(dx: speed, dy: speed), grab: .zero)
        XCTAssertEqual(d.stretchAngle, .pi / 4, accuracy: 0.001)
        XCTAssertEqual(d.stretchScale, 1 + tuning.maxStretch, accuracy: 0.001)
    }

    func testVolumeIsPreserved() {
        for speed in stride(from: CGFloat(50), through: 800, by: 50) {
            let amount = DeformationMath.stretchAmount(forSpeed: speed, tuning: tuning)
            let stretchScale = 1 + amount
            let perp = DeformationMath.perpendicularScale(forStretchScale: stretchScale)
            XCTAssertEqual(stretchScale * perp, 1, accuracy: 0.0001)
        }
    }

    func testStretchGrowsMonotonicallyWithSpeedUntilClamp() {
        var previous: CGFloat = 0
        for speed in stride(from: CGFloat(50), through: 800, by: 50) {
            let amount = DeformationMath.stretchAmount(forSpeed: speed, tuning: tuning)
            XCTAssertGreaterThanOrEqual(amount, previous)
            XCTAssertLessThanOrEqual(amount, tuning.maxStretch + 0.0001)
            previous = amount
        }
        XCTAssertEqual(
            DeformationMath.stretchAmount(forSpeed: 800, tuning: tuning),
            tuning.maxStretch,
            accuracy: 0.0001
        )
    }

    func testGrabAboveAndBelowCenterGiveOppositeRotation() {
        let velocity = CGVector(dx: 100, dy: 0)
        let above = deformation(velocity: velocity, grab: CGVector(dx: 0, dy: 1))
        let below = deformation(velocity: velocity, grab: CGVector(dx: 0, dy: -1))
        XCTAssertLessThan(above.rotation, 0)
        XCTAssertGreaterThan(below.rotation, 0)
        XCTAssertEqual(above.rotation, -below.rotation, accuracy: 0.0001)
    }

    func testGrabNearCenterYieldsTinyRotation() {
        let d = deformation(velocity: CGVector(dx: 600, dy: 0), grab: CGVector(dx: 0.01, dy: 0))
        XCTAssertLessThan(abs(d.rotation), 0.005)
    }

    func testRotationIsCapped() {
        let d = deformation(velocity: CGVector(dx: 10000, dy: 0), grab: CGVector(dx: 0, dy: 1))
        XCTAssertEqual(d.rotation, -tuning.maxRotation, accuracy: 0.0001)

        let fast = deformation(velocity: CGVector(dx: -10000, dy: 0), grab: CGVector(dx: 0, dy: 1))
        XCTAssertEqual(fast.rotation, tuning.maxRotation, accuracy: 0.0001)
    }

    func testVelocityAndNegatedVelocityShareStretchAxis() {
        let velocity = CGVector(dx: 300, dy: 200)
        let forward = deformation(velocity: velocity, grab: CGVector(dx: 0.3, dy: 0.9))
        let backward = deformation(velocity: CGVector(dx: -300, dy: -200), grab: CGVector(dx: 0.3, dy: 0.9))

        // Same undirected axis: angles differ by pi, so cos/sin of 2*angle match.
        XCTAssertEqual(
            cos(2 * forward.stretchAngle), cos(2 * backward.stretchAngle), accuracy: 0.0001
        )
        XCTAssertEqual(
            sin(2 * forward.stretchAngle), sin(2 * backward.stretchAngle), accuracy: 0.0001
        )
        XCTAssertEqual(forward.stretchScale, backward.stretchScale, accuracy: 0.0001)
        XCTAssertEqual(forward.perpendicularScale, backward.perpendicularScale, accuracy: 0.0001)
        XCTAssertEqual(forward.rotation, -backward.rotation, accuracy: 0.0001)
    }

    func testStretchAnglesAreCanonicalizedToUndirectedRange() {
        XCTAssertEqual(
            deformation(velocity: CGVector(dx: 100, dy: 0), grab: .zero).stretchAngle,
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            deformation(velocity: CGVector(dx: 0, dy: 100), grab: .zero).stretchAngle,
            .pi / 2,
            accuracy: 0.0001
        )
        // Down is the same undirected axis as up.
        XCTAssertEqual(
            deformation(velocity: CGVector(dx: 0, dy: -100), grab: .zero).stretchAngle,
            .pi / 2,
            accuracy: 0.0001
        )
        // Left is the same undirected axis as right.
        XCTAssertEqual(
            deformation(velocity: CGVector(dx: -100, dy: 0), grab: .zero).stretchAngle,
            0,
            accuracy: 0.0001
        )
    }

    func testAtan2WrapBoundaryDoesNotFlipTheAxis() {
        // Velocity direction crossing the -x axis (the atan2 wrap point),
        // at full speed so deformation is actually active.
        let e: CGFloat = 1.2
        let justAbove = deformation(velocity: CGVector(dx: -600, dy: e), grab: .zero)
        let justBelow = deformation(velocity: CGVector(dx: -600, dy: -e), grab: .zero)

        for d in [justAbove, justBelow] {
            XCTAssertGreaterThanOrEqual(d.stretchAngle, 0)
            XCTAssertLessThan(d.stretchAngle, .pi)
            XCTAssertGreaterThan(d.stretchScale, 1.3)
        }

        // The two axes are the same undirected line: the angle difference
        // is pi (|cos| == 1), so the visual transform does not flip.
        let difference = justAbove.stretchAngle - justBelow.stretchAngle
        XCTAssertEqual(abs(cos(difference)), 1, accuracy: 0.001)
        XCTAssertEqual(justAbove.stretchScale, justBelow.stretchScale, accuracy: 0.0001)
        XCTAssertEqual(justAbove.perpendicularScale, justBelow.perpendicularScale, accuracy: 0.0001)
    }

    func testGrabAnchorIsClampedToInterior() {
        let d = deformation(velocity: CGVector(dx: 100, dy: 0), grab: CGVector(dx: 2, dy: 2))
        XCTAssertEqual(d.anchor.dx, tuning.grabAnchorLimit, accuracy: 0.0001)
        XCTAssertEqual(d.anchor.dy, tuning.grabAnchorLimit, accuracy: 0.0001)

        // The clamped anchor is also the one used for torque.
        let expectedRotation = -tuning.grabAnchorLimit * 100 * tuning.rotationGain
        XCTAssertEqual(d.rotation, expectedRotation, accuracy: 0.0001)
    }
}
