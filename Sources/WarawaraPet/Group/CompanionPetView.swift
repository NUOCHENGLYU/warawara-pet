import SwiftUI

/// Publishable companion pose: velocity-driven deformation plus a subtle
/// breathing scale. Updated by GroupSequenceController each tick.
final class CompanionPoseModel: ObservableObject {
    @Published var deformation: PetDeformation = .neutral
    @Published var breathing: CGFloat = 1
}

/// Placeholder companion Warawara: the same procedural blob language as
/// the main pet. The body is CENTERED in a canvas large enough to contain
/// its maximum silhouette (scale + stretch + lean), so panel-center
/// coordinates equal body-center coordinates and nothing ever clips.
/// Final artwork replaces this later.
struct CompanionPetView: View {
    let scale: CGFloat
    @ObservedObject var pose: CompanionPoseModel

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.97), Color(white: 0.84)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: CompanionMetrics.blobWidth, height: CompanionMetrics.blobHeight)
            .overlay(Capsule().stroke(Color(white: 0.5), lineWidth: 1.2))
            .overlay(
                HStack(spacing: 22) {
                    Circle().fill(Color(white: 0.18)).frame(width: 6, height: 7)
                    Circle().fill(Color(white: 0.18)).frame(width: 6, height: 7)
                }
                .offset(y: 10),
                alignment: .center
            )
            .scaleEffect(scale, anchor: .center)
            .modifier(CompanionPoseEffect(deformation: pose.deformation))
            .scaleEffect(pose.breathing, anchor: .center)
            .frame(width: CompanionMetrics.size, height: CompanionMetrics.size)
    }
}

/// Applies a PetDeformation around the body center: rotate to the stretch
/// axis, directional scale, rotate back, plus the gentle lean rotation.
private struct CompanionPoseEffect: ViewModifier {
    let deformation: PetDeformation

    func body(content: Content) -> some View {
        content
            .rotationEffect(.radians(Double(deformation.rotation)), anchor: .center)
            .rotationEffect(.radians(Double(deformation.stretchAngle)), anchor: .center)
            .scaleEffect(x: deformation.stretchScale, y: deformation.perpendicularScale, anchor: .center)
            .rotationEffect(.radians(-Double(deformation.stretchAngle)), anchor: .center)
    }
}
