import Foundation

/// Time-aware smoothing of 2D drag velocity into a PetDeformation.
/// Pure and deterministic: the caller feeds (deltaX, deltaY, timestamp)
/// samples in global coordinates and reads `deformation`.
struct DragDeformationEstimator {
    var tuning: DeformationTuning

    private(set) var deformation: PetDeformation = .neutral
    private var smoothedVelocity = CGVector.zero
    private var grabVector = CGVector.zero
    private var lastTimestamp: TimeInterval?

    init(tuning: DeformationTuning = .default) {
        self.tuning = tuning
    }

    mutating func beginDrag(grabVector: CGVector) {
        deformation = .neutral
        smoothedVelocity = .zero
        lastTimestamp = nil
        self.grabVector = grabVector
    }

    mutating func update(deltaX: CGFloat, deltaY: CGFloat, at timestamp: TimeInterval) {
        guard let last = lastTimestamp else {
            lastTimestamp = timestamp
            return
        }
        let dt = timestamp - last
        lastTimestamp = timestamp
        guard dt > 0 else { return }

        if dt > tuning.maxGapDuration {
            // Long pause between events: treat as no movement and let the
            // velocity decay toward zero instead of spiking or freezing.
            let decay = CGFloat(exp(-dt / tuning.velocityTimeConstant))
            smoothedVelocity.dx *= decay
            smoothedVelocity.dy *= decay
        } else {
            let alpha = CGFloat(1 - exp(-dt / tuning.velocityTimeConstant))
            let velocityX = deltaX / CGFloat(dt)
            let velocityY = deltaY / CGFloat(dt)
            smoothedVelocity.dx += alpha * (velocityX - smoothedVelocity.dx)
            smoothedVelocity.dy += alpha * (velocityY - smoothedVelocity.dy)
        }

        // Both stretch and torque/rotation derive from the SMOOTHED
        // velocity; raw deltas never reach the deformation mapping.
        deformation = DeformationMath.deformation(
            forVelocity: smoothedVelocity,
            grabVector: grabVector,
            tuning: tuning
        )
    }

    mutating func reset() {
        deformation = .neutral
        smoothedVelocity = .zero
        lastTimestamp = nil
        grabVector = .zero
    }
}
