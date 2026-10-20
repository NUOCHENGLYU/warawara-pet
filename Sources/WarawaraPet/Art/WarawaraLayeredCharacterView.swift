import SwiftUI

/// Layered character renderer: body + eyes + mouth (limbs reserved).
/// All layers share the rig's canvas coordinate system; the parameter
/// values drive continuous, eased motion — the renderer never branches
/// on discrete state values.
struct WarawaraLayeredCharacterView: View {
    let rig: WarawaraRigManifest
    let rigLoader: WarawaraRigLoader
    let parameters: WarawaraPerformanceParameters
    let renderSize: CGSize

    /// Previous mouth style, crossfaded out on style changes.
    @State private var previousMouthStyle: WarawaraMouthStyle?
    @State private var previousMouthOpacity: Double = 0

    var body: some View {
        // 2.5D head-turn hierarchy (single yaw/pitch source of truth):
        //   body pose (outer pipeline, untouched)
        //   -> body volume warp: perspective-aware strip redistribution
        //      of the body raster (near side expands, far side narrows)
        //      + far-side shading — the silhouette actually turns
        //   -> shared facial frame: ONE affine remap of eyes + mouth
        //      derived from the same yaw/pitch (face rides the near
        //      side, eye spacing foreshortens) — never independent
        //      per-layer translations
        //   -> minimal eye-local gaze inside the facial frame
        //   -> whole-group breath / squash / lean (unchanged)
        // The birthday hat renders in front of the face group so it
        // inherits every body transform.
        ZStack {
            bodyLayer
            Group {
                eyesLayer
                mouthLayer
            }
            .scaleEffect(
                x: faceTransform?.scaleX ?? 1,
                y: faceTransform?.scaleY ?? 1,
                anchor: faceCenterUnit
            )
            .offset(
                x: faceTransform?.offset(in: renderSize).width ?? 0,
                y: faceTransform?.offset(in: renderSize).height ?? 0
            )
        }
        .frame(width: renderSize.width, height: renderSize.height)
        .scaleEffect(breathScale, anchor: bodyCenterUnit)
        .scaleEffect(
            x: parameters.bodySquashX,
            y: parameters.bodySquashY,
            anchor: bodyCenterUnit
        )
        .rotationEffect(.radians(Double(parameters.bodyTilt)), anchor: bodyCenterUnit)
        .onChange(of: parameters.mouthStyle) { oldStyle in
            previousMouthStyle = oldStyle
            previousMouthOpacity = 1
            withAnimation(.easeInOut(duration: 0.18)) {
                previousMouthOpacity = 0
            }
        }
    }

    /// The shared facial remap derived from yaw/pitch; nil (and thus
    /// exactly the accepted rendering) while the turn is inactive.
    private var faceTransform: WarawaraTurnGeometry.FaceTransform? {
        guard WarawaraTurnGeometry.isActive(
            yawDegrees: parameters.yawDegrees,
            pitchDegrees: parameters.pitchDegrees
        ) else { return nil }
        return WarawaraTurnGeometry.faceTransform(
            yawDegrees: parameters.yawDegrees,
            pitchDegrees: parameters.pitchDegrees
        )
    }

    private var faceCenterUnit: UnitPoint {
        UnitPoint(
            x: rig.eyesLayer?.anchor.x ?? 0.5,
            y: rig.eyesLayer?.anchor.y ?? 0.5
        )
    }

    // MARK: - Body

    @ViewBuilder
    private var bodyLayer: some View {
        if let layer = rig.bodyLayer, let image = rigLoader.image(forLayer: layer, role: "base") {
            if WarawaraTurnGeometry.isActive(
                yawDegrees: parameters.yawDegrees,
                pitchDegrees: parameters.pitchDegrees
            ),
               let warped = WarawaraWarpRenderer.warpedBodyImage(
                   body: image,
                   canvasSize: renderSize,
                   bodyBounds: rig.bodyBounds,
                   yawDegrees: parameters.yawDegrees,
                   pitchDegrees: parameters.pitchDegrees
               ) {
                // ONE coherent pre-rendered surface: continuous outline,
                // shading confined to the silhouette, composited exactly
                // like the accepted neutral artwork.
                Image(nsImage: warped)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: renderSize.width, height: renderSize.height)
                    .offset(
                        x: renderSize.width / 2 - layer.anchor.x * renderSize.width,
                        y: renderSize.height / 2 - layer.anchor.y * renderSize.height
                    )
            } else {
                layerImage(image, layer: layer)
            }
        }
    }

    /// Breathing amplitude: gentle awake, deeper asleep.
    private var breathScale: CGFloat {
        WarawaraLayeredGeometry.breathScale(
            breathPhase: parameters.breathPhase,
            drowsiness: parameters.drowsiness
        )
    }

    private var bodyCenterUnit: UnitPoint {
        WarawaraLayeredGeometry.bodyCenterUnit(bodyBounds: rig.bodyBounds)
    }

    // MARK: - Eyes

    @ViewBuilder
    private var eyesLayer: some View {
        if let layer = rig.eyesLayer {
            let e = WarawaraLayeredGeometry.effectiveEyeOpenness(
                base: parameters.eyeOpenness,
                blink: parameters.blinkAmount
            )
            let focus = WarawaraLayeredGeometry.focusAmount(
                gazeX: parameters.gazeX, gazeY: parameters.gazeY
            )
            let press = WarawaraLayeredGeometry.pressBlend(pressAmount: parameters.pressAmount)
            // Normalized composition: the base pair and the focused /
            // pressed overlays are mutually exclusive weights whose sum
            // never exceeds 1 — no additive double eyes, and fully closed
            // eyes leave zero open-eye remnant.
            let weights = WarawaraLayeredGeometry.composedEyeWeights(
                openness: e, focus: focus, press: press
            )
            let openImage = rigLoader.image(forLayer: layer, role: "open")
            let halfImage = rigLoader.image(forLayer: layer, role: "half")
            let closedImage = rigLoader.image(forLayer: layer, role: "closed")
            let focusedImage = rigLoader.image(forLayer: layer, role: "focused")
            let pressedImage = rigLoader.image(forLayer: layer, role: "pressed")

            ZStack {
                if weights.lowerWeight > 0.001 {
                    if let image = weights.lowerIsOpen ? openImage : halfImage {
                        layerImage(image, layer: layer)
                            .opacity(weights.lowerWeight)
                    }
                }
                if weights.upperWeight > 0.001 {
                    if let image = weights.lowerIsOpen ? halfImage : closedImage {
                        layerImage(image, layer: layer)
                            .opacity(weights.upperWeight)
                    }
                }
                if weights.focusedWeight > 0.001, let focusedImage {
                    layerImage(focusedImage, layer: layer)
                        .opacity(weights.focusedWeight)
                }
                if weights.pressedWeight > 0.001, let pressedImage {
                    layerImage(pressedImage, layer: layer)
                        .opacity(weights.pressedWeight)
                }
            }
            .offset(x: gazeOffsetX, y: gazeOffsetY)
        }
    }

    private var gazeOffsetX: CGFloat {
        WarawaraLayeredGeometry.gazeOffset(
            axis: .x,
            gaze: parameters.gazeX,
            range: rig.eyesLayer?.gazeRange?.width ?? 0,
            renderSize: renderSize
        )
    }

    private var gazeOffsetY: CGFloat {
        WarawaraLayeredGeometry.gazeOffset(
            axis: .y,
            gaze: parameters.gazeY,
            range: rig.eyesLayer?.gazeRange?.height ?? 0,
            renderSize: renderSize
        )
    }

    // MARK: - Mouth

    @ViewBuilder
    private var mouthLayer: some View {
        if let layer = rig.mouthLayer {
            ZStack {
                if let previous = previousMouthStyle,
                   previous != parameters.mouthStyle,
                   let image = rigLoader.image(forLayer: layer, role: previous.rawValue) {
                    layerImage(image, layer: layer)
                        .opacity(previousMouthOpacity)
                }
                if let image = rigLoader.image(forLayer: layer, role: parameters.mouthStyle.rawValue) {
                    layerImage(image, layer: layer)
                }
            }
            // Continuous open amount: controlled width/height scaling
            // around the mouth's registered pivot.
            .scaleEffect(
                x: 1 + 0.10 * parameters.mouthOpenAmount,
                y: 1 + 0.22 * parameters.mouthOpenAmount,
                anchor: mouthAnchorUnit
            )
        }
    }

    private var mouthAnchorUnit: UnitPoint {
        WarawaraLayeredGeometry.pivotUnit(layer: rig.mouthLayer)
    }

    // MARK: - Shared layer geometry

    /// A rig layer image drawn over the shared canvas, positioned so its
    /// normalized anchor maps onto the corresponding canvas point.
    private func layerImage(_ image: NSImage, layer: WarawaraRigManifest.Layer) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: renderSize.width, height: renderSize.height)
            .offset(
                x: renderSize.width / 2 - layer.anchor.x * renderSize.width,
                y: renderSize.height / 2 - layer.anchor.y * renderSize.height
            )
    }
}

/// Pure, testable geometry helpers shared by the layered renderer.
enum WarawaraLayeredGeometry {
    enum Axis { case x, y }

    /// Transform pivot at the body bounds center (normalized).
    static func bodyCenterUnit(bodyBounds: CGRect) -> UnitPoint {
        UnitPoint(x: bodyBounds.midX, y: bodyBounds.midY)
    }

    /// Breathing scale: gentle awake, clearly visible (but still soft)
    /// asleep. Consumed ONLY from the continuous phase accumulator —
    /// this is the single breathing authority for the character.
    static func breathScale(breathPhase: CGFloat, drowsiness: CGFloat) -> CGFloat {
        let depth = min(max(drowsiness, 0), 1)
        return 1 + 0.012 * sin(2 * .pi * breathPhase) * (0.4 + 0.9 * depth)
    }

    /// Screen-space conversion: gaze parameters use a canonical UP-
    /// POSITIVE Y (matching NSEvent screen coordinates and the curiosity
    /// tracker), while SwiftUI offsets are DOWN-POSITIVE. The negation
    /// happens exactly once, here.
    private static func screenAxis(_ axis: Axis, gaze: CGFloat) -> CGFloat {
        let clamped = min(max(gaze, -1), 1)
        return axis == .y ? -clamped : clamped
    }

    /// Eye layer gaze offset, bounded by the rig's gazeRange.

    /// Final rendered eye openness: the slow state channel (sleep/drowsy,
    /// smoothed by the animator) multiplied by the fast, unsmoothed blink
    /// channel. Sleeping stays fully closed because its base is zero.
    static func effectiveEyeOpenness(base: CGFloat, blink: CGFloat) -> CGFloat {
        let b = min(max(base, 0), 1)
        let k = min(max(blink, 0), 1)
        return min(max(b * (1 - 0.95 * k), 0), 1)
    }

    /// Normalized eye-layer composition weights for one rendered frame.
    struct EyeCompositeWeights: Equatable {
        var lowerWeight: Double
        var upperWeight: Double
        /// True when the lower slot is the "open" artwork (open/half pair);
        /// false for the half/closed pair.
        var lowerIsOpen: Bool
        var focusedWeight: Double
        var pressedWeight: Double

        var total: Double {
            lowerWeight + upperWeight + focusedWeight + pressedWeight
        }
    }

    /// Mutually exclusive blending across open/half/closed plus the
    /// focused and pressed overlays. The base pair weight is scaled down
    /// by the overlay weights, so the sum never exceeds 1 — no additive
    /// double eyes, and openness 0 leaves zero open-eye remnant.
    static func composedEyeWeights(
        openness: CGFloat,
        focus: CGFloat,
        press: CGFloat
    ) -> EyeCompositeWeights {
        let e = min(max(openness, 0), 1)
        let f = min(max(focus, 0), 1)
        let p = min(max(press, 0), 1)

        // The overlays replace part of the base pair: overlay total is
        // clamped and the pair is scaled down, so the whole composite
        // sums to exactly 1 (no additive double eyes).
        let overlayTotal = min(f + p, 1)
        let baseScale = 1 - overlayTotal
        var focusedWeight = f
        var pressedWeight = p
        if f + p > 1, f + p > 0 {
            let scale = overlayTotal / (f + p)
            focusedWeight *= scale
            pressedWeight *= scale
        }

        var lower: Double
        var upper: Double
        var lowerIsOpen: Bool
        if e >= 0.5 {
            lowerIsOpen = true
            lower = Double(2 * e - 1)
            upper = Double((1 - e) * 2)
        } else {
            lowerIsOpen = false
            lower = Double(e * 2)
            upper = Double((0.5 - e) * 2)
        }
        return EyeCompositeWeights(
            lowerWeight: lower * baseScale,
            upperWeight: upper * baseScale,
            lowerIsOpen: lowerIsOpen,
            focusedWeight: Double(focusedWeight),
            pressedWeight: Double(pressedWeight)
        )
    }

    /// Eye layer gaze offset, bounded by the rig's gazeRange.
    /// Gaze parameters are UP-POSITIVE; the returned value is a SwiftUI
    /// offset (DOWN-POSITIVE Y) — converted once via screenAxis.
    static func gazeOffset(
        axis: Axis,
        gaze: CGFloat,
        range: CGFloat,
        renderSize: CGSize
    ) -> CGFloat {
        let signed = screenAxis(axis, gaze: gaze)
        switch axis {
        case .x: return signed * range * renderSize.width
        case .y: return signed * range * renderSize.height
        }
    }

    /// Curious focus blend 0...1 from the gaze magnitude (smooth, no
    /// threshold snap).
    static func focusAmount(gazeX: CGFloat, gazeY: CGFloat) -> CGFloat {
        let magnitude = min(hypot(gazeX, gazeY), 1)
        return smoothstep(magnitude, edge0: 0.3, edge1: 0.7)
    }

    /// Press squint blend 0...1 from the press amount.
    static func pressBlend(pressAmount: CGFloat) -> CGFloat {
        smoothstep(min(max(pressAmount, 0), 1), edge0: 0.25, edge1: 0.6)
    }

    /// Layer transform pivot: explicit pivot or the layer anchor.
    static func pivotUnit(layer: WarawaraRigManifest.Layer?) -> UnitPoint {
        UnitPoint(
            x: layer?.pivot?.x ?? layer?.anchor.x ?? 0.5,
            y: layer?.pivot?.y ?? layer?.anchor.y ?? 0.5
        )
    }

    static func smoothstep(_ x: CGFloat, edge0: CGFloat, edge1: CGFloat) -> CGFloat {
        guard edge1 > edge0 else { return x >= edge1 ? 1 : 0 }
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// Time-driven expression driver: computes continuous performance
/// parameters (breath, blink, state targets) and eases toward them.
/// Sits inside WarawaraCharacterView and receives the app-level inputs.
///
/// State is mutated ONLY inside `tick(at:inputs:)`, which runs from a
/// `TimelineView.onChange` — never during view evaluation. Repeated
/// ticks with the same date are no-ops, so no duplicate stepping occurs.
struct WarawaraExpressionDriverView: View {
    let rig: WarawaraRigManifest
    let rigLoader: WarawaraRigLoader
    let inputs: WarawaraExpressionInputs
    let renderSize: CGSize

    @StateObject private var model = WarawaraExpressionDriverModel()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            WarawaraLayeredCharacterView(
                rig: rig,
                rigLoader: rigLoader,
                parameters: model.parameters,
                renderSize: renderSize
            )
            .onChange(of: context.date) { newDate in
                model.tick(at: newDate, inputs: inputs)
            }
        }
    }
}

/// The expression animator's state holder. All mutation happens in
/// `tick`, which is idempotent per date (dt == 0 for repeated calls).
final class WarawaraExpressionDriverModel: ObservableObject {
    @Published private(set) var parameters = WarawaraPerformanceParameters.neutral

    private var animator = WarawaraParameterAnimator()
    private var lastDate: Date?
    /// The SINGLE continuous breathing-phase accumulator (0...<1). It is
    /// never recomputed from absolute time: each tick advances it by
    /// dt / currentPeriod and wraps. The period may vary smoothly with
    /// drowsiness without ever jumping the phase, and sleep/wake
    /// transitions never reset it.
    private var breathPhase: CGFloat = 0

    func tick(at date: Date, inputs: WarawaraExpressionInputs) {
        let dt: TimeInterval
        if let last = lastDate {
            dt = min(max(date.timeIntervalSince(last), 0), 0.1)
        } else {
            dt = 0
        }
        lastDate = date

        // Breathing slows as the character drifts toward sleep. The
        // period follows the SMOOTHED drowsiness, so the frequency
        // changes continuously and the accumulator stays continuous.
        let breathPeriod = WarawaraExpressionDriver.breathBasePeriod
            + WarawaraExpressionDriver.breathSleepyExtraPerDrowsiness * animator.parameters.drowsiness
        breathPhase = WarawaraExpressionDriver.advanceBreathPhase(
            breathPhase, by: dt, period: breathPeriod
        )
        let blink = WarawaraExpressionDriver.blink(at: date.timeIntervalSinceReferenceDate)
        let context = WarawaraExpressionContext(
            inputs: inputs,
            breathPhase: breathPhase,
            floatPhase: inputs.floatProgress,
            blink: blink
        )
        let target = WarawaraExpressionMapper.targetParameters(for: context)
        animator.step(toward: target, dt: dt)
        parameters = animator.parameters
    }

    /// Test/diagnostic access to the smoothed state.
    var animatorParameters: WarawaraPerformanceParameters { animator.parameters }
}

/// Pure, testable time helpers for the expression driver.
enum WarawaraExpressionDriver {
    /// Awake breathing period in seconds (same value as the retired
    /// `PersonalityTuning.breathingPeriod`).
    static let breathBasePeriod: TimeInterval = 4.0
    /// Extra breathing period per unit of (smoothed) drowsiness: a fully
    /// asleep pet breathes with a 6.5 s period.
    static let breathSleepyExtraPerDrowsiness: TimeInterval = 2.5

    /// Advances a looping breathing phase by `dt` seconds at the given
    /// period, wrapping into 0...<1. This is the ONLY phase math used by
    /// the driver: an accumulator, never an absolute-time division, so
    /// period changes can never jump the phase.
    /// - dt is clamped to a positive value; a zero or negative dt is a
    ///   no-op (repeated ticks with the same date never double-step).
    /// - Non-positive periods are ignored (defensive).
    static func advanceBreathPhase(
        _ phase: CGFloat,
        by dt: TimeInterval,
        period: TimeInterval
    ) -> CGFloat {
        guard dt > 0, period > 0 else { return phase - floor(phase) }
        let next = phase - floor(phase) + CGFloat(dt / period)
        return next - floor(next)
    }

    /// Blink strength 0...1 with a natural asymmetric profile: quick
    /// close (0.06 s), brief fully-closed hold (0.05 s), slower reopen
    /// (0.15 s) — clearly visible to a human observer but still subtle.
    /// Two overlapping periods avoid a metronomic feel. Deterministic
    /// (no randomness in the render path).
    static func blink(at time: TimeInterval) -> CGFloat {
        max(
            blinkPulse(time, period: 3.8, phase: 0.3),
            blinkPulse(time, period: 7.6, phase: 5.1)
        )
    }

    static func blinkPulse(
        _ time: TimeInterval,
        period: TimeInterval,
        width: TimeInterval = 0.26,
        phase: TimeInterval
    ) -> CGFloat {
        let x = (time + phase).truncatingRemainder(dividingBy: period)
        guard x >= 0, x < width else { return 0 }
        let closeDuration = 0.06
        let holdDuration = 0.05
        let reopenDuration = width - closeDuration - holdDuration
        if x < closeDuration {
            // Fast close, ease-in slightly for a natural lid drop.
            let t = x / closeDuration
            return CGFloat(t * (2 - t))
        }
        if x < closeDuration + holdDuration {
            return 1
        }
        // Slower reopen with ease-out.
        let t = (x - closeDuration - holdDuration) / reopenDuration
        let eased = 1 - t * t * (3 - 2 * t)
        return CGFloat(eased)
    }

    /// Canvas render size for the rig, matching the sprite pipeline's
    /// body-height scaling (main 118 pt, companion 74 pt, times scale).
    static func renderSize(
        rig: WarawaraRigManifest,
        targetBodyHeight: CGFloat
    ) -> CGSize? {
        let bodyHeightInCanvas = rig.bodyBounds.height * rig.canvas.height
        guard bodyHeightInCanvas > 0 else { return nil }
        return WarawaraAnimationMapper.renderSize(
            canvas: rig.canvas,
            bodyHeightInCanvas: bodyHeightInCanvas,
            targetBodyHeight: targetBodyHeight
        )
    }
}
