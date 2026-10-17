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

/// Production scene renderer: draws the choreography pose (primary asset
/// or layered open states), decorations, and effect overlays. The panel
/// centers on the pose's CONTACT point; `SeasonalSceneMath.contentOffset`
/// places the painted content exactly there.
struct SeasonalSceneView: View {
    let kind: SeasonalEventKind
    let store: SeasonalAssetStore
    @ObservedObject var model: SeasonalSceneModel

    var body: some View {
        ZStack {
            if model.pose.showTrail,
               let trail = store.optionalImage(named: "paper_airplane_trail.png") {
                Image(nsImage: trail)
                    .resizable()
                    .interpolation(.high)
                    .frame(
                        width: kind.primaryDisplayPoints * 1.6,
                        height: kind.primaryDisplayPoints * 0.6
                    )
                    .offset(x: -kind.primaryDisplayPoints * 0.9, y: 0)
                    .opacity(0.6)
            }
            if model.pose.lidLift > 0 {
                giftOpenLayers
            } else if let image = store.optionalImage(named: model.pose.asset) {
                primaryImage(image)
            }
            decorations
        }
        .scaleEffect(model.pose.scale)
        .rotationEffect(.degrees(Double(model.pose.rotationDegrees)))
        .opacity(Double(model.pose.alpha))
    }

    private func primaryImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: kind.primaryDisplayPoints, height: kind.primaryDisplayPoints)
            .offset(SeasonalSceneMath.contentOffset(for: kind))
    }

    /// The gift lid rises from the open base on its own layer (lidLift
    /// 0...1 already eased by the choreography).
    @ViewBuilder
    private var giftOpenLayers: some View {
        let lift = model.pose.lidLift
        if let base = store.optionalImage(named: "xmas_gift_open_base.png") {
            Image(nsImage: base)
                .resizable()
                .interpolation(.high)
                .frame(width: kind.primaryDisplayPoints, height: kind.primaryDisplayPoints)
                .offset(SeasonalSceneMath.contentOffset(
                    asset: "xmas_gift_open_base.png",
                    contact: CGPoint(x: 0, y: -0.5),
                    displayPoints: kind.primaryDisplayPoints
                ))
                .offset(y: 4)
        }
        if let lid = store.optionalImage(named: "xmas_gift_lid.png") {
            Image(nsImage: lid)
                .resizable()
                .interpolation(.high)
                .frame(width: kind.primaryDisplayPoints, height: kind.primaryDisplayPoints)
                .offset(SeasonalSceneMath.contentOffset(
                    asset: "xmas_gift_lid.png",
                    contact: CGPoint(x: 0, y: -0.5),
                    displayPoints: kind.primaryDisplayPoints
                ))
                .offset(x: lift * 14, y: -lift * 26)
                .rotationEffect(.degrees(Double(lift * 10)))
        }
    }

    private var decorations: some View {
        ZStack {
            ForEach(SeasonalSceneMath.decorations(for: kind), id: \.asset) { deco in
                if let image = store.image(named: deco.asset) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(
                            width: kind.primaryDisplayPoints * deco.sizeFraction,
                            height: kind.primaryDisplayPoints * deco.sizeFraction
                        )
                        .offset(
                            x: deco.dxFraction * kind.primaryDisplayPoints,
                            y: deco.dyFraction * kind.primaryDisplayPoints
                        )
                }
            }
        }
        .offset(SeasonalSceneMath.contentOffset(for: kind))
    }
}

/// Effect overlay renderer for the second pooled panel (imaginary rain,
/// confetti). Click-through by design — the hosting panel ignores mouse
/// events.
struct SeasonalEffectView: View {
    let store: SeasonalAssetStore
    @ObservedObject var model: SeasonalEffectModel

    var body: some View {
        ZStack {
            if model.alpha > 0, let image = store.optionalImage(named: model.asset) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 300, height: 300)
                    .opacity(Double(model.alpha))
            }
        }
        .frame(width: 320, height: 320)
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
