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
        ZStack {
            bodyLayer
            eyesLayer
            mouthLayer
        }
        .frame(width: renderSize.width, height: renderSize.height)
        .onChange(of: parameters.mouthStyle) { oldStyle in
            previousMouthStyle = oldStyle
            previousMouthOpacity = 1
            withAnimation(.easeInOut(duration: 0.22)) {
                previousMouthOpacity = 0
            }
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var bodyLayer: some View {
        if let layer = rig.bodyLayer, let image = rigLoader.image(forLayer: layer, role: "base") {
            layerImage(image, layer: layer)
                // Breathing: subtle scale, deeper as drowsiness rises.
                .scaleEffect(breathScale, anchor: bodyCenterUnit)
                // Internal squash (identity for states where the outer
                // pose pipeline already deforms the body).
                .scaleEffect(
                    x: parameters.bodySquashX,
                    y: parameters.bodySquashY,
                    anchor: bodyCenterUnit
                )
                // Gentle internal lean.
                .rotationEffect(.radians(Double(parameters.bodyTilt)), anchor: bodyCenterUnit)
        }
    }

    /// Breathing amplitude: gentle awake, deeper asleep.
    private var breathScale: CGFloat {
        1 + 0.012 * sin(2 * .pi * parameters.breathPhase) * (0.4 + 0.6 * parameters.drowsiness)
    }

    private var bodyCenterUnit: UnitPoint {
        UnitPoint(
            x: rig.bodyBounds.midX,
            y: rig.bodyBounds.midY
        )
    }

    // MARK: - Eyes

    @ViewBuilder
    private var eyesLayer: some View {
        if let layer = rig.eyesLayer {
            // Continuous openness: crossfade between the open and closed
            // eye images (no binary open/closed switch). A single-image
            // rig degrades to a static eye layer.
            let openImage = rigLoader.image(forLayer: layer, role: "open")
            let closedImage = rigLoader.image(forLayer: layer, role: "closed")
            ZStack {
                if let openImage {
                    layerImage(openImage, layer: layer)
                        .opacity(Double(parameters.eyeOpenness))
                }
                if let closedImage {
                    layerImage(closedImage, layer: layer)
                        .opacity(Double(1 - parameters.eyeOpenness))
                }
            }
            // Small continuous gaze offset relative to the body.
            .offset(x: gazeOffsetX, y: gazeOffsetY)
        }
    }

    private var gazeOffsetX: CGFloat {
        let range = rig.eyesLayer?.gazeRange?.width ?? 0
        return parameters.gazeX * range * renderSize.width
    }

    private var gazeOffsetY: CGFloat {
        let range = rig.eyesLayer?.gazeRange?.height ?? 0
        return parameters.gazeY * range * renderSize.height
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
            // Continuous open amount on top of the style shape.
            .scaleEffect(1 + 0.18 * parameters.mouthOpenAmount, anchor: mouthAnchorUnit)
        }
    }

    private var mouthAnchorUnit: UnitPoint {
        UnitPoint(
            x: rig.mouthLayer?.anchor.x ?? 0.5,
            y: rig.mouthLayer?.anchor.y ?? 0.5
        )
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
            DispatchQueue.main.async { self.lastDate = date }

            let breath = WarawaraExpressionDriver.breathPhase(at: date.timeIntervalSinceReferenceDate)
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
