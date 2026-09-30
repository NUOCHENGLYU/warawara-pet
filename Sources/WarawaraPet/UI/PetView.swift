import SwiftUI

struct PetView: View {
    @State private var bobbing = false

    private let bobAnimation = Animation
        .easeInOut(duration: 2.2)
        .repeatForever(autoreverses: true)

    var body: some View {
        ZStack {
            bodyBlob
                .offset(y: bobbing ? -6 : 6)
            eyes
                .offset(y: (bobbing ? -6 : 6) - 10)
        }
        .frame(width: 160, height: 160, alignment: .bottom)
        .animation(bobAnimation, value: bobbing)
        .onAppear { bobbing = true }
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
    }
}

private struct EyeView: View {
    var body: some View {
        Circle()
            .fill(Color(white: 0.15))
            .frame(width: 9, height: 11)
    }
}
