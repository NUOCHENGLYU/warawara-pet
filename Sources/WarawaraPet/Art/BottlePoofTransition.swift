import SwiftUI

/// Phase 8C "poof" transition choreography (pure, testable):
/// anticipation squash -> hop up -> smoke "poof" -> HIDDEN asset swap ->
/// smoke dissipates while the bottle descends -> soft landing.
///
/// Timeline `t` is 0...1 over the total transition duration (1.35 s).
/// The same function of `t` drives BOTH directions (reverse = t runs
/// 1 -> 0), so the choreography is mirrored by construction.
///
/// OCCLUSION INVARIANT: the underlying asset swap happens exactly at
/// `switchPoint`, where the core smoke is fully opaque and covers the
/// union envelope of both silhouettes — the swap is never visible.
/// `occludedRect` is the machine-checkable statement of that rule.
enum BottlePoofTimeline {
    /// Total transition duration (seconds).
    static let duration: TimeInterval = 1.35

    /// Timeline instants (seconds -> fraction of the timeline). These
    /// are Double — the CGFloat functions below convert locally.
    static let anticipationEnd = 0.15 / 1.35            // 0.111
    static let poofPoint = 0.43 / 1.35                  // 0.3185
    static let switchPoint = 0.57 / 1.35                // 0.4222
    static let descentEnd = 1.03 / 1.35                 // 0.763
    static let smokeFadeEnd = 0.98 / 1.35               // 0.726

    /// Hop height in points (reduced under Reduce Motion).
    static let jumpHeight: CGFloat = 30
    static let reducedJumpHeight: CGFloat = 14
    /// Bottle hold altitude right after the hidden swap (keeps the
    /// bottle's cork inside the window at all times).
    static let switchHoldHeight: CGFloat = 12
    static let reducedSwitchHoldHeight: CGFloat = 6

    /// The core smoke's opaque content fraction of its square canvas
    /// (measured from the shipped asset, alpha >= 200).
    static let coreOpaqueWidthFraction: CGFloat = 0.803
    static let coreOpaqueHeightFraction: CGFloat = 0.576

    /// Core smoke square size needed at the switch to occlude the whole
    /// union envelope inside the pet window.
    static var coreSwitchSize: CGFloat {
        let envelope = switchEnvelopeRect(reduceMotion: false)
        return max(
            envelope.width / coreOpaqueWidthFraction,
            envelope.height / coreOpaqueHeightFraction
        )
    }

    /// Vertical center of the character envelope in the pet window
    /// (the smoke centers here, in wrapper-local coordinates).
    static var envelopeCenterY: CGFloat {
        (BottleMetrics.artTopY + BottleMetrics.artBottomY) / 2
    }

    static func hopHeight(reduceMotion: Bool) -> CGFloat {
        reduceMotion ? reducedJumpHeight : jumpHeight
    }

    static func holdHeight(reduceMotion: Bool) -> CGFloat {
        reduceMotion ? reducedSwitchHoldHeight : switchHoldHeight
    }

    // MARK: - Form (which asset is visible)

    /// 0 = Warawara, 1 = bottle. A hard step at the switch — the swap
    /// itself is hidden behind full smoke.
    static func formProgress(at t: Double) -> Double {
        t >= switchPoint ? 1 : 0
    }

    // MARK: - Jump arc

    /// Upward offset in points applied to the whole character wrapper.
    /// Continuous everywhere EXCEPT at the hidden swap (switchPoint),
    /// where it drops from the hop peak to the bottle hold height
    /// behind full smoke.
    static func jumpOffsetY(t: Double, reduceMotion: Bool) -> CGFloat {
        let clamped = CGFloat(min(max(t, 0), 1))
        let peak = hopHeight(reduceMotion: reduceMotion)
        let hold = holdHeight(reduceMotion: reduceMotion)
        let poof = CGFloat(poofPoint)
        let switchT = CGFloat(switchPoint)
        let descent = CGFloat(descentEnd)
        if clamped < poof {
            // Rise: anticipation is already done; ease-out into the air.
            let p = CGFloat(smoothstep(Double(clamped / poof), 0, 1))
            return peak * p
        }
        if clamped < switchT {
            // Hold at the peak while the smoke builds.
            return peak
        }
        // Post-swap: the bottle descends gently from the hold height.
        let p = CGFloat(smoothstep(Double((clamped - switchT) / (descent - switchT)), 0, 1))
        return hold * (1 - p)
    }

    /// Squash/stretch of the whole wrapper (anchor: bottom).
    static func squashX(t: Double) -> CGFloat {
        let clamped = CGFloat(min(max(t, 0), 1))
        let anticipation = CGFloat(anticipationEnd)
        let poof = CGFloat(poofPoint)
        let descent = CGFloat(descentEnd)
        if clamped < anticipation {
            let p = clamped / anticipation
            return 1 + 0.07 * p
        }
        if clamped < poof {
            // Stretch upward: narrower during flight.
            let p = (clamped - anticipation) / (poof - anticipation)
            return 1.07 - 0.13 * p
        }
        if clamped < descent {
            return 0.96
        }
        // Landing squash, then settle.
        if clamped < 0.9 {
            let p = (clamped - descent) / (0.9 - descent)
            return 0.96 + 0.10 * sin(.pi * p / 2)
        }
        let p = (clamped - 0.9) / 0.1
        return 1.06 - 0.06 * p
    }

    static func squashY(t: Double) -> CGFloat {
        let clamped = CGFloat(min(max(t, 0), 1))
        let anticipation = CGFloat(anticipationEnd)
        let poof = CGFloat(poofPoint)
        let descent = CGFloat(descentEnd)
        if clamped < anticipation {
            let p = clamped / anticipation
            return 1 - 0.15 * p
        }
        if clamped < poof {
            let p = (clamped - anticipation) / (poof - anticipation)
            return 0.85 + 0.21 * p
        }
        if clamped < descent {
            return 1.05
        }
        // Landing squash, then settle.
        if clamped < 0.9 {
            let p = (clamped - descent) / (0.9 - descent)
            return 1.05 - 0.15 * sin(.pi * p / 2)
        }
        let p = (clamped - 0.9) / 0.1
        return 0.90 + 0.10 * p
    }

    /// Tiny inertial tilt after landing (radians), decaying to zero.
    static func landingWobble(t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        guard clamped >= descentEnd else { return 0 }
        let p = (clamped - descentEnd) / (1 - descentEnd)
        let envelope = sin(p * .pi * 3) * exp(-2.6 * p)
        return 0.018 * envelope
    }

    // MARK: - Smoke

    /// Core occlusion smoke opacity: rises fast to 1 at the switch,
    /// holds while the swap lands, then dissipates as the bottle (which
    /// is fully inside the window) becomes visible.
    static func coreSmokeOpacity(t: Double) -> CGFloat {
        let clamped = CGFloat(min(max(t, 0), 1))
        let poof = CGFloat(poofPoint)
        let switchT = CGFloat(switchPoint)
        let fadeEnd = CGFloat(smokeFadeEnd)
        if clamped < poof { return 0 }
        if clamped < switchT {
            return CGFloat(smoothstep(Double((clamped - poof) / (switchT - poof)), 0, 1))
        }
        if clamped < 0.46 { return 1 }
        if clamped < fadeEnd {
            return 1 - CGFloat(smoothstep(Double((clamped - 0.46) / (fadeEnd - 0.46)), 0, 1))
        }
        return 0
    }

    /// Core smoke scale (1 = the full occlusion size).
    static func coreSmokeScale(t: Double) -> CGFloat {
        let clamped = CGFloat(min(max(t, 0), 1))
        let poof = CGFloat(poofPoint)
        let switchT = CGFloat(switchPoint)
        let fadeEnd = CGFloat(smokeFadeEnd)
        if clamped < switchT {
            let p = CGFloat(smoothstep(Double((clamped - poof) / (switchT - poof)), 0, 1))
            return 0.25 + 0.75 * p
        }
        // After the swap the cloud keeps swelling as it fades.
        let p = CGFloat(smoothstep(Double((clamped - switchT) / (fadeEnd - switchT)), 0, 1))
        return 1 + 0.3 * p
    }

    /// Decorative peripheral layers (soft / small / wisps): swell and
    /// fade after the swap. Reduced under Reduce Motion.
    static func decorativeSmokeOpacity(t: Double, reduceMotion: Bool) -> CGFloat {
        let clamped = CGFloat(min(max(t, 0), 1))
        let poof = CGFloat(poofPoint)
        let switchT = CGFloat(switchPoint)
        let fadeEnd = CGFloat(smokeFadeEnd)
        if clamped < switchT {
            let p = CGFloat(smoothstep(Double((clamped - poof) / (switchT - poof)), 0, 1))
            return p * 0.7
        }
        let fade = 1 - CGFloat(smoothstep(Double((clamped - switchT) / (fadeEnd - switchT)), 0, 1))
        return (reduceMotion ? 0.55 : 0.85) * fade
    }

    static func decorativeSmokeScale(t: Double, reduceMotion: Bool) -> CGFloat {
        let clamped = CGFloat(min(max(t, 0), 1))
        let poof = CGFloat(poofPoint)
        let switchT = CGFloat(switchPoint)
        let fadeEnd = CGFloat(smokeFadeEnd)
        if clamped < switchT {
            let p = CGFloat(smoothstep(Double((clamped - poof) / (switchT - poof)), 0, 1))
            return 0.5 + 0.5 * p
        }
        let p = CGFloat(smoothstep(Double((clamped - switchT) / (fadeEnd - switchT)), 0, 1))
        return 1 + (reduceMotion ? 0.25 : 0.6) * p
    }

    /// Landing dust: a small puff at the baseline as the body settles.
    static func landingDustOpacity(t: Double) -> CGFloat {
        let clamped = CGFloat(min(max(t, 0), 1))
        let descent = CGFloat(descentEnd)
        if clamped < descent { return 0 }
        if clamped < 0.84 {
            return CGFloat(smoothstep(Double((clamped - descent) / (0.84 - descent)), 0, 1))
        }
        if clamped < 0.95 {
            return 1 - CGFloat(smoothstep(Double((clamped - 0.84) / (0.95 - 0.84)), 0, 1))
        }
        return 0
    }

    static func landingDustScale(t: Double) -> CGFloat {
        let clamped = CGFloat(min(max(t, 0), 1))
        let descent = CGFloat(descentEnd)
        if clamped < descent { return 0.6 }
        let p = (clamped - descent) / (0.95 - descent)
        return 0.6 + 0.5 * min(p, 1)
    }

    /// True while any smoke is visible.
    static func smokeVisible(t: Double) -> Bool {
        coreSmokeOpacity(t: t) > 0.01 || decorativeSmokeOpacity(t: t, reduceMotion: false) > 0.01
            || landingDustOpacity(t: t) > 0.01
    }

    // MARK: - Occlusion invariant (machine-checked)

    /// The union envelope of BOTH silhouettes at timeline `t` (window
    /// coordinates, y down from the window top). Both forms share the
    /// wrapper jump offset, so one envelope covers them.
    static func envelopeRect(t: Double, reduceMotion: Bool) -> CGRect {
        let offset = jumpOffsetY(t: t, reduceMotion: reduceMotion)
        let bottleBottom = BottleMetrics.artBottomY - offset
        let bottleTop = bottleBottom - BottleMetrics.artHeight
        let bodyBottom = PetMetrics.visualCenter.y + PetMetrics.blobHeight / 2 - offset
        let bodyTop = bodyBottom - PetMetrics.blobHeight
        let minY = max(min(bottleTop, bodyTop), 0)
        let maxY = max(bottleBottom, bodyBottom)
        // Covers the bottle envelope AND any rig body up to 120 pt wide
        // (the blob is 96; the layered rig is body-normalized nearby).
        let width = max(BottleMetrics.artWidth, 120)
        return CGRect(
            x: PetMetrics.visualCenter.x - width / 2,
            y: minY,
            width: width,
            height: max(maxY - minY, 0)
        )
    }

    /// The envelope exactly at the hidden swap.
    static func switchEnvelopeRect(reduceMotion: Bool) -> CGRect {
        envelopeRect(t: switchPoint, reduceMotion: reduceMotion)
    }

    /// The opaque region covered by the core smoke at timeline `t`
    /// (window coordinates). The occlusion rule: from the switch until
    /// the smoke starts fading, this rect must contain the envelope.
    static func occludedRect(t: Double, reduceMotion: Bool) -> CGRect {
        let offset = jumpOffsetY(t: t, reduceMotion: reduceMotion)
        let size = coreSmokeScale(t: t) * coreSwitchSize * 1.06
        let width = size * coreOpaqueWidthFraction
        let height = size * coreOpaqueHeightFraction
        return CGRect(
            x: PetMetrics.visualCenter.x - width / 2,
            y: envelopeCenterY - offset - height / 2,
            width: width,
            height: height
        )
    }

    static func smoothstep(_ x: Double, _ edge0: Double, _ edge1: Double) -> Double {
        guard edge1 > edge0 else { return x >= edge1 ? 1 : 0 }
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

// MARK: - Views

/// The smoke stack rendered INSIDE the pet window (no extra windows):
/// one opaque core for occlusion plus soft peripheral layers that
/// swell and fade continuously with the timeline.
struct BottlePoofSmokeView: View {
    let timeline: Double
    let reduceMotion: Bool
    let store: BottleMailArtStore

    var body: some View {
        ZStack {
            if let core = store.smokeCore {
                smokeLayer(
                    core,
                    size: BottlePoofTimeline.coreSwitchSize,
                    scale: BottlePoofTimeline.coreSmokeScale(t: timeline),
                    opacity: BottlePoofTimeline.coreSmokeOpacity(t: timeline),
                    rotation: 0
                )
            }
            if let soft = store.smokeSoft {
                smokeLayer(
                    soft,
                    size: 150,
                    scale: BottlePoofTimeline.decorativeSmokeScale(t: timeline, reduceMotion: reduceMotion),
                    opacity: BottlePoofTimeline.decorativeSmokeOpacity(t: timeline, reduceMotion: reduceMotion),
                    rotation: -8,
                    offset: CGSize(width: 18, height: -22)
                )
            }
            if let small = store.smokeSmall {
                smokeLayer(
                    small,
                    size: 110,
                    scale: BottlePoofTimeline.decorativeSmokeScale(t: timeline, reduceMotion: reduceMotion),
                    opacity: BottlePoofTimeline.decorativeSmokeOpacity(t: timeline, reduceMotion: reduceMotion),
                    rotation: 10,
                    offset: CGSize(width: -16, height: 14)
                )
            }
            if let wisps = store.smokeWisps {
                smokeLayer(
                    wisps,
                    size: 120,
                    scale: BottlePoofTimeline.decorativeSmokeScale(t: timeline, reduceMotion: reduceMotion),
                    opacity: 0.7 * BottlePoofTimeline.decorativeSmokeOpacity(t: timeline, reduceMotion: reduceMotion),
                    rotation: -4,
                    offset: CGSize(width: 0, height: -40)
                )
            }
            if let dust = store.landingDust {
                Image(nsImage: dust)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 150, height: 150)
                    .scaleEffect(BottlePoofTimeline.landingDustScale(t: timeline))
                    .offset(y: BottleMetrics.artBottomY - BottlePoofTimeline.envelopeCenterY + 40)
                    .opacity(BottlePoofTimeline.landingDustOpacity(t: timeline))
            }
        }
        .position(x: PetMetrics.visualCenter.x, y: BottlePoofTimeline.envelopeCenterY)
        .allowsHitTesting(false)
    }

    private func smokeLayer(
        _ image: NSImage,
        size: CGFloat,
        scale: CGFloat,
        opacity: CGFloat,
        rotation: Double,
        offset: CGSize = .zero
    ) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .offset(offset)
            .opacity(opacity)
    }
}

/// The bottle art in poof mode: a plain full silhouette (no reveal
/// geometry) — it only becomes visible when `formProgress == 1`, i.e.
/// after the hidden swap.
struct BottlePoofArtView: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: BottleMetrics.artHeight, height: BottleMetrics.artHeight)
            .frame(width: BottleMetrics.artWidth, height: BottleMetrics.artHeight)
    }
}
