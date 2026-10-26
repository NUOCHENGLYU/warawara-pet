import SwiftUI

/// Procedural placeholder bottle visuals for Phase 8C. The morph is
/// driven entirely by `morphProgress` (0 = Warawara, 1 = bottle) and
/// `openingProgress` (0 = sealed, 1 = cork out + paper unrolled).
///
/// ART INTEGRATION POINT (Phase 8C art handoff): the sender will
/// provide transparent PNG layers + SVG sources
/// (`Warawara_BottleMail_Phase8C_Art_v1.zip`). When the art lands,
/// replace the shapes below with the delivered layers — the parameters
/// (morphProgress / openingProgress) and the layer ORDER (glass behind
/// the rig body, neck/cork/paper in front, face on top) are the
/// contract. Do NOT treat these placeholders as the final design.
enum BottleMetrics {
    static let glassWidth: CGFloat = 104
    /// Body glass height: the rig body height (118) times the morph
    /// squash (1.06).
    static let glassHeight: CGFloat = 118 * 1.06
    static let neckWidth: CGFloat = 26
    static let neckHeight: CGFloat = 22
    static let rimWidth: CGFloat = 30
    static let rimHeight: CGFloat = 4
    static let corkWidth: CGFloat = 20
    static let corkHeight: CGFloat = 9
    static let corkLift: CGFloat = 10
    static let paperWidth: CGFloat = 36
    static let paperHeight: CGFloat = 52
    /// Sway and bob slack kept inside the window top.
    static let swayExtra: CGFloat = 6
    static let bobExtra: CGFloat = 6
    /// Total height of the front layer (rim + neck + cork + lift),
    /// bottom-anchored at the glass top.
    static var extrasContainerHeight: CGFloat {
        rimHeight + neckHeight + corkHeight + corkLift
    }

    /// Distance from the body center (visual center) up to the highest
    /// point the bottle can ever reach (rim + raised cork + sway + bob).
    static func maximumTopReach() -> CGFloat {
        glassHeight / 2 + rimHeight + neckHeight + corkHeight + corkLift + swayExtra + bobExtra
    }

    /// The bottle must never be clipped by the window top: the headroom
    /// above the resting body center must absorb the full envelope.
    static func fitsInWindow() -> Bool {
        maximumTopReach() <= PetMetrics.visualCenter.y
    }
}

/// The translucent glass body, drawn BEHIND the rig body. The rig body
/// fades out through `bodyOpacity` while this fades in, so the warm
/// white body hands over to light blue-gray glass with the eyes and
/// mouth still on top.
struct BottleGlassBodyView: View {
    /// Eased morph progress 0...1.
    let progress: Double

    private var glassOpacity: Double {
        // The glass fades in only after the body has started to hand
        // over, so the two silhouettes never double up.
        let ramp = min(max((progress - 0.15) / 0.6, 0), 1)
        return 0.8 * ramp
    }

    var body: some View {
        BottleGlassShape()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.76, green: 0.84, blue: 0.91).opacity(0.34),
                        Color(red: 0.66, green: 0.76, blue: 0.86).opacity(0.44)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(BottleGlassShape().stroke(Color(white: 1).opacity(0.5), lineWidth: 1.2))
            .frame(width: BottleMetrics.glassWidth, height: BottleMetrics.glassHeight)
            .overlay(alignment: .leading) {
                // Thin soft highlight, low saturation.
                Capsule()
                    .fill(Color(white: 1).opacity(0.22))
                    .frame(width: 7, height: BottleMetrics.glassHeight * 0.62)
                    .offset(x: 12)
            }
            .opacity(glassOpacity)
    }
}

/// Neck, rim, cork and the rolled paper — drawn IN FRONT of the
/// character so the bottle reads above the body. Bottom-anchored: the
/// container's bottom edge sits on the glass top.
struct BottleExtrasView: View {
    /// Eased morph progress 0...1.
    let progress: Double
    /// 0 = sealed, 1 = cork lifted + paper unrolled.
    let openingProgress: Double

    /// Neck/cork/paper appear only in the last segment of the morph
    /// ("the neck grows upward as the morph completes").
    private var extrasOpacity: Double {
        min(max((progress - 0.55) / 0.45, 0), 1)
    }

    /// The neck grows from the glass top, matching the extras fade.
    private var neckGrow: CGFloat {
        CGFloat(BottleMorphMath.eased(min(max((progress - 0.55) / 0.45, 0), 1)))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            neckAndRim
            cork
            paper
        }
        .frame(
            width: BottleMetrics.rimWidth,
            height: BottleMetrics.extrasContainerHeight,
            alignment: .bottom
        )
        .opacity(extrasOpacity)
    }

    private var neckAndRim: some View {
        VStack(spacing: 0) {
            rim
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.72, green: 0.81, blue: 0.89).opacity(0.42),
                            Color(red: 0.62, green: 0.73, blue: 0.84).opacity(0.5)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color(white: 1).opacity(0.5), lineWidth: 1)
                )
                .frame(width: BottleMetrics.neckWidth,
                       height: BottleMetrics.neckHeight * neckGrow)
        }
    }

    private var rim: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color(red: 0.62, green: 0.73, blue: 0.84).opacity(0.55))
            .overlay(
                RoundedRectangle(cornerRadius: 1.5)
                    .stroke(Color(white: 1).opacity(0.5), lineWidth: 1)
            )
            .frame(width: BottleMetrics.rimWidth, height: BottleMetrics.rimHeight)
    }

    private var cork: some View {
        // The cork lifts as the bottle opens; sealed while idle.
        RoundedRectangle(cornerRadius: 3)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.83, green: 0.70, blue: 0.52), Color(red: 0.70, green: 0.56, blue: 0.40)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: BottleMetrics.corkWidth, height: BottleMetrics.corkHeight)
            .offset(y: -(BottleMetrics.rimHeight + BottleMetrics.neckHeight * neckGrow)
                        + BottleMetrics.corkLift * CGFloat(openingProgress))
    }

    private var paper: some View {
        // The rolled letter peeks out of the neck and unrolls on open.
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(red: 0.96, green: 0.93, blue: 0.85))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(white: 0.75), lineWidth: 0.8)
            )
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color(red: 0.72, green: 0.45, blue: 0.40).opacity(0.9))
                    .frame(width: 5, height: 5)
                    .padding(4)
            }
            .frame(
                width: BottleMetrics.paperWidth * CGFloat(0.6 + 0.4 * openingProgress),
                height: BottleMetrics.paperHeight * CGFloat(0.25 + 0.75 * openingProgress)
            )
            .offset(y: -(BottleMetrics.rimHeight + BottleMetrics.neckHeight * neckGrow)
                        - 4 - 0.5 * BottleMetrics.paperHeight
                            * CGFloat(0.25 + 0.75 * openingProgress))
            .opacity(0.35 + 0.65 * openingProgress)
    }
}

/// The glass silhouette: a rounded flask — wider base, curved shoulder.
struct BottleGlassShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        // Wide rounded base rising to a gentle shoulder.
        path.move(to: CGPoint(x: 0, y: h * 0.72))
        path.addCurve(
            to: CGPoint(x: w * 0.18, y: h * 0.12),
            control1: CGPoint(x: 0, y: h * 0.38),
            control2: CGPoint(x: w * 0.06, y: h * 0.2)
        )
        path.addLine(to: CGPoint(x: w * 0.82, y: h * 0.12))
        path.addCurve(
            to: CGPoint(x: w, y: h * 0.72),
            control1: CGPoint(x: w * 0.94, y: h * 0.2),
            control2: CGPoint(x: w, y: h * 0.38)
        )
        path.addQuadCurve(
            to: CGPoint(x: 0, y: h * 0.72),
            control: CGPoint(x: w * 0.5, y: h * 1.06)
        )
        path.closeSubpath()
        return path
    }
}
