import SwiftUI

/// Prop content for the shared seasonal scenes: primary prop with
/// content-aware sizing, optional secondary decorations, and gentle
/// scene-appropriate motion (sway / glide handled by the presenter's
/// panel path; here only in-panel life).
struct SeasonalPropView: View {
    let kind: SeasonalEventKind
    let store: SeasonalAssetStore
    let primarySize: CGFloat
    var showSecondary: Bool = false

    @State private var alive = false

    var body: some View {
        ZStack {
            if showSecondary {
                secondaryDecorations
            }
            if let image = store.image(named: kind.primaryAsset) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: primarySize, height: primarySize)
                    .scaleEffect(alive ? 1 : 0.92)
            }
        }
        .offset(y: alive ? 0 : -4)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9)) {
                alive = true
            }
        }
    }

    /// Secondary + decorative props with fixed per-slot offsets so every
    /// scene's decoration is visible (CNY lantern/plum/firecrackers,
    /// Christmas wreath, New Year popper).
    @ViewBuilder
    private var secondaryDecorations: some View {
        ForEach(Array(kind.secondaryAssets.enumerated()), id: \.offset) { index, name in
            if let image = store.image(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: primarySize * 0.9, height: primarySize * 0.9)
                    .offset(secondaryOffset(index: index))
                    .opacity(alive ? 0.9 : 0.25)
            }
        }
        ForEach(Array(kind.decorativeAssets.enumerated()), id: \.offset) { index, name in
            if let image = store.image(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: primarySize * 0.95, height: primarySize * 0.95)
                    .offset(decorativeOffset(index: index))
                    .opacity(alive ? 0.95 : 0.25)
            }
        }
    }

    private func secondaryOffset(index: Int) -> CGSize {
        switch index {
        case 0: return CGSize(width: primarySize * 0.55, height: -primarySize * 0.45)
        case 1: return CGSize(width: -primarySize * 0.55, height: -primarySize * 0.35)
        default: return CGSize(width: 0, height: -primarySize * 0.55)
        }
    }

    private func decorativeOffset(index: Int) -> CGSize {
        CGSize(width: CGFloat(index) * primarySize * 0.9 - primarySize * 0.45,
               height: primarySize * 0.5)
    }
}

/// Pure scene-motion math: the prop panel's approach/glide path.
enum SeasonalMotionMath {
    /// Parametric glide for the paper airplane: a smooth S-curve across
    /// the pet, from left-below to right-above. t in 0...1.
    static func paperAirplanePosition(
        t: CGFloat,
        from: CGPoint,
        to: CGPoint
    ) -> CGPoint {
        let eased = easeInOut(t)
        let dx = to.x - from.x
        let dy = to.y - from.y
        // Gentle arc: lift in the middle of the travel.
        let arc = sin(.pi * eased) * 30
        return CGPoint(
            x: from.x + dx * eased,
            y: from.y + dy * eased + arc
        )
    }

    /// Smooth approach easing (quadratic ease-out).
    static func approachPosition(t: CGFloat, from: CGPoint, to: CGPoint) -> CGPoint {
        let eased = 1 - (1 - min(max(t, 0), 1)) * (1 - min(max(t, 0), 1))
        return CGPoint(
            x: from.x + (to.x - from.x) * eased,
            y: from.y + (to.y - from.y) * eased
        )
    }

    static func easeInOut(_ t: CGFloat) -> CGFloat {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }
}
