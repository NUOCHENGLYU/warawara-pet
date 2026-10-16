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
        guard let kind = coordinator?.kind, let petFrame = windowController?.currentFrame,
              petFrame != .zero else { return }
        ensurePanel(kind: kind)
        guard let propPanel else { return }
        let visible = ScreenGeometry.visibleFrame(for: petFrame)
        let rest = restOrigin(petFrame: petFrame, visible: visible)
        let start = CGPoint(x: rest.x - 220, y: rest.y + 60)

        if kind == .paperAirplane {
            glideActive = true
            motionKind = kind
            motionFrom = start
            motionTo = rest
            motionStart = Date()
            propPanel.alphaValue = 0
            propPanel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                propPanel.animator().alphaValue = 1
            }
            startMotionTimer()
        } else {
            propPanel.setFrameOrigin(start)
            propPanel.alphaValue = 0
            propPanel.orderFrontRegardless()
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
        guard propPanel == nil else {
            updateContent(kind: kind)
            return
        }
        let panel = BirthdayPropPanel(size: panelSize, interactive: false)
        panel.alphaValue = 0
        updateContent(kind: kind)
        propPanel = panel
    }

    private func updateContent(kind: SeasonalEventKind) {
        guard let propPanel else { return }
        let view = SeasonalPropView(
            kind: kind,
            store: store,
            primarySize: kind.primaryDisplayPoints,
            showSecondary: false
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
    }
}
