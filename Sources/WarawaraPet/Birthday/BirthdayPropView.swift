import SwiftUI

/// Cake with a few muted gold sparkles (sparse, small, gentle) and an
/// OPTIONAL carry-helper overlay (tray/band from a future art pack).
struct CakePropView: View {
    let store: BirthdayAssetStore
    let cakeSize: CGFloat
    var carryHelper: NSImage? = nil
    @State private var twinkle = false

    var body: some View {
        ZStack {
            if let helper = carryHelper {
                let aspect = BirthdayImageAlignment.aspectRatio(of: helper, cacheKey: "cake_tray") ?? 1.59
                Image(nsImage: helper)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: cakeSize * 1.28, height: cakeSize * 1.28 / aspect)
                    // The tray sits slightly below the cake so the cake
                    // rests ON it with visible contact.
                    .offset(y: cakeSize * 0.16)
            }
            if let cake = store.image(named: "cake_lit.png") {
                Image(nsImage: cake)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: cakeSize, height: cakeSize)
            }
            sparkle(named: "sparkle_gold_large", size: 18, dx: -40, dy: -34)
            sparkle(named: "sparkle_gold_lower", size: 14, dx: 42, dy: -22)
            sparkle(named: "sparkle_gold_star", size: 12, dx: 8, dy: -44)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                twinkle = true
            }
        }
        .scaleEffect(twinkle ? 1 : 0.985)
        .opacity(twinkle ? 1 : 0.7)
    }

    private func sparkle(named name: String, size: CGFloat, dx: CGFloat, dy: CGFloat) -> some View {
        Group {
            if let image = store.image(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
                    .opacity(twinkle ? 0.95 : 0.35)
            }
        }
        .offset(x: dx, y: dy)
    }
}

/// The clickable envelope: closed by default, gentle crossfade to the
/// open illustration on click, then the letter window opens. An OPTIONAL
/// carry-helper overlay (paper band) may wrap it while carried.
struct EnvelopePropView: View {
    let store: BirthdayAssetStore
    let envelopeSize: CGFloat
    var carryHelper: NSImage? = nil
    var initiallyOpened: Bool = false
    let onOpenLetter: () -> Void

    @State private var opened: Bool

    init(
        store: BirthdayAssetStore,
        envelopeSize: CGFloat,
        carryHelper: NSImage? = nil,
        initiallyOpened: Bool = false,
        onOpenLetter: @escaping () -> Void
    ) {
        self.store = store
        self.envelopeSize = envelopeSize
        self.carryHelper = carryHelper
        self.initiallyOpened = initiallyOpened
        self.onOpenLetter = onOpenLetter
        _opened = State(initialValue: initiallyOpened)
    }

    var body: some View {
        let closedImage = store.image(named: "envelope_closed.png")
        let openImage = store.image(named: "envelope_open.png")
        // Content-aware alignment: both states share ONE displayed
        // content width and a common baseline, so switching never jumps
        // in position or apparent size. The open variant's extra height
        // (the letter emerging) grows UPWARD from the shared baseline.
        let targetWidth = envelopeSize * 0.92
        let closedScale = closedImage.map {
            BirthdayImageAlignment.scaleForContentWidth(
                of: $0, canvasPoints: envelopeSize,
                targetContentWidth: targetWidth, cacheKey: "envelope_closed"
            )
        } ?? 1
        let openScale = openImage.map {
            BirthdayImageAlignment.scaleForContentWidth(
                of: $0, canvasPoints: envelopeSize,
                targetContentWidth: targetWidth, cacheKey: "envelope_open"
            )
        } ?? 1

        ZStack {
            if let helper = carryHelper {
                Image(nsImage: helper)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: envelopeSize * 1.4, height: envelopeSize * 1.4)
            }
            if let closed = closedImage {
                Image(nsImage: closed)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: envelopeSize, height: envelopeSize)
                    .scaleEffect(closedScale, anchor: .bottom)
                    .opacity(opened ? 0 : 1)
            }
            if let open = openImage {
                Image(nsImage: open)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: envelopeSize, height: envelopeSize)
                    .scaleEffect(openScale, anchor: .bottom)
                    .opacity(opened ? 1 : 0)
            }
        }
        .scaleEffect(opened ? 1.03 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !opened else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                opened = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                onOpenLetter()
            }
        }
        .onChange(of: opened) { isOpened in
            if !isOpened {
                // Re-closed after the letter window closes.
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .birthdayLetterDidClose)) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                opened = false
            }
        }
    }
}

extension Notification.Name {
    static let birthdayLetterDidClose = Notification.Name("warawarapet.birthday.letterDidClose")
}

/// The personal letter reading surface: a cohesive warm ivory paper
/// page, selectable Unicode text, comfortable spacing and scrolling.
/// No corner illustration, no distorted foreground paper image.
struct LetterView: View {
    let text: String
    let store: BirthdayAssetStore

    private var paperColor: NSColor {
        NSColor(calibratedRed: 0.986, green: 0.972, blue: 0.936, alpha: 1)
    }

    private var inkColor: NSColor {
        NSColor(calibratedRed: 0.23, green: 0.21, blue: 0.24, alpha: 1)
    }

    private var accentColor: NSColor {
        NSColor(calibratedRed: 0.56, green: 0.40, blue: 0.44, alpha: 1)
    }

    var body: some View {
        ZStack {
            Color(nsColor: paperColor)
            VStack(spacing: 0) {
                Text("生日快乐 · Happy Birthday")
                    .font(.system(size: 21, weight: .semibold, design: .serif))
                    .foregroundColor(Color(nsColor: accentColor))
                    .padding(.top, 24)
                    .padding(.bottom, 8)
                Rectangle()
                    .fill(Color(nsColor: accentColor).opacity(0.45))
                    .frame(width: 240, height: 1)
                    .padding(.bottom, 6)
                ScrollView {
                    Text(text)
                        .textSelection(.enabled)
                        .font(.system(size: 15.5, design: .serif))
                        .foregroundColor(Color(nsColor: inkColor))
                        .lineSpacing(7.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 38)
                        .padding(.top, 20)
                        .padding(.bottom, 30)
                }
            }
        }
    }
}
