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
        // Body-level transforms wrap ALL layers so the face stays
        // registered to the deformed body (no detachment during squash,
        // lean or breathing). Face-only offsets happen inside the group.
        ZStack {
            bodyLayer
            eyesLayer
            mouthLayer
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

    // MARK: - Body

    @ViewBuilder
    private var bodyLayer: some View {
        if let layer = rig.bodyLayer, let image = rigLoader.image(forLayer: layer, role: "base") {
            layerImage(image, layer: layer)
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
            let e = min(max(parameters.eyeOpenness, 0), 1)
            // Continuous openness across three registered levels:
            // open (1) <-> half (0.5) <-> closed (0). At most two images
            // are meaningful at any moment.
            let (lower, upper, upperOpacity): (NSImage?, NSImage?, Double) =
                e >= 0.5
                ? (rigLoader.image(forLayer: layer, role: "open"),
                   rigLoader.image(forLayer: layer, role: "half"),
                   Double((1 - e) * 2))
                : (rigLoader.image(forLayer: layer, role: "half"),
                   rigLoader.image(forLayer: layer, role: "closed"),
                   Double((0.5 - e) * 2))

            // Curious focus and press squint replace the open look with
            // continuous crossfades (registered images, no jump).
            let focus = WarawaraLayeredGeometry.focusAmount(
                gazeX: parameters.gazeX, gazeY: parameters.gazeY
            )
            let press = WarawaraLayeredGeometry.pressBlend(pressAmount: parameters.pressAmount)

            ZStack {
                if let lower {
                    layerImage(lower, layer: layer)
                        .opacity(1 - upperOpacity)
                }
                if let upper {
                    layerImage(upper, layer: layer)
                        .opacity(upperOpacity)
                }
                if focus > 0.02, e >= 0.5,
                   let focused = rigLoader.image(forLayer: layer, role: "focused") {
                    layerImage(focused, layer: layer)
                        .opacity(Double(focus))
                }
                if press > 0.02,
                   let pressed = rigLoader.image(forLayer: layer, role: "pressed") {
                    layerImage(pressed, layer: layer)
                        .opacity(Double(press))
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

    /// Breathing scale: gentle awake, deeper as drowsiness rises.
    static func breathScale(breathPhase: CGFloat, drowsiness: CGFloat) -> CGFloat {
        let depth = min(max(drowsiness, 0), 1)
        return 1 + 0.012 * sin(2 * .pi * breathPhase) * (0.4 + 0.6 * depth)
    }

    /// Eye layer gaze offset, bounded by the rig's gazeRange.
    static func gazeOffset(
        axis: Axis,
        gaze: CGFloat,
        range: CGFloat,
        renderSize: CGSize
    ) -> CGFloat {
        let clamped = min(max(gaze, -1), 1)
        switch axis {
        case .x: return clamped * range * renderSize.width
        case .y: return clamped * range * renderSize.height
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
struct WarawaraExpressionDriverView: View {
    let rig: WarawaraRigManifest
    let rigLoader: WarawaraRigLoader
    let inputs: WarawaraExpressionInputs
    let renderSize: CGSize

    @State private var animator = WarawaraParameterAnimator()
    @State private var lastDate: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let date = context.date
            let dt = boundedDelta(from: lastDate, to: date)
            let _ = DispatchQueue.main.async { self.lastDate = date }

            // Breathing slows as the character drifts toward sleep.
            let breathPeriod = 4.0 + 2.5 * animator.parameters.drowsiness
            let breath = WarawaraExpressionDriver.breathPhase(
                at: date.timeIntervalSinceReferenceDate,
                period: breathPeriod
            )
            let blink = WarawaraExpressionDriver.blink(at: date.timeIntervalSinceReferenceDate)
            let contextValue = WarawaraExpressionContext(
                inputs: inputs,
                breathPhase: breath,
                floatPhase: inputs.floatProgress,
                blink: blink
            )
            let target = WarawaraExpressionMapper.targetParameters(for: contextValue)
            let parameters = withAnimationDisabled {
                var copy = animator
                copy.step(toward: target, dt: dt)
                animator = copy
                return copy.parameters
            }
            WarawaraLayeredCharacterView(
                rig: rig,
                rigLoader: rigLoader,
                parameters: parameters,
                renderSize: renderSize
            )
        }
    }

    private func boundedDelta(from previous: Date?, to current: Date) -> TimeInterval {
        guard let previous else { return 0 }
        return min(max(current.timeIntervalSince(previous), 0), 0.1)
    }

    /// Animator mutation inside the timeline closure must not trigger
    /// view updates mid-frame; step synchronously and return the value.
    private func withAnimationDisabled<T>(_ body: () -> T) -> T {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        return withTransaction(transaction) { body() }
    }
}

/// Pure, testable time helpers for the expression driver.
enum WarawaraExpressionDriver {
    /// Looping breath phase 0...1.
    static func breathPhase(at time: TimeInterval, period: TimeInterval = 4.0) -> CGFloat {
        let phase = (time / period).truncatingRemainder(dividingBy: 1)
        return CGFloat(phase < 0 ? phase + 1 : phase)
    }

    /// Blink strength 0...1: a raised-cosine pulse, mostly zero, with two
    /// overlapping periods so blinks never feel metronomic. Deterministic
    /// (placeholder until real tuning; no randomness in the render path).
    static func blink(at time: TimeInterval) -> CGFloat {
        max(
            blinkPulse(time, period: 3.6, width: 0.16, phase: 0.3),
            blinkPulse(time, period: 7.9, width: 0.16, phase: 5.1)
        )
    }

    static func blinkPulse(
        _ time: TimeInterval,
        period: TimeInterval,
        width: TimeInterval,
        phase: TimeInterval
    ) -> CGFloat {
        let x = (time + phase).truncatingRemainder(dividingBy: period)
        guard x >= 0, x < width else { return 0 }
        let t = x / width
        return CGFloat((1 - cos(2 * .pi * t)) / 2)
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
