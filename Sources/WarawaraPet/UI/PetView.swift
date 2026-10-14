import SwiftUI

struct PetView: View {
    @ObservedObject var controller: PetController

    @State private var bobbing = false
    @State private var breathingPhase = false

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

    private var breathingAnimation: Animation {
        .easeInOut(duration: PersonalityTuning.default.breathingPeriod)
            .repeatForever(autoreverses: true)
    }

    var body: some View {
        ZStack {
            petGroup
                .offset(y: bobOffset)
            if controller.state == .sleeping {
                SleepIndicatorView()
            }
        }
        .frame(width: 200, height: 226, alignment: .bottom)
        .animation(bobAnimation, value: bobbing)
        .onAppear {
            bobbing = true
            breathingPhase = true
        }
        .onChange(of: controller.state) { newState in
            if newState == .sleepy || newState == .sleeping {
                // Re-trigger the breathing oscillation each sleep entry.
                breathingPhase = false
                DispatchQueue.main.async { self.breathingPhase = true }
            }
        }
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
        .scaleEffect(breathingScale, anchor: .bottom)
        .animation(breathingAnimation, value: breathingPhase)
        .animation(poseAnimation, value: controller.state)
        .animation(poseAnimation, value: controller.hopProgress)
        .animation(poseAnimation, value: controller.settleProgress)
        .animation(poseAnimation, value: controller.floatProgress)
    }

    private var bobOffset: CGFloat {
        controller.state == .idle ? (bobbing ? -6 : 6) : 0
    }

    /// Continuous expression inputs for the layered character system:
    /// state, smoothed cursor direction, live drag deformation and motion
    /// progress. The expression driver adds time-derived breath/blink.
    private var expressionInputs: WarawaraExpressionInputs {
        WarawaraExpressionInputs(
            state: controller.state,
            gaze: controller.curiosityDirection,
            dragDeformation: controller.dragDeformation,
            hopProgress: controller.hopProgress,
            floatProgress: controller.floatProgress
        )
    }

    private var breathingScale: CGFloat {
        guard controller.state == .sleepy || controller.state == .sleeping else { return 1 }
        return breathingPhase ? 1.02 : 0.99
    }

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
