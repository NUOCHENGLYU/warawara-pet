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
                    .offset(x: 22, y: 42)
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
        ZStack {
            bodyBlob
            eyes
        }
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

    private var bodyBlob: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.98), Color(white: 0.86)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 96, height: 118)
            .overlay(Capsule().stroke(Color(white: 0.55), lineWidth: 1.5))
            .padding(.bottom, PetMetrics.blobBottomPadding)
    }

    private var eyes: some View {
        HStack(spacing: 34) {
            EyeView()
            EyeView()
        }
        .offset(y: 62)
    }

    private var bobOffset: CGFloat {
        controller.state == .idle ? (bobbing ? -6 : 6) : 0
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

private struct SleepIndicatorView: View {
    @State private var rising = false

    var body: some View {
        Text("Z")
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundColor(Color(white: 0.55))
            .opacity(rising ? 0 : 0.7)
            .offset(y: rising ? 26 : 0)
            .onAppear { rising = true }
            .animation(.easeOut(duration: 2.8).repeatForever(autoreverses: false), value: rising)
    }
}

private struct EyeView: View {
    var body: some View {
        Circle()
            .fill(Color(white: 0.15))
            .frame(width: 9, height: 11)
    }
}
