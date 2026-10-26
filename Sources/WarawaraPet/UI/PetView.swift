import SwiftUI

struct PetView: View {
    @ObservedObject var controller: PetController
    @ObservedObject var bottleVisualProvider: BottleVisualProvider

    @State private var bobbing = false
    @State private var bottleSwaying = false

    private let bobAnimation = Animation
        .easeInOut(duration: 2.2)
        .repeatForever(autoreverses: true)

    private let bottleSwayAnimation = Animation
        .easeInOut(duration: 4.2)
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
        ZStack {
            // The whole bottle reads as ONE body: the bottle art and the
            // character share the bob and the gentle floating tilt.
            ZStack {
                petGroup
                // The bottle form renders IN FRONT of the fading rig:
                // the v3 art (or the procedural fallback) grows out of
                // the body silhouette while the face dissolves.
                if let visual, visual.isBottleForm {
                    BottleArtOverlayView(visual: visual, store: .shared)
                        .scaleEffect(x: stateScaleX, y: stateScaleY, anchor: .bottom)
                }
            }
            .offset(y: bobOffset)
            .rotationEffect(.radians(bottleSwayAngle), anchor: .bottom)
            .animation(bottleSwayAnimation, value: bottleSwaying)

            if controller.state == .sleeping {
                SleepIndicatorView()
            }
        }
        .frame(width: 200, height: 226, alignment: .bottom)
        .animation(bobAnimation, value: bobbing)
        .onAppear {
            bobbing = true
            bottleSwaying = true
        }
    }

    /// Gentle floating tilt while the bottle waits (disabled under
    /// Reduce Motion — the morph itself still plays).
    private var bottleSwayAngle: Double {
        guard visual?.swayEnabled == true else { return 0 }
        return bottleSwaying ? 0.021 : -0.021
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
        controller.state == .idle ? (bobbing ? -6 : 6) : 0
    }

    /// Continuous expression inputs for the layered character system:
    /// event attention (birthday) overrides the mouse-driven gaze when
    /// active, so the pet can visibly "look at" something specific.
    private var expressionInputs: WarawaraExpressionInputs {
        let morph: CGFloat
        if let visual, visual.isBottleForm {
            morph = CGFloat(visual.morphProgress)
        } else {
            morph = 0
        }
        return WarawaraExpressionInputs(
            state: controller.state,
            gaze: controller.eventAttentionDirection ?? controller.curiosityDirection,
            dragDeformation: controller.dragDeformation,
            hopProgress: controller.hopProgress,
            floatProgress: controller.floatProgress,
            wishingEyes: controller.wishing,
            bottleMorphProgress: morph
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
