import Foundation

/// Time-aware smoothing of horizontal drag velocity into a bounded tilt
/// value. Pure and deterministic: the caller feeds (deltaX, timestamp)
/// samples and reads `tilt`. Parameters are tuned on a real Mac if needed.
struct TiltEstimator {
    /// Exponential smoothing time constant in seconds. Smaller = snappier.
    var timeConstant: TimeInterval = 0.12
    /// Gaps longer than this are treated as no-movement time: velocity
    /// decays toward zero instead of spiking or freezing.
    var maxGapDuration: TimeInterval = 1.0
    /// Hard clamp for the output tilt (radians).
    var maxTilt: CGFloat = 0.15
    /// Horizontal velocity (points/second) that produces exactly `maxTilt`.
    var velocityAtMaxTilt: CGFloat = 600

    private(set) var tilt: CGFloat = 0
    private var smoothedVelocityX: CGFloat = 0
    private var lastTimestamp: TimeInterval?

    mutating func update(deltaX: CGFloat, at timestamp: TimeInterval) {
        guard let last = lastTimestamp else {
            lastTimestamp = timestamp
            return
        }
        let dt = timestamp - last
        lastTimestamp = timestamp
        guard dt > 0 else { return }

        guard dt <= maxGapDuration else {
            let decay = CGFloat(exp(-dt / timeConstant))
            smoothedVelocityX *= decay
            tilt = tilt(forVelocityX: smoothedVelocityX)
            return
        }

        let velocity = deltaX / CGFloat(dt)
        let alpha = 1 - exp(-dt / timeConstant)
        smoothedVelocityX += CGFloat(alpha) * (velocity - smoothedVelocityX)
        tilt = tilt(forVelocityX: smoothedVelocityX)
    }

    func tilt(forVelocityX velocityX: CGFloat) -> CGFloat {
        let gain = maxTilt / velocityAtMaxTilt
        return min(max(velocityX * gain, -maxTilt), maxTilt)
    }

    mutating func reset() {
        tilt = 0
        smoothedVelocityX = 0
        lastTimestamp = nil
    }
}
