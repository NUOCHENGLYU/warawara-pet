import SwiftUI

/// The procedural placeholder Warawara (blob + eyes). This is exactly the
/// visual used since Phase 0 and remains the fallback whenever sprite
/// assets are missing. NOT the final artwork — it is a placeholder.
struct PlaceholderWarawaraView: View {
    enum SizeClass {
        /// Main pet placeholder: 96 x 118 blob with eyes.
        case main
        /// Companion placeholder: 60 x 74 blob with eyes, scaled.
        case companion
    }

    let sizeClass: SizeClass
    var scale: CGFloat = 1

    private var blobSize: CGSize {
        switch sizeClass {
        case .main: return CGSize(width: 96, height: 118)
        case .companion: return CGSize(width: CompanionMetrics.blobWidth, height: CompanionMetrics.blobHeight)
        }
    }

    private var eyeSpacing: CGFloat {
        switch sizeClass {
        case .main: return 34
        case .companion: return 22
        }
    }

    private var eyeOffset: CGFloat {
        switch sizeClass {
        case .main: return 62
        case .companion: return 10
        }
    }

    private var eyeSize: CGSize {
        switch sizeClass {
        case .main: return CGSize(width: 9, height: 11)
        case .companion: return CGSize(width: 6, height: 7)
        }
    }

    var body: some View {
        blob
            .padding(.bottom, sizeClass == .main ? PetMetrics.blobBottomPadding : 0)
            .scaleEffect(scale, anchor: .center)
    }

    private var blob: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.97), Color(white: 0.84)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: blobSize.width, height: blobSize.height)
            .overlay(Capsule().stroke(Color(white: 0.5), lineWidth: sizeClass == .main ? 1.5 : 1.2))
            .overlay(
                HStack(spacing: eyeSpacing) {
                    Circle().fill(Color(white: 0.18)).frame(width: eyeSize.width, height: eyeSize.height)
                    Circle().fill(Color(white: 0.18)).frame(width: eyeSize.width, height: eyeSize.height)
                }
                .offset(y: eyeOffset),
                alignment: .center
            )
    }
}

/// Renders one sprite frame with its manifest layout: the image is drawn
/// inside the logical canvas, positioned so the manifest anchor maps onto
/// the view's center. `renderSize` is the canvas scaled to the character's
/// target body height (main pet or companion).
struct WarawaraSpriteFrameView: View {
    let image: NSImage
    let renderSize: CGSize
    let anchor: CGPoint

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: renderSize.width, height: renderSize.height)
            .offset(
                x: renderSize.width / 2 - anchor.x * renderSize.width,
                y: renderSize.height / 2 - anchor.y * renderSize.height
            )
    }
}

/// The character content used by BOTH the main pet and companions:
/// sprite frames when assets exist, the procedural placeholder otherwise.
/// All deformation transforms stay OUTSIDE this view, applied by the
/// existing pose pipeline.
struct WarawaraCharacterView: View {
    let visualState: WarawaraVisualState
    let loader: WarawaraSpriteLoader
    var baseURL: URL?
    var scale: CGFloat = 1
    var placeholderSizeClass: PlaceholderWarawaraView.SizeClass = .main

    /// The manifest canvas scaled so the artwork's body height matches
    /// the character's target body height (main 118 pt, companion 74 pt,
    /// times `scale`). Keeps sprite artwork correctly sized inside both
    /// window classes without clipping.
    private var spriteRenderSize: CGSize? {
        guard let manifest = loader.manifest else { return nil }
        let bodyHeightInCanvas = manifest.layout.bodyBounds.height * manifest.layout.canvas.height
        guard bodyHeightInCanvas > 0 else { return nil }
        let targetBodyHeight: CGFloat
        switch placeholderSizeClass {
        case .main:
            targetBodyHeight = PetMetrics.blobHeight * scale
        case .companion:
            targetBodyHeight = CompanionMetrics.blobHeight * scale
        }
        return WarawaraAnimationMapper.renderSize(
            canvas: manifest.layout.canvas,
            bodyHeightInCanvas: bodyHeightInCanvas,
            targetBodyHeight: targetBodyHeight
        )
    }

    var body: some View {
        if let baseURL = baseURL ?? WarawaraSpriteLoader.defaultResourceURL,
           let animation = loader.animation(named: WarawaraAnimationMapper.animationKey(for: visualState)),
           let renderSize = spriteRenderSize,
           let firstFrame = loader.image(forRelativePath: animation.frames[0], baseURL: baseURL) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let index = WarawaraAnimationMapper.frameIndex(
                    at: context.date.timeIntervalSinceReferenceDate,
                    animation: animation
                )
                let image = loader.image(forRelativePath: animation.frames[index], baseURL: baseURL)
                    ?? firstFrame
                WarawaraSpriteFrameView(
                    image: image,
                    renderSize: renderSize,
                    anchor: loader.manifest?.layout.anchor ?? CGPoint(x: 0.5, y: 0.5)
                )
            }
        } else {
            PlaceholderWarawaraView(sizeClass: placeholderSizeClass, scale: scale)
        }
    }
}
