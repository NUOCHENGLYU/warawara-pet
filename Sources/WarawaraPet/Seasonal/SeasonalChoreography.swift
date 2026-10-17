import CoreGraphics
import Foundation

/// One production frame of a seasonal scene: the prop's world pose plus
/// which artwork layers are active. Pure value, produced deterministically
/// by `SeasonalChoreography` and applied by the presenter at ~30 Hz.
struct SeasonalPropPose: Equatable {
    /// World position of the prop's semantic CONTACT point (screen coords).
    var position: CGPoint = .zero
    var scale: CGFloat = 1
    var rotationDegrees: CGFloat = 0
    var alpha: CGFloat = 1
    /// Primary asset currently drawn.
    var asset: String = ""
    /// Gift lid lift 0...1 (drives offset + rotation of the lid layer).
    var lidLift: CGFloat = 0
    /// Hongbao note rise 0...1 (optional; unused while the static open
    /// artwork is drawn).
    var noteRise: CGFloat = 0
    /// Trail drawn BEHIND the plane (paper airplane only).
    var showTrail: Bool = false
    /// Imaginary drizzle (umbrella) or confetti (new year) overlay alpha.
    var effectAlpha: CGFloat = 0
    var effectAsset: String?
}

/// Deterministic per-kind choreography: entrances, interactions,
/// reactions, and retirements, all driven by phase-relative time. The
/// coordinator owns phase transitions; this owns the motion inside them.
enum SeasonalChoreography {

    static func pose(
        kind: SeasonalEventKind,
        phase: SeasonalPhase,
        elapsedInPhase: TimeInterval,
        totalElapsed: TimeInterval,
        anchors: EventAnchorSystem,
        visibleFrame: CGRect,
        timing: SeasonalTiming
    ) -> SeasonalPropPose {
        switch kind {
        case .cny:
            return cnyPose(phase: phase, elapsed: elapsedInPhase, anchors: anchors, timing: timing)
        case .christmas:
            return christmasPose(phase: phase, elapsed: elapsedInPhase, anchors: anchors, timing: timing)
        case .newYear:
            return newYearPose(phase: phase, elapsed: elapsedInPhase, anchors: anchors, timing: timing)
        case .umbrella:
            return umbrellaPose(phase: phase, elapsed: elapsedInPhase, anchors: anchors, timing: timing)
        case .hotCocoa:
            return cocoaPose(phase: phase, elapsed: elapsedInPhase, anchors: anchors, timing: timing)
        case .sprout:
            return sproutPose(phase: phase, elapsed: elapsedInPhase, anchors: anchors, timing: timing)
        case .paperAirplane:
            return airplanePose(phase: phase, elapsedInPhase: elapsedInPhase, totalElapsed: totalElapsed,
                                anchors: anchors, visibleFrame: visibleFrame, timing: timing)
        }
    }

    /// The world point the pet should look at for this frame (nil =
    /// release attention). Tracked every choreography tick.
    static func attentionTarget(
        kind: SeasonalEventKind,
        phase: SeasonalPhase,
        elapsedInPhase: TimeInterval,
        totalElapsed: TimeInterval,
        anchors: EventAnchorSystem,
        visibleFrame: CGRect,
        timing: SeasonalTiming
    ) -> CGPoint? {
        let pose = pose(
            kind: kind, phase: phase, elapsedInPhase: elapsedInPhase,
            totalElapsed: totalElapsed, anchors: anchors,
            visibleFrame: visibleFrame, timing: timing
        )
        guard phase != .depart else { return nil }
        guard pose.alpha > 0.02 else { return nil }
        return pose.position
    }

    // MARK: - CNY: descent, catch, hold, open, stow

    private static func cnyPose(
        phase: SeasonalPhase, elapsed: TimeInterval,
        anchors: EventAnchorSystem, timing: SeasonalTiming
    ) -> SeasonalPropPose {
        var pose = SeasonalPropPose()
        pose.asset = "cny_hongbao.png"
        switch phase {
        case .noticing, .idle, .completed, .cancelled:
            return pose
        case .approach:
            // Slow fall from above the head into the paws.
            let t = min(max(elapsed / timing.approachDuration, 0), 1)
            let eased = easeOut(t)
            let startY = anchors.aboveHead.y + 120
            let sway = sin(.pi * t * 2.4) * 10 * (1 - t)
            pose.position = CGPoint(
                x: anchors.handFront.x + sway,
                y: startY + (anchors.handFront.y - startY) * eased
            )
            pose.rotationDegrees = (1 - t) * -6
            pose.alpha = min(1, t * 6)
        case .present:
            // Held and inspected: gentle bob + tiny rock.
            let bob = sin(elapsed * 2.1) * 2.4
            let rock = sin(elapsed * 1.15) * 2.6
            pose.position = CGPoint(x: anchors.handFront.x, y: anchors.handFront.y + bob)
            pose.rotationDegrees = rock
        case .celebrate:
            // The flap opens: crossfade to the opened artwork after a
            // short anticipation beat.
            let openT = min(max((elapsed - 0.35) / 0.9, 0), 1)
            pose.asset = openT > 0 ? "cny_hongbao_open.png" : "cny_hongbao.png"
            // Held open with a tiny happy dip.
            let dip = openT > 0.5 ? -4 * sin((elapsed - 0.8) * 3) : 0
            pose.position = CGPoint(x: anchors.handFront.x, y: anchors.handFront.y + dip)
            pose.rotationDegrees = 0
        case .depart:
            // Stow: sink toward the paws and fade.
            let t = min(max(elapsed / timing.departDuration, 0), 1)
            pose.asset = "cny_hongbao_open.png"
            pose.position = CGPoint(
                x: anchors.handFront.x,
                y: anchors.handFront.y - 14 * t
            )
            pose.alpha = 1 - t
        }
        return pose
    }

    // MARK: - Christmas: appear, inspect, lid lift, delight, retire

    private static func christmasPose(
        phase: SeasonalPhase, elapsed: TimeInterval,
        anchors: EventAnchorSystem, timing: SeasonalTiming
    ) -> SeasonalPropPose {
        var pose = SeasonalPropPose()
        pose.asset = "xmas_gift.png"
        switch phase {
        case .noticing, .idle, .completed, .cancelled:
            return pose
        case .approach:
            // Materializes beside the pet: fade + soft scale-in.
            let t = min(max(elapsed / timing.approachDuration, 0), 1)
            pose.position = anchors.groundBesidePet
            pose.scale = 0.85 + 0.15 * easeOut(t)
            pose.alpha = min(1, t * 2.2)
        case .present:
            // Inspection: settles, then a small touch-rock on the ribbon.
            let t = min(max(elapsed / timing.presentDuration, 0), 1)
            pose.position = anchors.groundBesidePet
            let rock = t > 0.55 ? sin((t - 0.55) * 6) * 2.4 * (1 - t) * 2 : 0
            pose.rotationDegrees = rock
        case .celebrate:
            // The lid lifts from the open base on a believable hinge.
            let lift = min(max((elapsed - 0.15) / 1.1, 0), 1)
            let eased = easeInOut(lift)
            pose.asset = "xmas_gift_open_base.png"
            pose.lidLift = eased
            pose.position = anchors.groundBesidePet
        case .depart:
            // Gently retired at the feet.
            let t = min(max(elapsed / timing.departDuration, 0), 1)
            pose.asset = "xmas_gift_open_base.png"
            pose.lidLift = 1
            pose.position = anchors.groundBesidePet
            pose.alpha = 1 - t
        }
        return pose
    }

    // MARK: - New Year: soft reveal, inspect, confetti, hop, cleanup

    private static func newYearPose(
        phase: SeasonalPhase, elapsed: TimeInterval,
        anchors: EventAnchorSystem, timing: SeasonalTiming
    ) -> SeasonalPropPose {
        var pose = SeasonalPropPose()
        pose.asset = "newyear_calendar_jan1.png"
        switch phase {
        case .noticing, .idle, .completed, .cancelled:
            return pose
        case .approach:
            // Soft appearance beside the resting baseline.
            let t = min(max(elapsed / timing.approachDuration, 0), 1)
            pose.position = anchors.groundBesidePet
            pose.scale = 0.9 + 0.1 * easeOut(t)
            pose.alpha = min(1, t * 2.5)
        case .present:
            // Light touch: a tiny tilt inspection.
            let tilt = sin(elapsed * 1.4) * 1.8
            pose.position = anchors.groundBesidePet
            pose.rotationDegrees = tilt
        case .celebrate:
            // Confetti bursts over the first half of the celebration.
            let t = min(max(elapsed / timing.celebrateDuration, 0), 1)
            pose.position = anchors.groundBesidePet
            pose.effectAsset = "newyear_confetti_overlay.png"
            pose.effectAlpha = t < 0.6 ? sin(.pi * (t / 0.6)) * 0.95 : 0
        case .depart:
            let t = min(max(elapsed / timing.departDuration, 0), 1)
            pose.position = anchors.groundBesidePet
            pose.alpha = 1 - t
        }
        return pose
    }

    // MARK: - Umbrella: appear, reach, raise overhead, drizzle, retire

    private static func umbrellaPose(
        phase: SeasonalPhase, elapsed: TimeInterval,
        anchors: EventAnchorSystem, timing: SeasonalTiming
    ) -> SeasonalPropPose {
        var pose = SeasonalPropPose()
        pose.asset = "daily_umbrella.png"
        switch phase {
        case .noticing, .idle, .completed, .cancelled:
            return pose
        case .approach:
            // Appears within reach, leaning against the ground point.
            let t = min(max(elapsed / timing.approachDuration, 0), 1)
            let eased = easeOut(t)
            let start = CGPoint(x: anchors.groundBesidePet.x + 26, y: anchors.groundBesidePet.y)
            pose.position = CGPoint(
                x: start.x + (anchors.umbrellaGrip.x - start.x) * eased,
                y: start.y + (anchors.umbrellaGrip.y - start.y) * eased
            )
            pose.rotationDegrees = (1 - t) * -16
            pose.alpha = min(1, t * 2.6)
        case .present:
            // Raised: the handle settles into the grip anchor so the
            // canopy covers the head.
            let t = min(max(elapsed / 1.1, 0), 1)
            let eased = easeInOut(t)
            let raised = CGPoint(x: anchors.handFront.x + 4, y: anchors.handFront.y + 2)
            pose.position = CGPoint(
                x: anchors.umbrellaGrip.x + (raised.x - anchors.umbrellaGrip.x) * eased,
                y: anchors.umbrellaGrip.y + (raised.y - anchors.umbrellaGrip.y) * eased
            )
            pose.rotationDegrees = -16 * (1 - eased) + 2 * eased
            // Imaginary drizzle: gentle swell, hold, fade.
            let rainT = min(max(elapsed / timing.presentDuration, 0), 1)
            pose.effectAsset = "rain_drops_overlay.png"
            pose.effectAlpha = rainT < 0.3
                ? sin(.pi * (rainT / 0.3)) * 0.35
                : (rainT > 0.85 ? 0.35 * (1 - (rainT - 0.85) / 0.15) : 0.35)
        case .celebrate:
            pose.position = CGPoint(x: anchors.handFront.x + 4, y: anchors.handFront.y + 2)
            pose.rotationDegrees = 2
            pose.effectAsset = "rain_drops_overlay.png"
            pose.effectAlpha = 0.2
        case .depart:
            // Lowered back to the side, then retired.
            let t = min(max(elapsed / timing.departDuration, 0), 1)
            let eased = easeInOut(t)
            let raised = CGPoint(x: anchors.handFront.x + 4, y: anchors.handFront.y + 2)
            pose.position = CGPoint(
                x: raised.x + (anchors.groundBesidePet.x - raised.x) * eased,
                y: raised.y + (anchors.groundBesidePet.y - raised.y) * eased
            )
            pose.rotationDegrees = 2 + (1 - eased) * -18
            pose.alpha = 1 - t
        }
        return pose
    }

    // MARK: - Hot cocoa: appear at the paw, lift for a sip, put down

    private static func cocoaPose(
        phase: SeasonalPhase, elapsed: TimeInterval,
        anchors: EventAnchorSystem, timing: SeasonalTiming
    ) -> SeasonalPropPose {
        var pose = SeasonalPropPose()
        pose.asset = "daily_hot_cocoa.png"
        switch phase {
        case .noticing, .idle, .completed, .cancelled:
            return pose
        case .approach:
            // Gentle local placement at the front paw.
            let t = min(max(elapsed / timing.approachDuration, 0), 1)
            pose.position = anchors.nearRightFoot
            pose.alpha = min(1, t * 2.4)
        case .present:
            // Lift toward the face, hold, lower back.
            let t = min(max(elapsed / timing.presentDuration, 0), 1)
            let lift: CGFloat
            if t < 0.3 {
                lift = easeOut(t / 0.3)
            } else if t < 0.75 {
                lift = 1
            } else {
                lift = 1 - easeOut((t - 0.75) / 0.25)
            }
            let raised = CGPoint(x: anchors.handFront.x + 10, y: anchors.handFront.y + 4)
            pose.position = CGPoint(
                x: anchors.nearRightFoot.x + (raised.x - anchors.nearRightFoot.x) * lift,
                y: anchors.nearRightFoot.y + (raised.y - anchors.nearRightFoot.y) * lift
            )
            // Tiny steam sway while lifted.
            pose.rotationDegrees = lift > 0.05 ? sin(elapsed * 1.8) * 1.4 : 0
        case .celebrate:
            // Satisfied: the mug rests back at the paw.
            pose.position = anchors.nearRightFoot
        case .depart:
            let t = min(max(elapsed / timing.departDuration, 0), 1)
            pose.position = anchors.nearRightFoot
            pose.alpha = 1 - t
        }
        return pose
    }

    // MARK: - Sprout: emerge at the feet, lean in, sway, retire

    private static func sproutPose(
        phase: SeasonalPhase, elapsed: TimeInterval,
        anchors: EventAnchorSystem, timing: SeasonalTiming
    ) -> SeasonalPropPose {
        var pose = SeasonalPropPose()
        pose.asset = "daily_sprout.png"
        switch phase {
        case .noticing, .idle, .completed, .cancelled:
            return pose
        case .approach:
            // Grows out of the ground near the feet.
            let t = min(max(elapsed / timing.approachDuration, 0), 1)
            pose.position = anchors.nearLeftFoot
            pose.scale = 0.55 + 0.45 * easeOut(t)
            pose.alpha = min(1, t * 2.4)
        case .present:
            // Gentle leaf sway while the pet leans in.
            let sway = sin(elapsed * 1.6) * 3.2
            pose.position = anchors.nearLeftFoot
            pose.rotationDegrees = sway
        case .celebrate:
            pose.position = anchors.nearLeftFoot
            pose.rotationDegrees = sin(elapsed * 1.6) * 3.2
        case .depart:
            let t = min(max(elapsed / timing.departDuration, 0), 1)
            pose.position = anchors.nearLeftFoot
            pose.alpha = 1 - t
        }
        return pose
    }

    // MARK: - Paper airplane: continuous curved flyby, tracked gaze

    private static func airplanePose(
        phase: SeasonalPhase,
        elapsedInPhase: TimeInterval,
        totalElapsed: TimeInterval,
        anchors: EventAnchorSystem,
        visibleFrame: CGRect,
        timing: SeasonalTiming
    ) -> SeasonalPropPose {
        var pose = SeasonalPropPose()
        pose.asset = "daily_paper_airplane.png"
        pose.showTrail = true
        // One continuous flight across the whole scene, from left of the
        // pet to off-screen right, passing close above the head.
        let flightDuration = timing.approachDuration + timing.presentDuration
            + timing.celebrateDuration + timing.departDuration
        guard flightDuration > 0 else { return pose }
        let t = min(max(totalElapsed / flightDuration, 0), 1)
        let headY = anchors.headCenter.y + 26
        let p0 = CGPoint(x: visibleFrame.minX - 70, y: headY + 70)
        let p1 = CGPoint(x: anchors.headCenter.x - 150, y: headY + 30)
        let p2 = CGPoint(x: anchors.headCenter.x + 60, y: headY + 46)
        let p3 = CGPoint(x: visibleFrame.maxX + 90, y: headY + 90)
        pose.position = bezier(t, p0: p0, p1: p1, p2: p2, p3: p3)
        // Bank into the turns; nose direction roughly follows the path.
        pose.rotationDegrees = -10 + 14 * t
        pose.alpha = t < 0.05 ? t / 0.05 : (t > 0.92 ? (1 - t) / 0.08 : 1)
        if phase == .celebrate {
            // A happy little dip near the pet mid-flight.
            let dip = sin(elapsedInPhase * 2.2) * 6
            pose.position.y += dip
        }
        return pose
    }

    // MARK: - Easing + curves

    static func easeOut(_ t: CGFloat) -> CGFloat {
        let x = min(max(t, 0), 1)
        return 1 - (1 - x) * (1 - x)
    }

    static func easeInOut(_ t: CGFloat) -> CGFloat {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }

    /// Cubic bezier in 2D.
    static func bezier(
        _ t: CGFloat, p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint
    ) -> CGPoint {
        let x = min(max(t, 0), 1)
        let u = 1 - x
        let a = u * u * u
        let b = 3 * u * u * x
        let c = 3 * u * x * x
        let d = x * x * x
        return CGPoint(
            x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
            y: a * p0.y + b * p1.y + c * p2.y + d * p3.y
        )
    }
}
