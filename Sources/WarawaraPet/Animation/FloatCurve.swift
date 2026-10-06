import Foundation

/// Sustained, buoyant drifting — clearly distinct from a hop.
/// Phases over normalized time t in [0, 1]:
///   lift    0.00...liftFraction         slow eased ascent (no sharp launch)
///   hover   lift...lift+hover           plateau near peak height with a
///                                       low-frequency vertical bob
///   descent ...+descent                 slower, softer eased descent
///   settle  ...1.00                     at rest at ground (no bounce)
enum FloatCurve {
    private static func smoothstep(_ x: CGFloat) -> CGFloat {
        x * x * (3 - 2 * x)
    }

    static func liftEnd(_ tuning: PersonalityTuning) -> CGFloat {
        tuning.floatLiftFraction
    }

    static func hoverEnd(_ tuning: PersonalityTuning) -> CGFloat {
        tuning.floatLiftFraction + tuning.floatHoverFraction
    }

    static func descentEnd(_ tuning: PersonalityTuning) -> CGFloat {
        tuning.floatLiftFraction + tuning.floatHoverFraction + tuning.floatDescentFraction
    }

    static func offsetY(at t: CGFloat, height: CGFloat, tuning: PersonalityTuning) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        let lift = liftEnd(tuning)
        let hover = hoverEnd(tuning)
        let descent = descentEnd(tuning)

        if clamped < lift {
            return height * smoothstep(clamped / lift)
        }
        if clamped < hover {
            let u = clamped - lift
            let envelope = sin(.pi * u / tuning.floatHoverFraction)
            let bob = tuning.floatBobAmplitude * envelope
                * sin(2 * .pi * u / tuning.floatBobPeriod)
            return height + bob
        }
        if clamped < descent {
            let u = (clamped - hover) / tuning.floatDescentFraction
            return height * (1 - smoothstep(u))
        }
        return 0
    }

    static func offsetX(
        at t: CGFloat,
        drift: CGFloat,
        swayAmplitude: CGFloat,
        swayCycles: CGFloat,
        swayPhase: CGFloat
    ) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        let envelope = sin(.pi * clamped)
        let sway = swayAmplitude * envelope
            * sin(2 * .pi * swayCycles * clamped + swayPhase)
        let driftTerm = drift * envelope * envelope
        return sway + driftTerm
    }

    static func swayCycles(duration: TimeInterval, tuning: PersonalityTuning) -> CGFloat {
        CGFloat(duration / tuning.floatSwayPeriod)
    }
}

/// Low-amplitude body deformation during a float, expressed through the
/// existing PetDeformation type: slight vertical elongation while lifting
/// or descending, subtle breathing pulsation during hover, and a gentle
/// sway-synchronized lean.
enum FloatPoseMath {
    static func pose(
        at t: CGFloat,
        parameters: FloatParameters,
        tuning: PersonalityTuning
    ) -> PetDeformation {
        let clamped = min(max(t, 0), 1)
        let lift = FloatCurve.liftEnd(tuning)
        let hover = FloatCurve.hoverEnd(tuning)
        let descent = FloatCurve.descentEnd(tuning)

        var motion: CGFloat = 0
        if clamped < lift {
            motion = sin(.pi * clamped / lift)
        } else if clamped >= hover, clamped < descent {
            motion = sin(.pi * (clamped - hover) / tuning.floatDescentFraction)
        }

        var pulse: CGFloat = 0
        if clamped >= lift, clamped < hover {
            let u = clamped - lift
            let envelope = sin(.pi * u / tuning.floatHoverFraction)
            pulse = envelope * (0.5 + 0.5 * sin(2 * .pi * u / tuning.floatBobPeriod))
        }

        let amount = tuning.floatBodyStretch * (0.6 * motion + 0.4 * pulse)
        let stretchScale = 1 + amount
        let swayCycles = FloatCurve.swayCycles(duration: parameters.duration, tuning: tuning)
        let rotation = tuning.floatSwayLean
            * cos(2 * .pi * swayCycles * clamped + parameters.swayPhase)
            * sin(.pi * clamped)

        return PetDeformation(
            stretchAngle: .pi / 2,
            stretchScale: stretchScale,
            perpendicularScale: 1 / stretchScale,
            rotation: rotation,
            anchor: CGVector(dx: 0, dy: -1)
        )
    }
}
