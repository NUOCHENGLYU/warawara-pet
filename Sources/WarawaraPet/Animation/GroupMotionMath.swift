import Foundation

/// Pure, deterministic motion math for the companion group sequence.
/// All functions clamp their inputs; nothing here touches AppKit.
enum GroupMotionMath {
    private static func smoothstep(_ x: CGFloat) -> CGFloat {
        x * x * (3 - 2 * x)
    }

    private static func clamped(_ t: CGFloat) -> CGFloat {
        min(max(t, 0), 1)
    }

    /// Spawn position: main-pet center plus the companion's spawn offset,
    /// kept fully inside the visible frame (with margin) so companions
    /// never appear off-screen.
    static func spawnPosition(
        mainCenter: CGPoint,
        offset: CGVector,
        visibleFrame: CGRect,
        margin: CGFloat
    ) -> CGPoint {
        let desired = CGPoint(x: mainCenter.x + offset.dx, y: mainCenter.y + offset.dy)
        let x = min(max(desired.x, visibleFrame.minX + margin), visibleFrame.maxX - margin)
        let y = min(max(desired.y, visibleFrame.minY + margin), visibleFrame.maxY - margin)
        return CGPoint(x: x, y: y)
    }

    /// Gather interpolation: eased travel from spawn to the loose gather
    /// point around the main pet. t = 0 -> spawn, t = 1 -> gather.
    static func gatherPosition(
        at t: CGFloat,
        from spawn: CGPoint,
        to gather: CGPoint
    ) -> CGPoint {
        let eased = smoothstep(clamped(t))
        return CGPoint(
            x: spawn.x + (gather.x - spawn.x) * eased,
            y: spawn.y + (gather.y - spawn.y) * eased
        )
    }

    /// Gentle bobbing + small horizontal drift during the hover phase.
    /// Phase offsets come from the companion config so no two companions
    /// move identically.
    static func hoverOffset(
        at elapsed: TimeInterval,
        config: CompanionConfig,
        tuning: GroupTuning
    ) -> CGVector {
        let bob = tuning.hoverBobAmplitude
            * sin(2 * .pi * CGFloat(elapsed) / CGFloat(tuning.hoverBobPeriod) + config.bobPhase)
        let drift = tuning.hoverDriftAmplitude
            * sin(2 * .pi * CGFloat(elapsed) / (2 * CGFloat(tuning.hoverBobPeriod)) + config.driftPhase)
        return CGVector(dx: drift, dy: bob)
    }

    /// Ascent: slow initial rise with gentle acceleration plus continued
    /// subtle bobbing and slight horizontal wander. Returns the offset from
    /// the companion's gather position.
    static func ascentOffset(
        at elapsed: TimeInterval,
        config: CompanionConfig,
        tuning: GroupTuning
    ) -> CGVector {
        let e = CGFloat(max(elapsed, 0))
        let rise = tuning.ascentBaseSpeed * e + 0.5 * tuning.ascentAcceleration * e * e
        let bob = tuning.hoverBobAmplitude * 0.7
            * sin(2 * .pi * e / CGFloat(tuning.hoverBobPeriod) + config.bobPhase)
        let wander = tuning.ascentWanderAmplitude
            * sin(0.9 * e + config.driftPhase)
        return CGVector(dx: wander, dy: rise + bob)
    }

    /// Fade-in for the staggered appearance: 0 before the delay, 1 after
    /// delay + duration, clamped in between.
    static func appearAlpha(
        at elapsed: TimeInterval,
        delay: TimeInterval,
        duration: TimeInterval
    ) -> CGFloat {
        let local = elapsed - delay
        guard local > 0 else { return 0 }
        return clamped(CGFloat(local / max(duration, 0.001)))
    }

    /// Fade-out used for cancellation and the finishing phase: 1 -> 0.
    static func fadeAlpha(at elapsed: TimeInterval, duration: TimeInterval) -> CGFloat {
        let t = clamped(CGFloat(elapsed / max(duration, 0.001)))
        return 1 - smoothstep(t)
    }

    /// Total duration of the appearance phase (last companion fully faded
    /// in) for a given set of configs.
    static func appearPhaseDuration(
        configs: [CompanionConfig],
        fadeDuration: TimeInterval
    ) -> TimeInterval {
        (configs.map(\.appearDelay).max() ?? 0) + fadeDuration
    }
}
