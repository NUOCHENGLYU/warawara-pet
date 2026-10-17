import AppKit
import SwiftUI

/// Production realization of the meteor event:
/// - ONE pooled, click-through, transparent panel that follows the
///   FIXED world-space trajectory (never attached to the pet window);
/// - the panel is CREATED AND ORDERED FRONT at flight start (the
///   previous invisibility bug: a never-ordered NSPanel stays hidden
///   even with alpha 1 and correct frames);
/// - continuous 30 Hz attention tracking through the flight;
/// - gaze-hold after departure, then a closed-eye wish, then a
///   celebration hop;
/// - exact cleanup: alpha zero, parked off-screen, no residual sprite.
final class MeteorEventPresenter: MeteorEventPresenting {
    private weak var windowController: PetWindowController?
    private weak var controller: MeteorEventController?
    private let store: GiftAssetStore

    private var panel: BirthdayPropPanel?
    private var timer: Timer?
    private var trajectory: MeteorTrajectory?
    private var attentionDirection: CGVector?
    private var cleanupDone = false
    private var panelOrdered = false
    private var lastFrameLog = Date(timeIntervalSince1970: 0)
    private let viewState = MeteorViewState()

    /// Meteor painted content length (star + tail) in points. The star
    /// head lands in the 24-45 pt apparent-diameter range with a
    /// proportionate tail.
    private let paintedTargetLengthPt: CGFloat = 160
    /// Painted bbox of the approved meteor sprite (manifest: right=881,
    /// top=199, bottom=900) — the ONLY content measurement used.
    private let paintedWidthPx: CGFloat = 881
    private let canvasPx: CGFloat = 1024

    /// Test access to the production panel.
    var debugPanel: BirthdayPropPanel? { panel }

    init(
        windowController: PetWindowController,
        controller: MeteorEventController,
        store: GiftAssetStore = .shared
    ) {
        self.windowController = windowController
        self.controller = controller
        self.store = store
    }

    var activeVisibleFrame: CGRect {
        ScreenGeometry.visibleFrame(for: windowController?.currentFrame ?? .zero)
    }

    // MARK: - MeteorEventPresenting

    func noticeScene() {
        cleanupDone = false
        panelOrdered = false
        guard let petFrame = windowController?.currentFrame, petFrame != .zero else { return }
        // Look toward the entry side (top-left, off-screen).
        let body = BirthdayPropLayout.petBodyRect(petFrame: petFrame)
        let direction = EventAttentionMath.direction(
            from: CGPoint(x: body.midX, y: body.midY),
            to: CGPoint(x: petFrame.minX - 120, y: activeVisibleFrame.maxY * 0.78)
        )
        if direction != .zero {
            attentionDirection = direction
            windowController?.setEventAttention(direction)
        }
    }

    func flightDidBegin(trajectory: MeteorTrajectory) {
        self.trajectory = trajectory
        let visible = activeVisibleFrame
        EventDiagnostics.emit(String(
            format: "METEOR_PATH_RESOLVED entry=%.0f,%.0f exit=%.0f,%.0f c1=%.0f,%.0f c2=%.0f,%.0f visible=%.0fx%.0f",
            trajectory.entry.x, trajectory.entry.y,
            trajectory.exit.x, trajectory.exit.y,
            trajectory.control1.x, trajectory.control1.y,
            trajectory.control2.x, trajectory.control2.y,
            visible.width, visible.height
        ))
        ensurePanel()
        startTimer()
        // First frame immediately (still fully off-screen at t = 0).
        renderFrame(progress: 0, at: Date())
    }

    /// Called by the controller at phase boundaries; the 30 Hz render
    /// loop below does the per-frame work.
    func flightFrame(progress: CGFloat, at now: Date) {
        renderFrame(progress: progress, at: now)
    }

    func meteorDeparted() {
        // The meteor is fully beyond the display: hold the gaze toward
        // the exit direction for the departed beat.
        if let trajectory {
            let direction = EventAttentionMath.direction(
                from: petBodyCenter,
                to: trajectory.exit
            )
            if direction != .zero {
                attentionDirection = direction
                windowController?.setEventAttention(direction)
            }
        }
        panel?.alphaValue = 0
        EventDiagnostics.emit("METEOR_ALPHA alpha=0")
    }

    func wishingDidBegin() {
        // Release the gaze and close the eyes for the wish.
        attentionDirection = nil
        windowController?.setEventAttention(nil)
        windowController?.setWishing(true)
    }

    func celebrationDidBegin() {
        windowController?.setWishing(false)
        windowController?.performCelebrationHop()
    }

    func cleanup() {
        guard !cleanupDone else { return }
        cleanupDone = true
        stopTimer()
        panel?.alphaValue = 0
        // Park the pooled panel fully off-screen below the visible area
        // so nothing can linger at the screen edge.
        if let panel {
            let visible = activeVisibleFrame
            panel.setFrameOrigin(CGPoint(
                x: visible.minX + 40,
                y: visible.minY - panel.frame.height - 80
            ))
            EventDiagnostics.emit(String(
                format: "METEOR_CLEANED_UP frame=%.0f,%.0f alpha=%.2f",
                panel.frame.minX, panel.frame.minY, panel.alphaValue
            ))
        }
        trajectory = nil
        attentionDirection = nil
        windowController?.setEventAttention(nil)
        windowController?.setWishing(false)
    }

    private var petBodyCenter: CGPoint {
        guard let petFrame = windowController?.currentFrame else { return .zero }
        let body = BirthdayPropLayout.petBodyRect(petFrame: petFrame)
        return CGPoint(x: body.midX, y: body.midY)
    }

    // MARK: - 30 Hz render loop (independent of the 4 Hz scheduler)

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.timerTick()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func timerTick() {
        guard let controller else { return }
        guard let progress = controller.flightProgress(at: Date()) else {
            return
        }
        renderFrame(progress: progress, at: Date())
    }

    private func renderFrame(progress: CGFloat, at now: Date) {
        guard let trajectory, let panel else { return }
        let position = trajectory.position(at: progress)
        let size = panel.frame.size
        panel.setFrameOrigin(CGPoint(
            x: position.x - size.width / 2,
            y: position.y - size.height / 2
        ))
        viewState.rotationDegrees = trajectory.heading(at: progress) * 180 / .pi + 15
        if panel.alphaValue < 0.99 {
            panel.alphaValue = 1
            EventDiagnostics.emit(String(
                format: "METEOR_ALPHA alpha=%.2f frame=%.0f,%.0f visible=%d level=%d",
                panel.alphaValue, panel.frame.minX, panel.frame.minY,
                panel.isVisible ? 1 : 0, Int(panel.level.rawValue)
            ))
        }
        if now.timeIntervalSince(lastFrameLog) >= 1 {
            lastFrameLog = now
            EventDiagnostics.emit(String(
                format: "METEOR_FRAME progress=%.2f x=%.0f y=%.0f panel=%.0f,%.0f",
                progress, position.x, position.y, panel.frame.minX, panel.frame.minY
            ))
        }

        // Continuous attention tracking toward the moving meteor.
        let direction = EventAttentionMath.direction(
            from: petBodyCenter,
            to: position
        )
        if direction != .zero {
            if attentionDirection == nil {
                attentionDirection = direction
                windowController?.setEventAttention(direction)
            } else if direction != attentionDirection {
                attentionDirection = direction
                windowController?.updateEventAttention(direction)
            }
        }
    }

    // MARK: - Panel

    private func ensurePanel() {
        guard panel == nil else { return }
        // ONE consistent source-pixel-to-point scale. The previous code
        // divided by (881/1024) AND multiplied by 1024, producing a
        // ~178,000-point canvas: a giant translucent panel stretched
        // across the screen (the yellow/white block artifact).
        let scale = paintedTargetLengthPt / paintedWidthPx
        let canvasPt = canvasPx * scale
        // Sanity: the meteor canvas must stay a small sky object.
        guard canvasPt > 60, canvasPt < 400 else {
            EventDiagnostics.emit(String(
                format: "METEOR_SCALE_INVALID canvasPt=%.1f scale=%.4f",
                canvasPt, scale
            ))
            return
        }
        let panelSize = CGSize(width: canvasPt + 28, height: canvasPt + 28)
        let newPanel = BirthdayPropPanel(size: panelSize, interactive: false)
        if let image = store.image(named: "meteor_celfilm.png") {
            viewState.image = image
            viewState.canvasSize = CGSize(width: canvasPt, height: canvasPt)
            viewState.rotationDegrees = 0
            let hosting = NSHostingView(rootView: MeteorView(state: viewState))
            hosting.frame = NSRect(origin: .zero, size: panelSize)
            newPanel.contentView = hosting
        }
        newPanel.alphaValue = 0
        panel = newPanel
        if let screen = newPanel.screen {
            EventDiagnostics.emit(String(
                format: "METEOR_RENDER_DEBUG bbox=0,199,881,900 logicalSize=%.1fx%.1f scale=%.4f backingScale=%.2f panelFrame=%.0f,%.0f,%.0f,%.0f alpha=%.2f",
                canvasPt, canvasPt, scale, screen.backingScaleFactor,
                newPanel.frame.minX, newPanel.frame.minY,
                newPanel.frame.width, newPanel.frame.height,
                newPanel.alphaValue
            ))
        }
        EventDiagnostics.emit(String(
            format: "METEOR_PANEL_CREATED size=%.0fx%.0f contentView=%d",
            panelSize.width, panelSize.height, newPanel.contentView != nil ? 1 : 0
        ))
        // THE visibility fix: a brand-new NSPanel is invisible until it
        // is ordered front. Without this the meteor never appears even
        // with alpha 1 and correct frames.
        newPanel.orderFrontRegardless()
        panelOrdered = true
        EventDiagnostics.emit("METEOR_ORDERED_FRONT")
    }
}

/// Live state for the meteor view (rotation updated per frame without
/// rebuilding the SwiftUI root).
final class MeteorViewState: ObservableObject {
    @Published var rotationDegrees: CGFloat = 0
    var image: NSImage?
    var canvasSize: CGSize = .zero
}

/// The meteor painting (unchanged artwork), banked along its heading.
struct MeteorView: View {
    @ObservedObject var state: MeteorViewState

    var body: some View {
        if let image = state.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: state.canvasSize.width, height: state.canvasSize.height)
                .rotationEffect(.degrees(Double(state.rotationDegrees)))
        }
    }
}
