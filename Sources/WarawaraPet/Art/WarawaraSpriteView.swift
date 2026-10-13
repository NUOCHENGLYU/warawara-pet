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

/// What `WarawaraCharacterView` will draw for a given state. Extracted
/// from the view body so the real rendering decision is unit-testable
/// without instantiating SwiftUI views.
enum WarawaraCharacterContent {
    case layered(rig: WarawaraRigManifest, rigLoader: WarawaraRigLoader, renderSize: CGSize)
    case sprite(
        firstFrame: NSImage,
        animation: WarawaraSpriteManifest.Animation,
        renderSize: CGSize,
        anchor: CGPoint
    )
    case placeholder

    static func resolve(
        visualState: WarawaraVisualState,
        loader: WarawaraSpriteLoader,
        rigLoader: WarawaraRigLoader = .shared,
        baseURL: URL?,
        placeholderSizeClass: PlaceholderWarawaraView.SizeClass,
        scale: CGFloat
    ) -> WarawaraCharacterContent {
        // Resolution order: layered rig (primary direction) -> single
        // sprite pipeline -> procedural placeholder (+ error badge).
        if let rig = rigLoader.rig {
            let targetBodyHeight: CGFloat
            switch placeholderSizeClass {
            case .main: targetBodyHeight = PetMetrics.blobHeight * scale
            case .companion: targetBodyHeight = CompanionMetrics.blobHeight * scale
            }
            if let renderSize = WarawaraExpressionDriver.renderSize(rig: rig, targetBodyHeight: targetBodyHeight) {
                return .layered(rig: rig, rigLoader: rigLoader, renderSize: renderSize)
            }
        }
        let resolvedBaseURL = baseURL ?? loader.loadedBaseURL ?? WarawaraSpriteLoader.defaultResourceURL
        guard let resolvedBaseURL,
              let manifest = loader.manifest,
              let animation = loader.animation(named: WarawaraAnimationMapper.animationKey(for: visualState)),
              let renderSize = WarawaraCharacterView.spriteRenderSize(
                manifest: manifest,
                placeholderSizeClass: placeholderSizeClass,
                scale: scale
              ),
              let firstFrame = loader.image(forRelativePath: animation.frames[0], baseURL: resolvedBaseURL) else {
            return .placeholder
        }
        return .sprite(
            firstFrame: firstFrame,
            animation: animation,
            renderSize: renderSize,
            anchor: manifest.layout.anchor
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
    var rigLoader: WarawaraRigLoader = .shared
    var baseURL: URL?
    var scale: CGFloat = 1
    var placeholderSizeClass: PlaceholderWarawaraView.SizeClass = .main
    /// App-level expression inputs (state, gaze, drag, progress). Only
    /// consumed by the layered rig branch.
    var expressionInputs: WarawaraExpressionInputs = .neutral

    /// The manifest canvas scaled so the artwork's body height matches
    /// the character's target body height (main 118 pt, companion 74 pt,
    /// times `scale`). Keeps sprite artwork correctly sized inside both
    /// window classes without clipping.
    static func spriteRenderSize(
        manifest: WarawaraSpriteManifest,
        placeholderSizeClass: PlaceholderWarawaraView.SizeClass,
        scale: CGFloat
    ) -> CGSize? {
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
        let content = WarawaraCharacterContent.resolve(
            visualState: visualState,
            loader: loader,
            rigLoader: rigLoader,
            baseURL: baseURL,
            placeholderSizeClass: placeholderSizeClass,
            scale: scale
        )
        switch content {
        case .layered(let rig, let rigLoader, let renderSize):
            WarawaraExpressionDriverView(
                rig: rig,
                rigLoader: rigLoader,
                inputs: expressionInputs,
                renderSize: renderSize
            )
            .padding(.bottom, spriteBottomLift(renderSize: renderSize))
        case .sprite(let firstFrame, let animation, let renderSize, let anchor):
            spriteView(
                firstFrame: firstFrame,
                animation: animation,
                renderSize: renderSize,
                anchor: anchor
            )
        case .placeholder:
            placeholderView
        }
    }

    private func spriteView(
        firstFrame: NSImage,
        animation: WarawaraSpriteManifest.Animation,
        renderSize: CGSize,
        anchor: CGPoint
    ) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let baseURL = self.baseURL ?? loader.loadedBaseURL ?? WarawaraSpriteLoader.defaultResourceURL
            let index = WarawaraAnimationMapper.frameIndex(
                at: context.date.timeIntervalSinceReferenceDate,
                animation: animation
            )
            let image = baseURL.flatMap { loader.image(forRelativePath: animation.frames[index], baseURL: $0) }
                ?? firstFrame
            WarawaraSpriteFrameView(
                image: image,
                renderSize: renderSize,
                anchor: anchor
            )
            // Keep the artwork's body center on the established
            // visual center so window origins, ground position and
            // the hit region stay aligned for any canvas aspect.
            .padding(.bottom, spriteBottomLift(renderSize: renderSize))
        }
    }

    /// The procedural fallback is kept for resilience, but a failed
    /// sprite load must never be silent: a small amber badge marks the
    /// placeholder whenever the loader recorded an error.
    private var placeholderView: some View {
        PlaceholderWarawaraView(sizeClass: placeholderSizeClass, scale: scale)
            .overlay(alignment: .topTrailing) {
                if loader.lastErrorDescription != nil {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .padding(4)
                        .accessibilityLabel("sprite-load-error")
                }
            }
    }

    /// Lifts the sprite so its body center lands on the pet's visual
    /// center (main pet only; companions stay panel-centered). Zero for
    /// the legacy full-window canvas.
    private func spriteBottomLift(renderSize: CGSize) -> CGFloat {
        guard placeholderSizeClass == .main else { return 0 }
        return max(0, PetMetrics.visualCenter.y - renderSize.height / 2)
    }
}
