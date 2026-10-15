import XCTest
@testable import WarawaraPet

/// Pure math of the 2.5D turn: clamping, zero-angle identity, sign
/// conventions, left/right mirror symmetry, continuity, and the
/// single-source facial remap.
final class WarawaraTurnGeometryTests: XCTestCase {
    private let canvas = CGSize(width: 143.9, height: 143.9)
    private let bodyBounds = CGRect(x: 0.10, y: 0.09, width: 0.80, height: 0.82)

    func testYawAndPitchClampToDocumentedRanges() {
        XCTAssertEqual(WarawaraTurnGeometry.clampedYaw(30), 25, accuracy: 0.001)
        XCTAssertEqual(WarawaraTurnGeometry.clampedYaw(-30), -25, accuracy: 0.001)
        XCTAssertEqual(WarawaraTurnGeometry.clampedYaw(10), 10, accuracy: 0.001)
        XCTAssertEqual(WarawaraTurnGeometry.clampedPitch(15), 10, accuracy: 0.001)
        XCTAssertEqual(WarawaraTurnGeometry.clampedPitch(-15), -10, accuracy: 0.001)
    }

    func testZeroAngleIsExactlyIdentity() {
        XCTAssertFalse(WarawaraTurnGeometry.isActive(yawDegrees: 0, pitchDegrees: 0))
        let strips = WarawaraTurnGeometry.strips(
            count: 14, canvasSize: canvas, bodyBounds: bodyBounds,
            yawDegrees: 0, pitchDegrees: 0
        )
        let bodyRect = CGRect(
            x: bodyBounds.minX * canvas.width,
            y: bodyBounds.minY * canvas.height,
            width: bodyBounds.width * canvas.width,
            height: bodyBounds.height * canvas.height
        )
        for strip in strips {
            XCTAssertEqual(strip.source.minX, strip.destination.minX, accuracy: 0.0001,
                           "zero yaw must reproduce the accepted artwork exactly")
            XCTAssertEqual(strip.source.minY, strip.destination.minY, accuracy: 0.0001)
            XCTAssertEqual(strip.source.width, strip.destination.width, accuracy: 0.0001)
            XCTAssertEqual(strip.source.height, strip.destination.height, accuracy: 0.0001)
        }
        XCTAssertEqual(
            strips.last?.destination.maxX ?? 0, bodyRect.maxX, accuracy: 0.0001
        )
        let face = WarawaraTurnGeometry.faceTransform(yawDegrees: 0, pitchDegrees: 0)
        XCTAssertTrue(face.isIdentity())
        XCTAssertEqual(WarawaraTurnGeometry.shadeStrength(yawDegrees: 0), 0, accuracy: 0.001)
    }

    func testYawPreservesTotalWidth() {
        for yaw in [CGFloat(-25), -15, 15, 25] {
            let strips = WarawaraTurnGeometry.strips(
                count: 14, canvasSize: canvas, bodyBounds: bodyBounds,
                yawDegrees: yaw, pitchDegrees: 0
            )
            let total = strips.map(\.destination.width).reduce(0, +)
            let expected = bodyBounds.width * canvas.width
            XCTAssertEqual(total, expected, accuracy: 0.5, "yaw must not change body size")
        }
    }

    func testYawRedistributesWidthTowardTheTurnDirection() {
        let right = WarawaraTurnGeometry.strips(
            count: 14, canvasSize: canvas, bodyBounds: bodyBounds,
            yawDegrees: 25, pitchDegrees: 0
        )
        let left = WarawaraTurnGeometry.strips(
            count: 14, canvasSize: canvas, bodyBounds: bodyBounds,
            yawDegrees: -25, pitchDegrees: 0
        )
        // Turning right: the rightmost strip widens, the leftmost narrows.
        XCTAssertGreaterThan(right.last!.destination.width, right.first!.destination.width)
        XCTAssertLessThan(left.last!.destination.width, left.first!.destination.width)
    }

    func testLeftRightMirrorSymmetry() {
        let right = WarawaraTurnGeometry.strips(
            count: 14, canvasSize: canvas, bodyBounds: bodyBounds,
            yawDegrees: 20, pitchDegrees: 0
        )
        let left = WarawaraTurnGeometry.strips(
            count: 14, canvasSize: canvas, bodyBounds: bodyBounds,
            yawDegrees: -20, pitchDegrees: 0
        )
        let bodyRect = CGRect(
            x: bodyBounds.minX * canvas.width,
            y: bodyBounds.minY * canvas.height,
            width: bodyBounds.width * canvas.width,
            height: bodyBounds.height * canvas.height
        )
        let midX = bodyRect.midX
        XCTAssertEqual(right.count, left.count)
        for i in 0..<right.count {
            // Mirroring maps the right turn's strip i (counting from the
            // left edge) onto the left turn's strip counted from the
            // right edge.
            let mirroredRight = CGRect(
                x: 2 * midX - right[i].destination.maxX,
                y: right[i].destination.minY,
                width: right[i].destination.width,
                height: right[i].destination.height
            )
            let mirroredLeft = left[left.count - 1 - i].destination
            XCTAssertEqual(mirroredRight.minX, mirroredLeft.minX, accuracy: 0.001,
                           "left turn must mirror the right turn (strip \(i))")
        }
    }

    func testStripsAreContinuousWithoutGaps() {
        for yaw in [CGFloat(-25), -7, 0, 7, 25] {
            let strips = WarawaraTurnGeometry.strips(
                count: 14, canvasSize: canvas, bodyBounds: bodyBounds,
                yawDegrees: yaw, pitchDegrees: 0
            )
            for i in 1..<strips.count {
                XCTAssertEqual(
                    strips[i].destination.minX, strips[i - 1].destination.maxX,
                    accuracy: 0.001, "adjacent strips must touch exactly"
                )
            }
        }
    }

    func testContinuityAcrossYawSweep() {
        // Adjacent yaw samples must produce nearly identical layouts.
        let samples: [CGFloat] = stride(from: -25.0, through: 25.0, by: 2.5).map { $0 }
        var previous: [WarawaraTurnGeometry.Strip]?
        for yaw in samples {
            let strips = WarawaraTurnGeometry.strips(
                count: 14, canvasSize: canvas, bodyBounds: bodyBounds,
                yawDegrees: yaw, pitchDegrees: 0
            )
            if let previous {
                var maxDelta: CGFloat = 0
                for i in 0..<strips.count {
                    maxDelta = max(maxDelta, abs(strips[i].destination.minX - previous[i].destination.minX))
                }
                XCTAssertLessThan(maxDelta, canvas.width * 0.08, "no jumps across yaw")
            }
            previous = strips
        }
    }

    func testFaceTransformSignsFollowScreenConventions() {
        let right = WarawaraTurnGeometry.faceTransform(yawDegrees: 20, pitchDegrees: 0)
        XCTAssertGreaterThan(right.offsetXFrac, 0, "yaw right rides the face right")
        XCTAssertLessThan(right.scaleX, 1, "eye spacing foreshortens with yaw")
        XCTAssertEqual(right.offsetYFrac, 0, accuracy: 0.0001)

        let left = WarawaraTurnGeometry.faceTransform(yawDegrees: -20, pitchDegrees: 0)
        XCTAssertLessThan(left.offsetXFrac, 0)
        XCTAssertEqual(left.scaleX, right.scaleX, accuracy: 0.0001, "foreshortening is symmetric")

        let up = WarawaraTurnGeometry.faceTransform(yawDegrees: 0, pitchDegrees: 8)
        XCTAssertLessThan(up.offsetYFrac, 0, "pitch up must move the face up on screen")
        let down = WarawaraTurnGeometry.faceTransform(yawDegrees: 0, pitchDegrees: -8)
        XCTAssertGreaterThan(down.offsetYFrac, 0)
    }

    func testFaceRidesTheNearSideBeyondEyeLocalGaze() {
        let renderSize = CGSize(width: 143.9, height: 143.9)
        let face = WarawaraTurnGeometry.faceTransform(yawDegrees: 25, pitchDegrees: 0)
        let faceOffsetX = face.offsetXFrac * renderSize.width
        let eyeLocal = WarawaraLayeredGeometry.gazeOffset(
            axis: .x, gaze: 1, range: 0.012, renderSize: renderSize
        )
        XCTAssertGreaterThan(faceOffsetX, eyeLocal, "shared face motion must exceed eye-local gaze")
    }

    func testPitchAddsSubtleShearAndForeshortening() {
        let strips = WarawaraTurnGeometry.strips(
            count: 14, canvasSize: canvas, bodyBounds: bodyBounds,
            yawDegrees: 0, pitchDegrees: 10
        )
        XCTAssertLessThan(strips.first!.destination.height, strips.first!.source.height)
        XCTAssertNotEqual(
            strips.first!.destination.minY, strips.last!.destination.minY,
            "pitch shear must differentiate top/bottom edges"
        )
    }

    func testShadeStrengthGrowsWithYawAndIsZeroNearNeutral() {
        XCTAssertEqual(WarawaraTurnGeometry.shadeStrength(yawDegrees: 0), 0, accuracy: 0.001)
        XCTAssertEqual(WarawaraTurnGeometry.shadeStrength(yawDegrees: 3), 0, accuracy: 0.001)
        let half = WarawaraTurnGeometry.shadeStrength(yawDegrees: 15)
        let full = WarawaraTurnGeometry.shadeStrength(yawDegrees: 25)
        XCTAssertGreaterThan(full, half)
        XCTAssertLessThanOrEqual(full, 0.12)
    }

    func testStripShadeIsInBodyVolumeOnlyAndSymmetric() {
        // Zero at neutral; bounded by the global strength; strongest at
        // the far edge and fading to the near edge; mirrored for the
        // opposite turn direction.
        for i in 0..<14 {
            XCTAssertEqual(
                WarawaraTurnGeometry.stripShade(at: i, count: 14, yawDegrees: 0),
                0, accuracy: 0.0001
            )
        }
        let right = (0..<14).map { WarawaraTurnGeometry.stripShade(at: $0, count: 14, yawDegrees: 25) }
        let left = (0..<14).map { WarawaraTurnGeometry.stripShade(at: $0, count: 14, yawDegrees: -25) }
        let strength = WarawaraTurnGeometry.shadeStrength(yawDegrees: 25)
        for i in 0..<14 {
            XCTAssertLessThanOrEqual(right[i], strength + 0.0001)
            XCTAssertGreaterThanOrEqual(right[i], 0)
            XCTAssertEqual(right[i], left[13 - i], accuracy: 0.0001,
                           "strip shading must mirror with the turn")
        }
        // Monotonic falloff from the far (left) edge to the near side.
        for i in 1..<14 {
            XCTAssertLessThanOrEqual(right[i], right[i - 1] + 0.0001)
        }
        // The far-edge strip is shaded, the near-edge strip is (nearly) not.
        XCTAssertGreaterThan(right[0], right[13])
        XCTAssertLessThan(right[13], 0.01)
    }
}
