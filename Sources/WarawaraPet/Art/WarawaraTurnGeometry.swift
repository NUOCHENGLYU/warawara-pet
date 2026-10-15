import Foundation

/// Pure, deterministic math for the 2.5D body turn. The illusion comes
/// from a perspective-aware redistribution of horizontal volume: the
/// body raster is drawn in vertical strips whose widths follow a smooth
/// profile (near side expands, far side compresses) while the total
/// width is preserved, plus a coordinated facial remap derived from the
/// SAME yaw/pitch parameters. Zero angle is exactly the identity, so
/// the accepted frontal artwork renders pixel-identically.
enum WarawaraTurnGeometry {
    static let maxYawDegrees: CGFloat = 25
    static let maxPitchDegrees: CGFloat = 10

    /// Stable fallback switch (launch argument `--no-2d5-turn`): forces
    /// yaw/pitch to zero everywhere, keeping the accepted gaze/face
    /// behavior without the experimental 2.5D warp.
    static var turnDisabled = false

    static func clampedYaw(_ degrees: CGFloat) -> CGFloat {
        min(max(degrees, -maxYawDegrees), maxYawDegrees)
    }

    static func clampedPitch(_ degrees: CGFloat) -> CGFloat {
        min(max(degrees, -maxPitchDegrees), maxPitchDegrees)
    }

    /// The turn pipeline is active only beyond a tiny threshold, so the
    /// zero-angle rendering path stays exactly the accepted one.
    static func isActive(yawDegrees: CGFloat, pitchDegrees: CGFloat) -> Bool {
        abs(yawDegrees) > 0.5 || abs(pitchDegrees) > 0.5
    }

    /// One vertical strip of the body image and its warped destination.
    struct Strip: Equatable {
        let source: CGRect
        let destination: CGRect
    }

    /// Warp strip layout over the body bounds. Strip widths follow
    /// w(u) = w0 x (1 + k x yawFrac x u) with u in [-1, 1] across the
    /// body; the integral over u is zero, so the total body width is
    /// preserved at every angle (only the distribution changes). For
    /// yaw > 0 (turning right) the right side widens and the left side
    /// narrows. Pitch adds a tiny linear shear and a slight vertical
    /// foreshortening.
    static func strips(
        count: Int,
        canvasSize: CGSize,
        bodyBounds: CGRect,
        yawDegrees: CGFloat,
        pitchDegrees: CGFloat
    ) -> [Strip] {
        let yaw = clampedYaw(yawDegrees)
        let pitch = clampedPitch(pitchDegrees)
        let yawFrac = yaw / maxYawDegrees
        let pitchFrac = pitch / maxPitchDegrees
        let bodyRect = CGRect(
            x: bodyBounds.minX * canvasSize.width,
            y: bodyBounds.minY * canvasSize.height,
            width: bodyBounds.width * canvasSize.width,
            height: bodyBounds.height * canvasSize.height
        )
        let stripCount = max(count, 2)
        let baseWidth = bodyRect.width / CGFloat(stripCount)
        let widthK: CGFloat = 0.55
        let shear: CGFloat = -0.015 * pitchFrac
        let heightScale = 1 - 0.02 * abs(pitchFrac)

        var result: [Strip] = []
        var xEdge = bodyRect.minX
        for i in 0..<stripCount {
            let u = (CGFloat(i) + 0.5) / CGFloat(stripCount) * 2 - 1
            let width = baseWidth * (1 + widthK * yawFrac * u)
            let stripHeight = bodyRect.height * heightScale
            let yOffset = shear * bodyRect.height * u
            let source = CGRect(
                x: bodyRect.minX + CGFloat(i) * baseWidth,
                y: bodyRect.minY,
                width: baseWidth,
                height: bodyRect.height
            )
            let destination = CGRect(
                x: xEdge,
                y: bodyRect.minY + (bodyRect.height - stripHeight) / 2 + yOffset,
                width: width,
                height: stripHeight
            )
            result.append(Strip(source: source, destination: destination))
            xEdge += width
        }
        return result
    }

    /// Affine remap of the shared facial frame (eyes + mouth together),
    /// derived from the same yaw/pitch. The face rides toward the near
    /// side and foreshortens horizontally (eye spacing narrows); pitch
    /// shifts the face up/down (screen-converted) and compresses it
    /// slightly. All face layers consume this ONE transform, so the
    /// facial registration can never disagree.
    struct FaceTransform: Equatable {
        /// Fractions of the render size.
        var offsetXFrac: CGFloat
        var offsetYFrac: CGFloat
        var scaleX: CGFloat
        var scaleY: CGFloat

        static let identity = FaceTransform(offsetXFrac: 0, offsetYFrac: 0, scaleX: 1, scaleY: 1)

        func offset(in renderSize: CGSize) -> CGSize {
            CGSize(
                width: offsetXFrac * renderSize.width,
                height: offsetYFrac * renderSize.height
            )
        }

        func isIdentity(_ epsilon: CGFloat = 0.0005) -> Bool {
            abs(offsetXFrac) < epsilon && abs(offsetYFrac) < epsilon
                && abs(scaleX - 1) < epsilon && abs(scaleY - 1) < epsilon
        }
    }

    static func faceTransform(
        yawDegrees: CGFloat,
        pitchDegrees: CGFloat
    ) -> FaceTransform {
        let yaw = clampedYaw(yawDegrees)
        let pitch = clampedPitch(pitchDegrees)
        let yawFrac = yaw / maxYawDegrees
        let pitchFrac = pitch / maxPitchDegrees
        let scaleX = max(cos(yaw * .pi / 180), 0.86)
        return FaceTransform(
            offsetXFrac: yawFrac * 0.035,
            offsetYFrac: -pitchFrac * 0.02,
            scaleX: scaleX,
            scaleY: 1 - 0.03 * abs(pitchFrac)
        )
    }

    /// Far-side shading strength (0...1). Grows with |yaw|; zero at
    /// neutral so the accepted look is untouched.
    static func shadeStrength(yawDegrees: CGFloat) -> CGFloat {
        let yawFrac = abs(clampedYaw(yawDegrees)) / maxYawDegrees
        let t = max((yawFrac - 0.15) / 0.85, 0)
        return t * t * (3 - 2 * t) * 0.11
    }

    /// Per-strip volume shading: strongest at the far-side edge, fading
    /// smoothly to zero at the near-side edge. Zero at neutral. This is
    /// INTENTIONAL in-body volume shading — never a window shadow.
    static func stripShade(at index: Int, count: Int, yawDegrees: CGFloat) -> CGFloat {
        let strength = shadeStrength(yawDegrees: yawDegrees)
        guard strength > 0.001 else { return 0 }
        let u = (CGFloat(index) + 0.5) / CGFloat(max(count, 2)) * 2 - 1
        // Far side depends on the turn direction; near side stays bright.
        let falloff: CGFloat = yawDegrees >= 0 ? (1 - u) / 2 : (1 + u) / 2
        let eased = falloff * falloff * (3 - 2 * falloff)
        return strength * eased
    }
}
