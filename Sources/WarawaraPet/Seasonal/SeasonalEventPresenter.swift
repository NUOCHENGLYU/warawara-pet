import AppKit
import SwiftUI

/// Production realization of the seasonal + daily scenes: ONE pooled
/// transparent prop panel per app lifetime, positioned around the main
/// pet, with per-kind content and motion. Props always retire at scene
/// end — no permanent decorations.
final class SeasonalEventPresenter: SeasonalEventPresenting {
    private weak var windowController: PetWindowController?
    private weak var coordinator: SeasonalEventCoordinator?
    private let store: SeasonalAssetStore

    private var propPanel: BirthdayPropPanel?
    private var motionTimer: Timer?
    private var motionStart = Date()
    private var motionFrom = CGPoint.zero
    private var motionTo = CGPoint.zero
    private var motionKind: SeasonalEventKind?
    private var glideActive = false
    private var lastUpdateLog = Date(timeIntervalSince1970: 0)

    /// Production-path observability (tests assert against the REAL
    /// presenter, not a fake): presentation attempt count, rejected
    /// attempts with reasons, presented window state, depart count.
    private(set) var presentCallCount = 0
    private(set) var rejectionReasons: [String] = []
    private(set) var departCallCount = 0
    var presentedPanel: BirthdayPropPanel? { propPanel }

    private let panelSize = CGSize(width: 220, height: 220)

    init(
        windowController: PetWindowController,
        coordinator: SeasonalEventCoordinator,
        store: SeasonalAssetStore = .shared
    ) {
        self.windowController = windowController
        self.coordinator = coordinator
        self.store = store
    }

    // MARK: - SeasonalEventPresenting

    func noticeScene() {
        // Attention toward where the prop will arrive from (left).
        windowController?.setEventAttention(CGVector(dx: -0.45, dy: -0.1))
    }

    func presentProp() {
        presentCallCount += 1
        guard let kind = coordinator?.kind else {
            reject(id: coordinator?.kind?.replayArgument ?? "?", reason: "no-event-kind")
            return
        }
        guard let petFrame = windowController?.currentFrame, petFrame != .zero else {
            reject(id: kind.replayArgument, reason: "invalid-geometry")
            return
        }
        ensurePanel(kind: kind)
        guard let propPanel else {
            reject(id: kind.replayArgument, reason: "panel-creation-failed")
            return
        }
        let visible = ScreenGeometry.visibleFrame(for: petFrame)
        let rest = restOrigin(petFrame: petFrame, visible: visible)
        let start = CGPoint(x: rest.x - 220, y: rest.y + 60)

        propPanel.setFrameOrigin(start)
        propPanel.alphaValue = 0
        propPanel.orderFrontRegardless()
        verifyPresentedWindow(kind: kind, panel: propPanel, targetAlpha: 1)
        if kind == .paperAirplane {
            glideActive = true
            motionKind = kind
            motionFrom = start
            motionTo = rest
            motionStart = Date()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                propPanel.animator().alphaValue = 1
            }
            startMotionTimer()
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5
                propPanel.animator().alphaValue = 1
            }
            motionKind = kind
            motionFrom = start
            motionTo = rest
            motionStart = Date()
            startMotionTimer()
        }
        // The pet looks at the arriving prop.
        windowController?.setEventAttention(CGVector(dx: -0.45, dy: -0.1))
    }

    /// After ordering the prop panel front, VERIFY the presentation
    /// state and log it. Emits EVENT_WINDOW_PRESENTED only once the
    /// production presenter actually holds a retained, nonzero window
    /// with populated content heading to a visible alpha.
    private func verifyPresentedWindow(
        kind: SeasonalEventKind,
        panel: BirthdayPropPanel,
        targetAlpha: CGFloat
    ) {
        let frame = panel.frame
        guard !frame.isEmpty,
              frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite else {
            reject(id: kind.replayArgument, reason: "invalid-window-frame")
            return
        }
        guard panel.contentView is NSHostingView<SeasonalPropView> else {
            reject(id: kind.replayArgument, reason: "empty-content-view")
            return
        }
        EventReplayLog.visible(id: kind.replayArgument)
        EventReplayLog.windowPresented(
            id: kind.replayArgument,
            visible: panel.isVisible,
            frame: frame,
            level: panel.level,
            alpha: targetAlpha
        )
    }

    private func reject(id: String, reason: String) {
        rejectionReasons.append(reason)
        EventReplayLog.sceneFailed(id: id, reason: reason)
    }

    func settleProp() {
        stopMotionTimer()
        guard let propPanel, let petFrame = windowController?.currentFrame, petFrame != .zero else { return }
        let visible = ScreenGeometry.visibleFrame(for: petFrame)
        let rest = restOrigin(petFrame: petFrame, visible: visible)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.8
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            propPanel.animator().setFrameOrigin(rest)
        }
        windowController?.setEventAttention(CGVector(dx: -0.25, dy: -0.12))
    }

    func celebrateScene() {
        // The main pet makes its small celebratory hop.
        windowController?.performBirthdayHop()
    }

    func departScene() {
        departCallCount += 1
        stopMotionTimer()
        glideActive = false
        guard let propPanel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 1.2
            propPanel.animator().alphaValue = 0
        }
    }

    func clearAttention() {
        windowController?.setEventAttention(nil)
    }

    // MARK: - Panel + motion

    private func ensurePanel(kind: SeasonalEventKind) {
        if propPanel == nil {
            let panel = BirthdayPropPanel(size: panelSize, interactive: false)
            panel.alphaValue = 0
            propPanel = panel
        }
        // updateContent MUST run after the panel is assigned: it builds
        // the production view onto the live panel. (The original order
        // called it while propPanel was still nil, leaving the window
        // permanently empty — the exact "phases advance, nothing
        // visible" failure.)
        updateContent(kind: kind)
    }

    private func updateContent(kind: SeasonalEventKind) {
        guard let propPanel else { return }
        // Load and VERIFY every production asset for this scene before
        // building the view: a missing PNG must be loud, not a silently
        // empty transparent window.
        let assetNames = kind.displayedAssets
        for name in assetNames {
            if store.image(named: name) != nil {
                EventReplayLog.assetLoaded(id: kind.replayArgument, name: name)
            } else {
                EventReplayLog.assetMissing(id: kind.replayArgument, name: name)
                reject(id: kind.replayArgument, reason: "missing-asset:\(name)")
            }
        }
        let view = SeasonalPropView(
            kind: kind,
            store: store,
            primarySize: kind.primaryDisplayPoints,
            showSecondary: kind.showsSecondaryDecor
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: panelSize)
        propPanel.contentView = hosting
    }

    private func restOrigin(petFrame: CGRect, visible: CGRect) -> CGPoint {
        let origin = CGPoint(
            x: petFrame.midX - 58 - 10 - panelSize.width / 2,
            y: petFrame.minY + 54 - panelSize.height / 2 + 40
        )
        return BirthdayPropLayout.clamped(
            origin, panelSize: panelSize, visibleFrame: visible
        )
    }

    private func startMotionTimer() {
        motionTimer?.invalidate()
        motionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.motionTick()
        }
    }

    private func stopMotionTimer() {
        motionTimer?.invalidate()
        motionTimer = nil
    }

    private func motionTick() {
        guard let propPanel, let kind = motionKind else { return }
        let elapsed = Date().timeIntervalSince(motionStart)
        let duration: TimeInterval = kind == .paperAirplane ? 3.5 : 3.0
        let t = CGFloat(min(max(elapsed / duration, 0), 1))
        let position: CGPoint
        if kind == .paperAirplane {
            position = SeasonalMotionMath.paperAirplanePosition(
                t: t, from: motionFrom, to: motionTo
            )
        } else {
            position = SeasonalMotionMath.approachPosition(t: t, from: motionFrom, to: motionTo)
        }
        propPanel.setFrameOrigin(position)
        if t >= 1 {
            stopMotionTimer()
        }
        // Throttled heartbeat proving frame-by-frame delivery to the
        // REAL presenter (1 Hz, no spam).
        let now = Date()
        if now.timeIntervalSince(lastUpdateLog) >= 1 {
            lastUpdateLog = now
            EventReplayLog.sceneUpdated(id: kind.replayArgument, phase: "approach")
        }
    }
}
