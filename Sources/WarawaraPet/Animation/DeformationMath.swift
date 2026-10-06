import Foundation

/// Pure, deterministic mapping from (smoothed) drag velocity and grab
/// vector to a visual deformation. No physics simulation.
///
/// Coordinate conventions:
/// - velocity: screen/global coordinates, +x right, +y up
/// - grab vector: pet space (same orientation as screen), normalized by
///   half the window extent and clamped
/// - rotation: CCW positive; torque = cross(grab, velocity)
enum DeformationMath {
    static func deformation(
        forVelocity velocity: CGVector,
        grabVector: CGVector,
        tuning: DeformationTuning
    ) -> PetDeformation {
        let clampedGrab = clampedGrabVector(grabVector, tuning: tuning)
        let speed = hypot(velocity.dx, velocity.dy)
        let amount = stretchAmount(forSpeed: speed, tuning: tuning)
        guard amount > 0 else {
            return PetDeformation(
                stretchAngle: 0,
                stretchScale: 1,
                perpendicularScale: 1,
                rotation: 0,
                anchor: clampedGrab
            )
        }

        let stretchScale = 1 + amount
        let perpendicularScale = perpendicularScale(forStretchScale: stretchScale)
        let stretchAngle = canonicalStretchAngle(atan2(velocity.dy, velocity.dx))
        let tau = torque(grabVector: clampedGrab, velocity: velocity)
        let rotation = rotationAmount(forTorque: tau, tuning: tuning)

        return PetDeformation(
            stretchAngle: stretchAngle,
            stretchScale: stretchScale,
            perpendicularScale: perpendicularScale,
            rotation: rotation,
            anchor: clampedGrab
        )
    }

    static func stretchAmount(forSpeed speed: CGFloat, tuning: DeformationTuning) -> CGFloat {
        let usable = max(0, speed - tuning.minimumSpeed)
        let range = max(tuning.velocityAtMaxStretch - tuning.minimumSpeed, 1)
        return min(usable / range, 1) * tuning.maxStretch
    }

    /// Exact volume preservation: (1 + s) * (1 / (1 + s)) == 1.
    static func perpendicularScale(forStretchScale stretchScale: CGFloat) -> CGFloat {
        1 / stretchScale
    }

    /// Maps an angle to the undirected-axis range [0, .pi). Because scaling
    /// along a line is symmetric, an axis at `angle` and `angle + .pi` is
    /// the same axis, and the composed transform (rotate, scale, rotate
    /// back) is .pi-periodic, so the wrap boundary is visually seamless.
    static func canonicalStretchAngle(_ angle: CGFloat) -> CGFloat {
        var canonical = angle
        while canonical < 0 { canonical += .pi }
        while canonical >= .pi { canonical -= .pi }
        return canonical
    }

    static func torque(grabVector: CGVector, velocity: CGVector) -> CGFloat {
        grabVector.dx * velocity.dy - grabVector.dy * velocity.dx
    }

    static func rotationAmount(forTorque torque: CGFloat, tuning: DeformationTuning) -> CGFloat {
        min(max(torque * tuning.rotationGain, -tuning.maxRotation), tuning.maxRotation)
    }

    static func clampedGrabVector(_ grab: CGVector, tuning: DeformationTuning) -> CGVector {
        let limit = tuning.grabAnchorLimit
        return CGVector(
            dx: min(max(grab.dx, -limit), limit),
            dy: min(max(grab.dy, -limit), limit)
        )
    }
}
