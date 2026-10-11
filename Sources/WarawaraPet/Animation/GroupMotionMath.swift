import Foundation

/// Second-order (spring/damper) kinematic state: position + velocity,
/// integrated semi-implicitly with time-step awareness. This gives
/// companions visible inertia — soft acceleration, natural overshoot, and
/// a gentle settle — instead of sticker-like linear translation.
struct CompanionKinematics: Equatable {
    var position: CGPoint
    var velocity: CGVector

    /// Clamp dt so large frame gaps cannot destabilize the integration.
    static let maxStep: TimeInterval = 1.0 / 15.0

    mutating func step(
        toward target: CGPoint,
        dt: TimeInterval,
        springStrength: CGFloat,
        damping: CGFloat
    ) {
        let h = CGFloat(min(max(dt, 0.0005), Self.maxStep))
        let ax = springStrength * (target.x - position.x) - damping * velocity.dx
        let ay = springStrength * (target.y - position.y) - damping * velocity.dy
        velocity.dx += ax * h
        velocity.dy += ay * h
        position.x += velocity.dx * h
        position.y += velocity.dy * h
    }

    var speed: CGFloat {
        hypot(velocity.dx, velocity.dy)
    }

    func distance(to point: CGPoint) -> CGFloat {
        hypot(position.x - point.x, position.y - point.y)
    }
}

/// Pure, deterministic motion math for the companion group sequence.
/// All functions clamp their inputs; nothing here touches AppKit.
enum GroupMotionMath {
    private static func smoothstep(_ x: CGFloat) -> CGFloat {
        x * x * (3 - 2 * x)
    }

    private static func clamped(_ t: CGFloat) -> CGFloat {
        min(max(t, 0), 1)
    }

    // MARK: - Spawn

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

    /// Clamp an exit-target offset so the fan-out destination stays within
    /// the screen horizontally (companions exit through the TOP, so the
    /// vertical rise is never clamped).
    static func clampExitOffset(
        mainCenter: CGPoint,
        offset: CGVector,
        visibleFrame: CGRect,
        sideMargin: CGFloat
    ) -> CGVector {
        let targetX = mainCenter.x + offset.dx
        let minX = visibleFrame.minX - sideMargin
        let maxX = visibleFrame.maxX + sideMargin
        let clampedX = min(max(targetX, minX), maxX)
        return CGVector(dx: clampedX - mainCenter.x, dy: offset.dy)
    }

    // MARK: - Formation slots

    /// Generates stable, loose, screen-aware formation offsets around the
    /// main pet: a jittered ring around the main center, clamped into the
    /// visible frame, then relaxed with a few rounds of pairwise
    /// separation so bodies never collapse onto each other or onto the
    /// main pet.
    static func formationOffsets(
        count: Int,
        mainCenter: CGPoint,
        visibleFrame: CGRect,
        using rng: inout some RandomSource,
        tuning: GroupTuning
    ) -> [CGVector] {
        guard count > 0 else { return [] }

        func clampIntoFormationArea(_ point: CGPoint) -> CGPoint {
            let minX = visibleFrame.minX + tuning.formationMargin
            let maxX = visibleFrame.maxX - tuning.formationMargin
            let minY = visibleFrame.minY + tuning.formationMargin
            let maxY = visibleFrame.maxY - tuning.formationMargin
            return CGPoint(
                x: min(max(point.x, minX), maxX),
                y: min(max(point.y, minY), maxY)
            )
        }

        var positions: [CGPoint] = (0..<count).map { index in
            let goldenAngle: CGFloat = 2.399963229728653
            let angle = CGFloat(index) * goldenAngle
                + RandomBounds.randomCGFloat(in: -0.25...0.25, using: &rng)
            let radius = tuning.formationRadius
                + RandomBounds.randomCGFloat(
                    in: -tuning.formationRadiusVariation...tuning.formationRadiusVariation,
                    using: &rng
                )
            let candidate = CGPoint(
                x: mainCenter.x + cos(angle) * radius,
                y: mainCenter.y + sin(angle) * radius * 0.8
            )
            return clampIntoFormationArea(candidate)
        }

        // Separation relaxation: pairwise spacing plus a repulsor at the
        // main pet center so companions keep their distance from it.
        for _ in 0..<6 {
            positions = relaxSpacing(
                positions: positions,
                minSpacing: tuning.companionMinSpacing,
                strength: tuning.separationStrength,
                origin: mainCenter,
                originMinRadius: tuning.preferredMainPetRadius
            )
            positions = positions.map(clampIntoFormationArea)
        }

        return positions.map { CGVector(dx: $0.x - mainCenter.x, dy: $0.y - mainCenter.y) }
    }

    /// One round of separation on a set of points: points closer than
    /// `minSpacing` are pushed apart smoothly along the connecting line,
    /// and points closer than `originMinRadius` to `origin` (the main pet
    /// center) are pushed outward so companions never sit on the pet.
    static func relaxSpacing(
        positions: [CGPoint],
        minSpacing: CGFloat,
        strength: CGFloat,
        origin: CGPoint,
        originMinRadius: CGFloat
    ) -> [CGPoint] {
        var result = positions
        for i in 0..<result.count {
            // Repulsion from the main pet center.
            let ox = result[i].x - origin.x
            let oy = result[i].y - origin.y
            let originDistance = hypot(ox, oy)
            if originDistance > 0.0001, originDistance < originMinRadius {
                let push = (originMinRadius - originDistance) * strength
                result[i].x += ox / originDistance * push
                result[i].y += oy / originDistance * push
            }
            // Pairwise repulsion.
            for j in (i + 1)..<result.count {
                let dx = result[j].x - result[i].x
                let dy = result[j].y - result[i].y
                let distance = hypot(dx, dy)
                guard distance > 0.0001, distance < minSpacing else { continue }
                let overlap = (minSpacing - distance) * strength * 0.5
                let ux = dx / distance
                let uy = dy / distance
                result[i].x -= ux * overlap
                result[i].y -= uy * overlap
                result[j].x += ux * overlap
                result[j].y += uy * overlap
            }
        }
        return result
    }

    /// Separation-adjusted targets for live motion: companions closer than
    /// `minSpacing` push their TARGETS apart so the spring moves them
    /// apart smoothly (no hard snapping).
    static func separationAdjustedTargets(
        positions: [CGPoint],
        targets: [CGPoint],
        minSpacing: CGFloat,
        strength: CGFloat
    ) -> [CGPoint] {
        guard positions.count == targets.count else { return targets }
        var result = targets
        for i in 0..<positions.count {
            for j in (i + 1)..<positions.count {
                let dx = positions[j].x - positions[i].x
                let dy = positions[j].y - positions[i].y
                let distance = hypot(dx, dy)
                guard distance > 0.0001, distance < minSpacing else { continue }
                let overlap = (minSpacing - distance) * strength * 0.5
                let ux = dx / distance
                let uy = dy / distance
                result[i].x -= ux * overlap
                result[i].y -= uy * overlap
                result[j].x += ux * overlap
                result[j].y += uy * overlap
            }
        }
        return result
    }

    // MARK: - Hover (position-continuous with gathering)

    /// Hover offset around a captured base position. Zero at t = 0 (the
    /// bob ramps in smoothly), so the gather -> hover transition is
    /// exactly position-continuous.
    static func hoverOffset(
        at elapsed: TimeInterval,
        rampInDuration: TimeInterval,
        config: CompanionConfig,
        tuning: GroupTuning
    ) -> CGVector {
        let e = CGFloat(max(elapsed, 0))
        let ramp = smoothstep(clamped(e / CGFloat(max(rampInDuration, 0.001))))
        let bob = tuning.hoverBobAmplitude * ramp
            * sin(2 * .pi * e / CGFloat(tuning.hoverBobPeriod) + config.bobPhase)
        let drift = tuning.hoverDriftAmplitude * ramp
            * sin(2 * .pi * e / (2 * CGFloat(tuning.hoverBobPeriod)) + config.driftPhase)
        return CGVector(dx: drift, dy: bob)
    }

    // MARK: - Ascent (fan-out, position-continuous with hover)

    /// Horizontal sway during ascent; zero at t = 0.
    static func ascentSway(
        at elapsed: TimeInterval,
        config: CompanionConfig,
        tuning: GroupTuning
    ) -> CGFloat {
        let e = CGFloat(max(elapsed, 0))
        let ramp = smoothstep(clamped(e / 1.2))
        return tuning.ascentSwayAmplitude * ramp
            * sin(2 * .pi * e / CGFloat(tuning.ascentSwayPeriod) + config.driftPhase)
    }

    /// Exit predicates: each companion leaves independently once its own
    /// top edge passes the fade zone / fully leaves the screen.
    static func isAboveExitFadeZone(
        panelTopY: CGFloat,
        visibleFrame: CGRect,
        margin: CGFloat
    ) -> Bool {
        panelTopY > visibleFrame.maxY - margin
    }

    static func isFullyAboveScreen(
        panelTopY: CGFloat,
        visibleFrame: CGRect,
        margin: CGFloat
    ) -> Bool {
        panelTopY > visibleFrame.maxY + margin
    }

    // MARK: - Fades

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

    /// Fade-out (cancellation, finishing, and per-companion exit): 1 -> 0.
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
