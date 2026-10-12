import Foundation

/// Velocity-responsive soft-body pose for companions, reusing the
/// existing PetDeformation type. Companions are never grabbed, so there
/// is no grab anchor: deformation derives purely from smoothed velocity
/// (directional stretch, perpendicular compression, gentle lean). The
/// time-aware filter makes the response smooth across frames, phase
/// transitions, and irregular frame intervals.
struct CompanionPoseEstimator {
    var tuning: GroupTuning

    private(set) var pose: PetDeformation = .neutral
    private var smoothedVelocity = CGVector.zero
    private var lastTimestamp: TimeInterval?

    init(tuning: GroupTuning = .default) {
        self.tuning = tuning
    }

    mutating func update(velocity: CGVector, at timestamp: TimeInterval) {
        if let last = lastTimestamp {
            let gap = timestamp - last
            if gap > 0, gap < tuning.poseMaxGapDuration {
                let alpha = CGFloat(1 - exp(-gap / tuning.poseTimeConstant))
                smoothedVelocity.dx += alpha * (velocity.dx - smoothedVelocity.dx)
                smoothedVelocity.dy += alpha * (velocity.dy - smoothedVelocity.dy)
            } else if gap >= tuning.poseMaxGapDuration {
                let decay = CGFloat(exp(-gap / tuning.poseTimeConstant))
                smoothedVelocity.dx *= decay
                smoothedVelocity.dy *= decay
            }
        }
        lastTimestamp = timestamp
        pose = Self.pose(forVelocity: smoothedVelocity, tuning: tuning)
    }

    static func pose(forVelocity velocity: CGVector, tuning: GroupTuning) -> PetDeformation {
        let speed = hypot(velocity.dx, velocity.dy)
        let usable = max(speed - tuning.poseMinSpeed, 0)
        let range = max(tuning.poseVelocityAtMax - tuning.poseMinSpeed, 1)
        let amount = min(usable / range, 1) * tuning.poseMaxStretch
        guard amount > 0.001 else { return .neutral }

        let angle = DeformationMath.canonicalStretchAngle(atan2(velocity.dy, velocity.dx))
        let stretchScale = 1 + amount
        let lean = tuning.poseMaxLean * (speed / max(tuning.poseVelocityAtMax, 1))
        let rotation = min(
            max(-velocity.dx * lean / max(speed, 1), -tuning.poseMaxLean),
            tuning.poseMaxLean
        )
        return PetDeformation(
            stretchAngle: angle,
            stretchScale: stretchScale,
            perpendicularScale: 1 / stretchScale,
            rotation: rotation,
            anchor: .zero
        )
    }

    /// Subtle breathing used while hovering (and gentle phases): a small
    /// scale multiplier around 1.
    static func breathingScale(
        at elapsed: TimeInterval,
        config: CompanionConfig,
        tuning: GroupTuning
    ) -> CGFloat {
        1 + 0.02 * sin(2 * .pi * CGFloat(elapsed) / CGFloat(tuning.poseBreathingPeriod) + config.bobPhase)
    }

    mutating func reset() {
        pose = .neutral
        smoothedVelocity = .zero
        lastTimestamp = nil
    }
}
