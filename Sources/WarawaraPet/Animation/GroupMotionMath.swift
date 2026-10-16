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

    // MARK: - Entry (from outside the physical screen)

    /// Chooses a screen-aware entry edge: 0 = left, 1 = right, 2 = bottom.
    /// When the main pet sits near an edge, that edge is avoided so
    /// companions do not appear "behind" the pet's side of the display.
    static func entryEdge(
        index: Int,
        count: Int,
        mainCenter: CGPoint,
        physicalFrame: CGRect,
        using rng: inout some RandomSource,
        tuning: GroupTuning
    ) -> Int {
        var edges: [Int] = [0, 1, 2]
        let leftZone = physicalFrame.minX + physicalFrame.width * 0.35
        let rightZone = physicalFrame.maxX - physicalFrame.width * 0.35
        if mainCenter.x < leftZone { edges.removeAll { $0 == 0 } }
        if mainCenter.x > rightZone { edges.removeAll { $0 == 1 } }
        guard !edges.isEmpty else { return index % 3 }
        let chosen = edges[index % edges.count]
        if rng.nextUnit() < 0.25, edges.count > 1 {
            return edges[Int(rng.nextUnit() * Double(edges.count)) % edges.count]
        }
        return chosen
    }

    /// An entry position whose entire panel body lies outside the physical
    /// screen frame, along the chosen edge and vertically near the main
    /// pet's row (left/right) or below it (bottom).
    static func entryPosition(
        edge: Int,
        mainCenter: CGPoint,
        physicalFrame: CGRect,
        panelSize: CGFloat,
        using rng: inout some RandomSource,
        tuning: GroupTuning
    ) -> CGPoint {
        let jitter = RandomBounds.randomCGFloat(in: tuning.entryJitterRange, using: &rng)
        let half = panelSize / 2 + tuning.entryMargin
        switch edge {
        case 0: // left
            return CGPoint(
                x: physicalFrame.minX - half - jitter,
                y: mainCenter.y + (jitter - tuning.entryJitterRange.upperBound / 2) * 0.6
            )
        case 1: // right
            return CGPoint(
                x: physicalFrame.maxX + half + jitter,
                y: mainCenter.y + (jitter - tuning.entryJitterRange.upperBound / 2) * 0.6
            )
        default: // bottom
            return CGPoint(
                x: mainCenter.x + (jitter - tuning.entryJitterRange.upperBound / 2) * 0.8,
                y: physicalFrame.minY - half - jitter
            )
        }
    }

    /// True when the point lies strictly outside the given frame.
    static func isOutside(_ point: CGPoint, frame: CGRect) -> Bool {
        !frame.contains(point)
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

    /// Exit predicate: the companion's ENTIRE rendered body (panel inset
    /// by CompanionMetrics.padding) is above the chosen visible upper
    /// boundary (`topY`, normally `visibleFrame.maxY`), so the last
    /// visible pixel has left the desktop and the panel can be recycled.
    static func isFullyAboveTopEdge(
        panelFrame: CGRect,
        topY: CGFloat,
        margin: CGFloat
    ) -> Bool {
        let body = CompanionMetrics.bodyFrame(panelFrame: panelFrame)
        return body.minY >= topY + margin
    }

    /// Character-space exit predicate: the rendered body's BOTTOM (from
    /// the character's global center and scale) is above `topY`. This is
    /// the unified completion check for both the moving-panel ascent and
    /// the screen-contained viewport exit.
    static func isCharacterFullyAboveTopEdge(
        characterCenterY: CGFloat,
        scale: CGFloat,
        topY: CGFloat,
        margin: CGFloat
    ) -> Bool {
        let bodyBottom = characterCenterY - CompanionMetrics.blobHeight * scale / 2
        return bodyBottom > topY + margin
    }

    /// The screen-contained exit viewport: a fixed panel frame whose TOP
    /// edge coincides exactly with the visible desktop's upper boundary
    /// (`topY`). The panel stays inside the visible region; the character
    /// moves upward INSIDE it and is clipped by the panel's top edge.
    /// The horizontal origin is centered on the character and clamped
    /// into the visible frame (near side edges the viewport shifts but
    /// the character position is preserved via the local offset).
    static func exitViewportFrame(
        characterCenter: CGPoint,
        topY: CGFloat,
        visibleFrame: CGRect,
        tuning: GroupTuning
    ) -> CGRect {
        let width = tuning.exitViewportWidth
        let height = tuning.exitViewportHeight
        let minX = visibleFrame.minX
        let maxX = max(visibleFrame.minX, visibleFrame.maxX - width)
        let x = min(max(characterCenter.x - width / 2, minX), maxX)
        return CGRect(x: x, y: topY - height, width: width, height: height)
    }

    /// The character's local offset from the viewport's center (AppKit
    /// orientation: +x right, +y up). Handoff preserves the character's
    /// exact global position: viewportCenter + offset == characterCenter.
    static func localOffset(characterCenter: CGPoint, viewportFrame: CGRect) -> CGVector {
        CGVector(
            dx: characterCenter.x - viewportFrame.midX,
            dy: characterCenter.y - viewportFrame.midY
        )
    }

    /// Fraction of the rendered body that has passed above `topY`:
    /// 0 = fully visible, 1 = fully beyond. Used to verify the staged
    /// partial-body exit.
    static func fractionAboveTopEdge(panelFrame: CGRect, topY: CGFloat) -> CGFloat {
        let body = CompanionMetrics.bodyFrame(panelFrame: panelFrame)
        let fraction = (body.maxY - topY) / max(body.height, 1)
        return min(max(fraction, 0), 1)
    }

    /// True when the companion's rendered body top is within the slow
    /// exit zone below the visible upper boundary: from here on it should
    /// move upward at a slow constant speed so the crossing is visibly
    /// staged.
    static func isInExitSlowZone(
        bodyTopY: CGFloat,
        topY: CGFloat,
        zoneHeight: CGFloat
    ) -> Bool {
        bodyTopY >= topY - zoneHeight
    }

    /// Continuous exit-velocity blend: eases the current vertical
    /// velocity toward the slow exit speed with an exponential time
    /// constant, so companions never experience a velocity jump when
    /// entering the top-edge slow zone ("ceiling hit").
    static func exitVelocityBlend(
        current: CGFloat,
        target: CGFloat,
        dt: TimeInterval,
        timeConstant: TimeInterval
    ) -> CGFloat {
        guard dt > 0, timeConstant > 0 else { return current }
        let blend = CGFloat(1 - exp(-dt / timeConstant))
        return current + blend * (target - current)
    }

    /// Continuous vertical hop/bob for the companion APPROACH motion:
    /// a springy sine bob whose intensity follows the current speed, so
    /// fast-approaching companions bounce lively and decelerating ones
    /// settle softly (no teleportation, no synchronized identical
    /// motion — the phase is per-companion).
    static func approachBob(
        speed: CGFloat,
        maxAmplitude: CGFloat,
        phase: CGFloat,
        time: TimeInterval,
        hopPeriod: TimeInterval
    ) -> CGFloat {
        guard speed > 1, maxAmplitude > 0 else { return 0 }
        let intensity = min(max(speed / 25, 0), 1)
        return sin(2 * .pi * (time / hopPeriod) + phase) * maxAmplitude * intensity
    }

    // MARK: - Fades

    /// Fade-out used only for user cancellation: 1 -> 0.
    static func fadeAlpha(at elapsed: TimeInterval, duration: TimeInterval) -> CGFloat {
        let t = clamped(CGFloat(elapsed / max(duration, 0.001)))
        return 1 - smoothstep(t)
    }

    /// Total duration of the staggered release (last companion begins
    /// moving) for a given set of configs.
    static func releasePhaseDuration(
        configs: [CompanionConfig],
        fadeDuration: TimeInterval = 0
    ) -> TimeInterval {
        (configs.map(\.releaseDelay).max() ?? 0) + fadeDuration
    }
}
