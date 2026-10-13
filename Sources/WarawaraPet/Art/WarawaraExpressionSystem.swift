import Foundation

/// Inputs the app layer provides per frame. Time-derived values (breath
/// phase, blink) are added by the expression driver, so this struct stays
/// a plain value PetView can build from PetController state.
struct WarawaraExpressionInputs: Equatable {
    var state: PetState = .idle
    /// Signed cursor direction while curious (-1...1 each axis, right/up
    /// positive); zero otherwise.
    var gaze: CGVector = .zero
    /// Live drag deformation while dragged; neutral otherwise.
    var dragDeformation: PetDeformation = .neutral
    var hopProgress: CGFloat = 0
    var floatProgress: CGFloat = 0

    static let neutral = WarawaraExpressionInputs()
}

/// Full mapper context, including the time-derived components.
struct WarawaraExpressionContext: Equatable {
    var inputs: WarawaraExpressionInputs = .neutral
    /// Looping breathing phase 0...1.
    var breathPhase: CGFloat = 0
    /// Looping float phase 0...1.
    var floatPhase: CGFloat = 0
    /// Blink strength: 0 = fully open, 1 = fully closed for this tick.
    var blink: CGFloat = 0

    static let neutral = WarawaraExpressionContext()
}

/// Response-time tuning for the parameter animator.
struct WarawaraExpressionTuning {
    /// Eye openness (fast: blinks track closely, wake-up stays soft).
    var eyeResponse: TimeInterval = 0.12
    /// Eye openness response when drowsy: wakes and droops stay gradual
    /// instead of snapping open/shut.
    var eyeDrowsyResponse: TimeInterval = 0.55
    /// Gaze smoothing (curious tracking).
    var gazeResponse: TimeInterval = 0.18
    /// Mouth opening response.
    var mouthResponse: TimeInterval = 0.20
    /// Drowsiness drifts slowly so sleepy -> sleeping never snaps.
    var drowsinessResponse: TimeInterval = 1.4
    /// Press attack (instant squash feel)...
    var pressAttackResponse: TimeInterval = 0.045
    /// ...and press release (rebound recovery, deliberately slower).
    var pressReleaseResponse: TimeInterval = 0.35
    /// Drag intensity tracking.
    var dragResponse: TimeInterval = 0.08
    /// Internal body squash/tilt.
    var bodyResponse: TimeInterval = 0.25
    /// Mouth style crossfade handled by the renderer; this paces the
    /// open-amount and style decision cadence.
    var styleResponse: TimeInterval = 0.22

    static let `default` = WarawaraExpressionTuning()
}

/// Maps (state + inputs) to continuous parameter targets. Pure and
/// deterministic: the same context always yields the same targets.
/// Easing toward those targets is the parameter animator's job.
enum WarawaraExpressionMapper {
    static func targetParameters(
        for context: WarawaraExpressionContext,
        tuning: PersonalityTuning = .default
    ) -> WarawaraPerformanceParameters {
        var p = WarawaraPerformanceParameters.neutral
        let inputs = context.inputs

        switch inputs.state {
        case .idle:
            p.eyeOpenness = 1
            p.mouthStyle = .neutral
            p.mouthOpenAmount = 0
        case .curious:
            // Gaze follows the cursor direction (already smoothed by the
            // curiosity tracker); the body lean is handled by the existing
            // curiosity pose pipeline, so no double tilt here.
            p.eyeOpenness = 1
            p.gazeX = clamp(inputs.gaze.dx, -1, 1)
            p.gazeY = clamp(inputs.gaze.dy, -1, 1)
            p.mouthStyle = .neutral
        case .hop:
            // Mildly alert during flight; mouth opens mid-hop.
            p.eyeOpenness = 1
            let flight = hopFlightAmount(inputs.hopProgress)
            p.mouthStyle = flight > 0.2 ? .open : .soft
            p.mouthOpenAmount = flight
        case .float:
            p.eyeOpenness = 1
            p.mouthStyle = .soft
            p.mouthOpenAmount = 0.15
            p.floatPhase = context.floatPhase
            // Gentle wandering gaze while drifting.
            p.gazeX = 0.25 * sin(2 * .pi * context.floatPhase)
            p.gazeY = 0.15 * sin(2 * .pi * context.floatPhase + 1.2)
        case .clicked:
            p.pressAmount = 1
            p.eyeOpenness = 0.62 // squint under pressure
            p.mouthStyle = .pressed
            p.mouthOpenAmount = 0.15
        case .dragged:
            let deformation = inputs.dragDeformation
            let amount = clamp(
                (deformation.stretchScale - 1) / max(DeformationTuning.default.maxStretch, 0.001),
                0, 1
            )
            let direction = normalizedDragDirection(deformation.anchor)
            p.dragAmount = amount
            p.dragDirectionX = direction.dx
            p.dragDirectionY = direction.dy
            // Face follows the drag direction a little; eyes widen with speed.
            p.gazeX = clamp(direction.dx * 0.35, -1, 1)
            p.gazeY = clamp(direction.dy * 0.35, -1, 1)
            p.eyeOpenness = 0.85 + 0.15 * amount
            p.mouthStyle = amount > 0.25 ? .open : .soft
            p.mouthOpenAmount = 0.2 * amount
        case .settling:
            // Dazed little blink after landing/release.
            p.eyeOpenness = 0.9
            p.mouthStyle = .neutral
        case .sleepy:
            p.eyeOpenness = 0.5
            p.drowsiness = 0.5
            p.mouthStyle = .relaxed
            p.mouthOpenAmount = 0.1
            p.bodySquashX = 1.02
            p.bodySquashY = 0.98
        case .sleeping:
            p.eyeOpenness = 0.05
            p.drowsiness = 1
            p.mouthStyle = .sleepy
            p.mouthOpenAmount = 0.15
            p.bodySquashX = 1.03
            p.bodySquashY = 0.97
        }

        // Blink multiplies openness everywhere except deep sleep (already
        // closed) 鈥?continuous, never an open/closed flip.
        let blinkDamp = 1 - 0.8 * clamp(context.blink, 0, 1)
        if inputs.state != .sleeping {
            p.eyeOpenness *= blinkDamp
        }

        p.breathPhase = context.breathPhase
        return p.clamped()
    }

    /// Mouth openness across a hop: closed at takeoff/landing, open mid-flight.
    static func hopFlightAmount(_ progress: CGFloat) -> CGFloat {
        let x = clamp(progress, 0, 1)
        // Zero at the ends, peak in the middle flight phase.
        if x < 0.15 || x > 0.85 { return 0 }
        let t = (x - 0.15) / 0.7
        return sin(.pi * t) * 0.5
    }

    /// Normalizes the drag anchor (grab point relative to center) to a
    /// signed -1...1 direction.
    static func normalizedDragDirection(_ anchor: CGVector) -> CGVector {
        let limit = DeformationTuning.default.grabAnchorLimit
        guard limit > 0 else { return .zero }
        return CGVector(
            dx: clamp(anchor.dx / limit, -1, 1),
            dy: clamp(anchor.dy / limit, -1, 1)
        )
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(value, low), high)
    }
}

/// Eases parameters toward targets with per-parameter exponential
/// smoothing. Pure and deterministic: `step(toward:dt:)` only depends on
/// its inputs and the stored current values.
struct WarawaraParameterAnimator {
    var tuning = WarawaraExpressionTuning.default
    private(set) var parameters = WarawaraPerformanceParameters.neutral

    /// Advances the animation by `dt` seconds toward `target`.
    /// Returns the new (clamped) parameters.
    @discardableResult
    mutating func step(
        toward target: WarawaraPerformanceParameters,
        dt: TimeInterval
    ) -> WarawaraPerformanceParameters {
        let t = target.clamped()
        let dtF = CGFloat(max(dt, 0))

        // Eye response slows with drowsiness so sleeping <-> wake
        // transitions are continuous reopenings, never snaps.
        let eyeTau = tuning.eyeResponse
            + (tuning.eyeDrowsyResponse - tuning.eyeResponse) * parameters.drowsiness
        parameters.eyeOpenness = Self.approach(
            parameters.eyeOpenness, t.eyeOpenness,
            dt: dtF, tau: eyeTau
        )
        parameters.gazeX = Self.approach(parameters.gazeX, t.gazeX, dt: dtF, tau: tuning.gazeResponse)
        parameters.gazeY = Self.approach(parameters.gazeY, t.gazeY, dt: dtF, tau: tuning.gazeResponse)
        parameters.mouthOpenAmount = Self.approach(
            parameters.mouthOpenAmount, t.mouthOpenAmount,
            dt: dtF, tau: tuning.mouthResponse
        )
        parameters.drowsiness = Self.approach(
            parameters.drowsiness, t.drowsiness,
            dt: dtF, tau: tuning.drowsinessResponse
        )
        parameters.dragAmount = Self.approach(parameters.dragAmount, t.dragAmount, dt: dtF, tau: tuning.dragResponse)
        parameters.dragDirectionX = Self.approach(
            parameters.dragDirectionX, t.dragDirectionX, dt: dtF, tau: tuning.dragResponse
        )
        parameters.dragDirectionY = Self.approach(
            parameters.dragDirectionY, t.dragDirectionY, dt: dtF, tau: tuning.dragResponse
        )
        parameters.bodySquashX = Self.approach(
            parameters.bodySquashX, t.bodySquashX, dt: dtF, tau: tuning.bodyResponse
        )
        parameters.bodySquashY = Self.approach(
            parameters.bodySquashY, t.bodySquashY, dt: dtF, tau: tuning.bodyResponse
        )
        parameters.bodyTilt = Self.approach(parameters.bodyTilt, t.bodyTilt, dt: dtF, tau: tuning.bodyResponse)

        // Press uses asymmetric response: fast squash on press, slower
        // springy release on recovery 鈥?no instant snap-back.
        let pressTau = t.pressAmount > parameters.pressAmount
            ? tuning.pressAttackResponse
            : tuning.pressReleaseResponse
        parameters.pressAmount = Self.approach(parameters.pressAmount, t.pressAmount, dt: dtF, tau: pressTau)

        // Mouth style: adopt the target style but let the renderer
        // crossfade the images; the style value itself eases through the
        // open amount and style cadence.
        parameters.mouthStyle = t.mouthStyle

        parameters.breathPhase = t.breathPhase
        parameters.floatPhase = t.floatPhase
        parameters.limbSwingAmount = Self.approach(
            parameters.limbSwingAmount, t.limbSwingAmount, dt: dtF, tau: tuning.bodyResponse
        )
        parameters.limbLagPhase = t.limbLagPhase

        parameters = parameters.clamped()
        return parameters
    }

    /// Jump directly to a value (wake-ups etc. 鈥?still used only where a
    /// hard reset is semantically required).
    mutating func set(_ value: WarawaraPerformanceParameters) {
        parameters = value.clamped()
    }

    /// Exponential smoothing: factor = 1 - e^(-dt/tau).
    static func approach(_ current: CGFloat, _ target: CGFloat, dt: CGFloat, tau: TimeInterval) -> CGFloat {
        guard dt > 0, tau > 0 else { return current }
        let factor = 1 - exp(-dt / CGFloat(tau))
        return current + (target - current) * factor
    }
}
