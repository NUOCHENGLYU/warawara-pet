import Foundation

/// Subtle "noticing the cursor" pose, expressed through the existing
/// PetDeformation type (no second deformation system).
enum CuriosityPoseMath {
    static func pose(
        direction: CGVector,
        dwellProgress: CGFloat,
        tuning: PersonalityTuning
    ) -> PetDeformation {
        let progress = min(max(dwellProgress, 0), 1)
        guard progress > 0 else { return .neutral }
        let magnitude = min(hypot(direction.dx, direction.dy), 1)
        guard magnitude > 0.001 else { return .neutral }

        let angle = DeformationMath.canonicalStretchAngle(atan2(direction.dy, direction.dx))
        let stretchScale = 1 + tuning.curiosityMaxStretch * progress * magnitude
        // Lean using the horizontal component only: continuous across the
        // atan2 wrap and zero when the cursor is straight above/below.
        let rotation = min(
            max(-direction.dx * tuning.curiosityMaxRotation * magnitude,
                -tuning.curiosityMaxRotation),
            tuning.curiosityMaxRotation
        )
        return PetDeformation(
            stretchAngle: angle,
            stretchScale: stretchScale,
            perpendicularScale: 1 / stretchScale,
            rotation: rotation,
            anchor: .zero
        )
    }

    /// Zeroes tiny direction components so a stationary cursor produces
    /// exactly no gaze drift (pure helper, used by the gaze publish only).
    static func deadbanded(_ direction: CGVector, threshold: CGFloat) -> CGVector {
        let magnitude = hypot(direction.dx, direction.dy)
        guard magnitude > threshold else { return .zero }
        return direction
    }
}

/// Time-aware smoothing of the cursor direction into the curiosity pose.
struct CuriosityPoseEstimator {
    var tuning: PersonalityTuning

    private(set) var pose: PetDeformation = .neutral
    /// Smoothed signed cursor direction (-1...1 each axis); consumed by
    /// the layered expression system for continuous gaze.
    private(set) var direction: CGVector = .zero
    private var smoothedDirection = CGVector.zero
    private var lastTimestamp: TimeInterval?

    init(tuning: PersonalityTuning = .default) {
        self.tuning = tuning
    }

    mutating func update(direction: CGVector, dwellProgress: CGFloat, at timestamp: TimeInterval) {
        guard let last = lastTimestamp else {
            lastTimestamp = timestamp
            return
        }
        let dt = timestamp - last
        lastTimestamp = timestamp
        if dt > 0, dt < 1 {
            let alpha = CGFloat(1 - exp(-dt / tuning.curiositySmoothingTimeConstant))
            smoothedDirection.dx += alpha * (direction.dx - smoothedDirection.dx)
            smoothedDirection.dy += alpha * (direction.dy - smoothedDirection.dy)
        } else if dt >= 1 {
            // Long gap between samples: re-anchor instead of spiking.
            smoothedDirection = direction
        }
        self.direction = smoothedDirection
        pose = CuriosityPoseMath.pose(
            direction: smoothedDirection,
            dwellProgress: dwellProgress,
            tuning: tuning
        )
    }

    mutating func reset() {
        pose = .neutral
        direction = .zero
        smoothedDirection = .zero
        lastTimestamp = nil
    }
}
