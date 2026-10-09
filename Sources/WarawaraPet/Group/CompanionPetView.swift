import SwiftUI

/// Placeholder companion Warawara: the same procedural blob language as
/// the main pet, rendered smaller with a per-companion scale so the
/// choreography is judgeable. Final artwork replaces this later.
struct CompanionPetView: View {
    let scale: CGFloat

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.97), Color(white: 0.84)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 60, height: 74)
            .overlay(Capsule().stroke(Color(white: 0.5), lineWidth: 1.2))
            .overlay(
                HStack(spacing: 22) {
                    Circle().fill(Color(white: 0.18)).frame(width: 6, height: 7)
                    Circle().fill(Color(white: 0.18)).frame(width: 6, height: 7)
                }
                .offset(y: 10),
                alignment: .center
            )
            .scaleEffect(scale, anchor: .bottom)
            .frame(width: 96, height: 96, alignment: .bottom)
    }
}
