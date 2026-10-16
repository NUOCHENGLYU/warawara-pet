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
                Image(nsImage: helper)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: cakeSize * 1.35, height: cakeSize * 1.35)
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
    let onOpenLetter: () -> Void

    @State private var opened = false

    var body: some View {
        ZStack {
            if let helper = carryHelper {
                Image(nsImage: helper)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: envelopeSize * 1.4, height: envelopeSize * 1.4)
            }
            if let closed = store.image(named: "envelope_closed.png") {
                Image(nsImage: closed)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: envelopeSize, height: envelopeSize)
                    .opacity(opened ? 0 : 1)
            }
            if let open = store.image(named: "envelope_open.png") {
                Image(nsImage: open)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: envelopeSize, height: envelopeSize)
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

/// The personal letter reading surface: warm cream native background
/// (readability first), optional parchment decoration behind the text,
/// comfortable line spacing, scrolling, UTF-8 Chinese + English.
struct LetterView: View {
    let text: String
    let store: BirthdayAssetStore

    var body: some View {
        ZStack {
            Color(nsColor: NSColor(
                calibratedRed: 0.982, green: 0.968, blue: 0.935, alpha: 1
            ))
            VStack(spacing: 0) {
                Text("生日快乐 · Happy Birthday")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundColor(Color(nsColor: NSColor(
                        calibratedRed: 0.45, green: 0.41, blue: 0.52, alpha: 1
                    )))
                    .padding(.top, 22)
                    .padding(.bottom, 6)
                Rectangle()
                    .fill(Color(nsColor: NSColor(
                        calibratedRed: 0.72, green: 0.66, blue: 0.80, alpha: 0.5
                    )))
                    .frame(width: 220, height: 1)
                ScrollView {
                    Text(text)
                        .font(.system(size: 15, design: .serif))
                        .foregroundColor(Color(nsColor: NSColor(
                            calibratedRed: 0.24, green: 0.22, blue: 0.24, alpha: 1
                        )))
                        .lineSpacing(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 24)
                }
            }
            if let paper = store.image(named: "letter_paper_blank.png") {
                Image(nsImage: paper)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 96, height: 96)
                    .opacity(0.85)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
    }
}
