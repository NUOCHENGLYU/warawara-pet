import SwiftUI

struct PetView: View {
    @ObservedObject var controller: PetController
    @ObservedObject var bottleVisualProvider: BottleVisualProvider

    @State private var bobbing = false

    private let bobAnimation = Animation
        .easeInOut(duration: 2.2)
        .repeatForever(autoreverses: true)

    private let poseAnimation = Animation
        .spring(
            response: PersonalityTuning.default.wakeTransitionDuration,
            dampingFraction: 0.55
        )

    private let deformationReleaseAnimation = Animation
        .spring(
            response: DeformationTuning.default.releaseSpringResponse,
            dampingFraction: DeformationTuning.default.releaseSpringDamping
        )

    private var visual: BottleVisualCoordinator? {
        bottleVisualProvider.coordinator
    }

    var body: some View {
        petCanvas
            .frame(
                width: PetMetrics.windowSize.width,
                height: PetMetrics.windowSize.height,
                alignment: .bottom
            )
    }

    /// The unchanged 226 pt pet canvas, bottom-anchored inside the taller
    /// window. The transparent strip above it is poof drawing room only —
    /// every pet-space coordinate, the hit ellipse and the drag anchor
    /// stay relative to this canvas.
    private var petCanvas: some View {
        ZStack {
            // The whole transition reads as ONE body: the character, the
            // bottle form and the smoke share the hop, squash and
            // landing wobble driven by the poof timeline.
            ZStack {
                petGroup
                // The bottle form renders IN FRONT of the character —
                // only AFTER the hidden swap (formProgress == 1), so
                // the two silhouettes never visibly overlap.
                if let visual, visual.isBottleForm {
                    BottleArtOverlayView(visual: visual, store: .shared)
                        .scaleEffect(x: stateScaleX, y: stateScaleY, anchor: .bottom)
                }
                // The occlusion smoke sits ON TOP of both forms.
                if let visual, BottlePoofTimeline.smokeVisible(t: visual.morphProgress) {
                    BottlePoofSmokeView(
                        timeline: visual.morphProgress,
                        reduceMotion: visual.reduceMotion(),
                        store: .shared
                    )
                }
            }
            .scaleEffect(x: stateScaleX * poofSquash.x, y: stateScaleY * poofSquash.y, anchor: .bottom)
            .offset(y: -poofJump)
            .rotationEffect(.radians(poofWobble), anchor: .bottom)
            .offset(y: bobOffset)

            // The stable bottle never shows the sleep "Z" — the pet's
            // sleep machinery is suspended while bottle-formed anyway;
            // this gate also covers the transition edges.
            if controller.state == .sleeping && !(visual?.isBottleForm ?? false) {
                SleepIndicatorView()
            }
        }
        .frame(width: PetMetrics.size.width, height: PetMetrics.size.height, alignment: .bottom)
        .animation(bobAnimation, value: bobbing)
        .onAppear {
            bobbing = true
        }
    }

    /// The poof transition hop (0 outside the transition timeline).
    private var poofJump: CGFloat {
        guard let visual else { return 0 }
        return BottlePoofTimeline.jumpOffsetY(
            t: visual.morphProgress,
            reduceMotion: visual.reduceMotion()
        )
    }

    /// Anticipation -> flight stretch -> landing squash (poof timeline).
    private var poofSquash: (x: CGFloat, y: CGFloat) {
        guard let visual else { return (1, 1) }
        return (
            BottlePoofTimeline.squashX(t: visual.morphProgress),
            BottlePoofTimeline.squashY(t: visual.morphProgress)
        )
    }

    /// Tiny inertial tilt after the landing.
    private var poofWobble: Double {
        guard let visual else { return 0 }
        return BottlePoofTimeline.landingWobble(t: visual.morphProgress)
    }

    private var petGroup: some View {
        WarawaraCharacterView(
            visualState: WarawaraVisualState.state(for: controller.state),
            loader: .shared,
            placeholderSizeClass: .main,
            expressionInputs: expressionInputs
        )
        .modifier(PoseEffect(
            deformation: controller.dragDeformation,
            isActive: controller.state == .dragged,
            releaseAnimation: deformationReleaseAnimation
        ))
        .modifier(PoseEffect(
            deformation: controller.curiosityPose,
            isActive: controller.state == .curious,
            releaseAnimation: poseAnimation
        ))
        .modifier(PoseEffect(
            deformation: controller.floatDeformation,
            isActive: controller.state == .float,
            releaseAnimation: poseAnimation
        ))
        .scaleEffect(x: stateScaleX, y: stateScaleY, anchor: .bottom)
        .animation(poseAnimation, value: controller.state)
        .animation(poseAnimation, value: controller.hopProgress)
        .animation(poseAnimation, value: controller.settleProgress)
        .animation(poseAnimation, value: controller.floatProgress)
    }

    private var bobOffset: CGFloat {
        // The bottle is completely static: no idle bob while any part
        // of the bottle form (or its frozen silhouette) is visible —
        // the poof timeline's own jump/landing is the only motion.
        guard !(visual?.isBottleForm ?? false) else { return 0 }
        return controller.state == .idle ? (bobbing ? -6 : 6) : 0
    }

    /// Continuous expression inputs for the layered character system:
    /// event attention (birthday) overrides the mouse-driven gaze when
    /// active, so the pet can visibly "look at" something specific.
    private var expressionInputs: WarawaraExpressionInputs {
        // The bottle form is a hidden step (0/1) — the face/body
        // handover happens behind full occlusion smoke.
        let form: CGFloat
        if let visual, visual.isBottleForm {
            form = CGFloat(visual.formProgress)
        } else {
            form = 0
        }
        return WarawaraExpressionInputs(
            state: controller.state,
            gaze: controller.eventAttentionDirection ?? controller.curiosityDirection,
            dragDeformation: controller.dragDeformation,
            hopProgress: controller.hopProgress,
            floatProgress: controller.floatProgress,
            wishingEyes: controller.wishing,
            bottleMorphProgress: form
        )
    }

    /// The layered character renderer owns ALL breathing (single
    /// responsibility): its continuous breath-phase accumulator drives a
    /// gentle, deeper-asleep body scale inside the character view. The
    /// outer pipeline only applies the state pose squash below.
    private var stateScaleX: CGFloat {
        switch controller.state {
        case .idle, .dragged, .curious, .float:
            return 1
        case .clicked:
            return 1.04
        case .hop:
            return 1 - 0.08 * HopCurve.stretchFactor(at: controller.hopProgress)
                + 0.15 * HopCurve.squashAtLanding(at: controller.hopProgress)
        case .settling:
            return 1 + 0.1 * (1 - controller.settleProgress)
        case .sleepy:
            return 1.02
        case .sleeping:
            return 1.03
        }
    }

    private var stateScaleY: CGFloat {
        switch controller.state {
        case .idle, .dragged, .curious, .float:
            return 1
        case .clicked:
            return 0.78
        case .hop:
            return 1 + 0.12 * HopCurve.stretchFactor(at: controller.hopProgress)
                - 0.3 * HopCurve.squashAtLanding(at: controller.hopProgress)
        case .settling:
            return 1 - 0.2 * (1 - controller.settleProgress)
        case .sleepy:
            return 0.93
        case .sleeping:
            return 0.88
        }
    }
}

/// Applies a PetDeformation around its anchor: torque rotation, rotate to
/// the stretch axis, directional scale, rotate back. While `isActive` the
/// values apply instantly (no per-event animation stacking); when it flips
/// inactive the scoped spring returns everything to neutral.
private struct PoseEffect: ViewModifier {
    let deformation: PetDeformation
    let isActive: Bool
    let releaseAnimation: Animation

    func body(content: Content) -> some View {
        content
            .rotationEffect(.radians(Double(deformation.rotation)), anchor: anchorUnit)
            .rotationEffect(.radians(Double(deformation.stretchAngle)), anchor: anchorUnit)
            .scaleEffect(x: deformation.stretchScale, y: deformation.perpendicularScale, anchor: anchorUnit)
            .rotationEffect(.radians(-Double(deformation.stretchAngle)), anchor: anchorUnit)
            .animation(releaseAnimation, value: isActive)
    }

    private var anchorUnit: UnitPoint {
        UnitPoint(
            x: 0.5 + 0.5 * Double(deformation.anchor.dx),
            y: 0.5 - 0.5 * Double(deformation.anchor.dy)
        )
    }
}

/// The sleeping "Z" rises from just ABOVE the head (head top is fixed at
/// blobBottomPadding + blobHeight below the window top for both the rig
/// and the legacy renderers), then drifts further upward and fades.
private struct SleepIndicatorView: View {
    @State private var rising = false

    var body: some View {
        Text("Z")
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundColor(Color(white: 0.55))
            .position(
                x: PetMetrics.size.width / 2 + 22,
                y: PetMetrics.sleepZBaseY
            )
            .offset(y: rising ? -30 : 0)
            .opacity(rising ? 0 : 0.7)
            .onAppear { rising = true }
            .animation(.easeOut(duration: 2.8).repeatForever(autoreverses: false), value: rising)
    }
}
