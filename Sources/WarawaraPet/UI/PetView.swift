import SwiftUI

struct PetView: View {
    @ObservedObject var controller: PetController

    @State private var bobbing = false

    private let bobAnimation = Animation
        .easeInOut(duration: 2.2)
        .repeatForever(autoreverses: true)

    private let poseAnimation = Animation
        .spring(response: 0.3, dampingFraction: 0.55)

    private let deformationReleaseAnimation = Animation
        .spring(
            response: DeformationTuning.default.releaseSpringResponse,
            dampingFraction: DeformationTuning.default.releaseSpringDamping
        )

    var body: some View {
        ZStack {
            petGroup
                .offset(y: bobOffset)
        }
        .frame(width: 160, height: 160, alignment: .bottom)
        .animation(bobAnimation, value: bobbing)
        .onAppear { bobbing = true }
    }

    private var petGroup: some View {
        ZStack {
            bodyBlob
            eyes
        }
        .modifier(DeformationEffect(
            deformation: controller.dragDeformation,
            isDragging: controller.state == .dragged,
            releaseAnimation: deformationReleaseAnimation
        ))
        .scaleEffect(x: stateScaleX, y: stateScaleY, anchor: .bottom)
        .animation(poseAnimation, value: controller.state)
        .animation(poseAnimation, value: controller.hopProgress)
        .animation(poseAnimation, value: controller.settleProgress)
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
            .padding(.bottom, 6)
    }

    private var eyes: some View {
        HStack(spacing: 34) {
            EyeView()
            EyeView()
        }
        .offset(y: 34)
    }

    private var bobOffset: CGFloat {
        controller.state == .idle ? (bobbing ? -6 : 6) : 0
    }

    private var stateScaleX: CGFloat {
        switch controller.state {
        case .idle, .dragged:
            return 1
        case .clicked:
            return 1.04
        case .hop:
            return 1 - 0.08 * HopCurve.stretchFactor(at: controller.hopProgress)
                + 0.15 * HopCurve.squashAtLanding(at: controller.hopProgress)
        case .settling:
            return 1 + 0.1 * (1 - controller.settleProgress)
        }
    }

    private var stateScaleY: CGFloat {
        switch controller.state {
        case .idle, .dragged:
            return 1
        case .clicked:
            return 0.78
        case .hop:
            return 1 + 0.12 * HopCurve.stretchFactor(at: controller.hopProgress)
                - 0.3 * HopCurve.squashAtLanding(at: controller.hopProgress)
        case .settling:
            return 1 - 0.2 * (1 - controller.settleProgress)
        }
    }
}

/// Applies the drag deformation around the grab anchor: torque rotation,
/// rotate to the stretch axis, directional scale, rotate back. During drag
/// the values apply instantly (no per-event animation stacking); when the
/// drag ends, the scoped release spring returns everything to neutral. As
/// the deformation approaches identity the anchor ceases to matter.
private struct DeformationEffect: ViewModifier {
    let deformation: PetDeformation
    let isDragging: Bool
    let releaseAnimation: Animation

    func body(content: Content) -> some View {
        content
            .rotationEffect(.radians(Double(deformation.rotation)), anchor: anchorUnit)
            .rotationEffect(.radians(Double(deformation.stretchAngle)), anchor: anchorUnit)
            .scaleEffect(x: deformation.stretchScale, y: deformation.perpendicularScale, anchor: anchorUnit)
            .rotationEffect(.radians(-Double(deformation.stretchAngle)), anchor: anchorUnit)
            .animation(releaseAnimation, value: isDragging)
    }

    private var anchorUnit: UnitPoint {
        UnitPoint(
            x: 0.5 + 0.5 * Double(deformation.anchor.dx),
            y: 0.5 - 0.5 * Double(deformation.anchor.dy)
        )
    }
}

private struct EyeView: View {
    var body: some View {
        Circle()
            .fill(Color(white: 0.15))
            .frame(width: 9, height: 11)
    }
}
