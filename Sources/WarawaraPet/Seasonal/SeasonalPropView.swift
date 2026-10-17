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
                let contact = PropRenderGeometry.contactPoint(for: kind)
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(
                        width: PropRenderGeometry.canvasPt(asset: kind.primaryAsset),
                        height: PropRenderGeometry.canvasPt(asset: kind.primaryAsset)
                    )
                    .offset(PropRenderGeometry.canvasOffset(
                        asset: kind.primaryAsset, fx: contact.x, fy: contact.y, at: .zero
                    ))
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
        let primaryRect = PropRenderGeometry.primaryContentRectInPanel(for: kind)
        let center = CGPoint(x: primaryRect.midX, y: primaryRect.midY)
        ForEach(PropRenderGeometry.decorations(for: kind), id: \.asset) { deco in
            if let image = store.image(named: deco.asset) {
                let decoCenter = CGPoint(
                    x: center.x + deco.dxFrac * primaryRect.width,
                    y: center.y - deco.dyFrac * primaryRect.height
                )
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(
                        width: PropRenderGeometry.canvasPt(asset: deco.asset),
                        height: PropRenderGeometry.canvasPt(asset: deco.asset)
                    )
                    .offset(PropRenderGeometry.canvasOffset(
                        asset: deco.asset, fx: 0.5, fy: 0.5, at: decoCenter
                    ))
                    .opacity(alive ? 0.9 : 0.25)
            }
        }
    }
}

/// Production scene renderer: draws the choreography pose through the
/// authoritative `PropRenderGeometry` (one scale per asset, contact
/// point at the panel center). All painted content — primary, open
/// layers, decorations, trail — stays inside the computed extents.
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
                        width: PropRenderGeometry.canvasPt(asset: "paper_airplane_trail.png"),
                        height: PropRenderGeometry.canvasPt(asset: "paper_airplane_trail.png")
                    )
                    .offset(PropRenderGeometry.canvasOffset(
                        asset: "paper_airplane_trail.png",
                        fx: 0.5, fy: 0.5,
                        at: CGPoint(
                            x: PropRenderGeometry.trailRectInPanel().midX,
                            y: PropRenderGeometry.trailRectInPanel().midY
                        )
                    ))
                    .opacity(0.6)
            }
            if model.pose.lidLift > 0 {
                giftOpenLayers
            } else if let image = store.optionalImage(named: model.pose.asset) {
                primaryImage(image, asset: model.pose.asset)
            }
            decorations
        }
        .scaleEffect(model.pose.scale)
        .rotationEffect(.degrees(Double(model.pose.rotationDegrees)))
        .opacity(Double(model.pose.alpha))
    }

    private func primaryImage(_ image: NSImage, asset: String) -> some View {
        let contact = PropRenderGeometry.contactPoint(for: kind)
        return Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(
                width: PropRenderGeometry.canvasPt(asset: asset),
                height: PropRenderGeometry.canvasPt(asset: asset)
            )
            .offset(PropRenderGeometry.canvasOffset(
                asset: asset, fx: contact.x, fy: contact.y, at: .zero
            ))
    }

    /// The gift lid rises from the open base on its own layer (lidLift
    /// 0...1 already eased by the choreography), sharing the closed
    /// gift's contact so body and lid stay aligned.
    @ViewBuilder
    private var giftOpenLayers: some View {
        let lift = model.pose.lidLift
        if let base = store.optionalImage(named: "xmas_gift_open_base.png") {
            Image(nsImage: base)
                .resizable()
                .interpolation(.high)
                .frame(
                    width: PropRenderGeometry.canvasPt(asset: "xmas_gift_open_base.png"),
                    height: PropRenderGeometry.canvasPt(asset: "xmas_gift_open_base.png")
                )
                .offset(PropRenderGeometry.canvasOffset(
                    asset: "xmas_gift_open_base.png",
                    fx: 0.5, fy: 0,
                    at: .zero
                ))
        }
        if let lid = store.optionalImage(named: "xmas_gift_lid.png") {
            let lidRect = PropRenderGeometry.giftOpenRectsInPanel(lidLift: lift).lid
            Image(nsImage: lid)
                .resizable()
                .interpolation(.high)
                .frame(
                    width: PropRenderGeometry.canvasPt(asset: "xmas_gift_lid.png"),
                    height: PropRenderGeometry.canvasPt(asset: "xmas_gift_lid.png")
                )
                .offset(PropRenderGeometry.canvasOffset(
                    asset: "xmas_gift_lid.png",
                    fx: 0.5, fy: 0.5,
                    at: CGPoint(x: lidRect.midX, y: lidRect.midY)
                ))
                .rotationEffect(.degrees(Double(lift * 10)))
        }
    }

    private var decorations: some View {
        let primaryRect = PropRenderGeometry.primaryContentRectInPanel(for: kind)
        let primaryCenter = CGPoint(x: primaryRect.midX, y: primaryRect.midY)
        return ZStack {
            ForEach(PropRenderGeometry.decorations(for: kind), id: \.asset) { deco in
                if let image = store.image(named: deco.asset) {
                    let size = PropRenderGeometry.contentSizePt(asset: deco.asset)
                    let center = CGPoint(
                        x: primaryCenter.x + deco.dxFrac * primaryRect.width,
                        y: primaryCenter.y - deco.dyFrac * primaryRect.height
                    )
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(
                            width: PropRenderGeometry.canvasPt(asset: deco.asset),
                            height: PropRenderGeometry.canvasPt(asset: deco.asset)
                        )
                        .offset(PropRenderGeometry.canvasOffset(
                            asset: deco.asset, fx: 0.5, fy: 0.5, at: center
                        ))
                }
            }
        }
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
                let canvas = PropRenderGeometry.canvasPt(asset: model.asset)
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: canvas, height: canvas)
                    .offset(PropRenderGeometry.canvasOffset(
                        asset: model.asset, fx: 0.5, fy: 0.5, at: .zero
                    ))
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
