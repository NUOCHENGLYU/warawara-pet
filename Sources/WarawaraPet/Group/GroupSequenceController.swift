import AppKit
import SwiftUI

/// Orchestrates the temporary companion group sequence: staggered
/// appearance around the main pet, eased gathering, organic hover,
/// accelerating ascent, and a soft fade-out — or an immediate safe
/// cancellation. Companions are lightweight non-interactive panels driven
/// by one master timer; the main pet's core state model is never touched.
final class GroupSequenceController {
    private weak var windowController: PetWindowController?

    private let tuning = GroupTuning.default
    private var model = GroupSequenceModel()
    private var rng = SystemRandomSource()
    private var panels: [Int: CompanionPetPanel] = [:]
    private var timer: Timer?
    private var phaseStart = Date()
    private var fadeStart = Date()
    private var appearPhaseTotal: TimeInterval = 1

    /// Called when the sequence becomes active (true) and when it fully
    /// ends (false); the main pet uses this to pause/resume autonomous
    /// scheduling.
    var onActiveChanged: ((Bool) -> Void)?

    init(windowController: PetWindowController) {
        self.windowController = windowController
    }

    var state: GroupSequenceState { model.state }

    // MARK: - Start / cancel

    func start() {
        guard model.state == .inactive else { return }
        guard model.begin(using: &rng, tuning: tuning) else { return }
        onActiveChanged?(true)
        appearPhaseTotal = GroupMotionMath.appearPhaseDuration(
            configs: model.companions.map(\.config),
            fadeDuration: tuning.appearFadeDuration
        )
        createPanels()
        phaseStart = Date()
        startTimer()
    }

    func cancel() {
        switch model.state {
        case .appearing, .gathering, .hovering, .ascending:
            transition(to: .cancelled)
        default:
            break
        }
    }

    // MARK: - Lifecycle internals

    private func createPanels() {
        for companion in model.companions {
            let panel = CompanionPetPanel(size: tuning.companionPanelSize)
            let hosting = NSHostingView(rootView: CompanionPetView(scale: companion.config.scale))
            hosting.frame = NSRect(
                origin: .zero,
                size: CGSize(width: tuning.companionPanelSize, height: tuning.companionPanelSize)
            )
            panel.contentView = hosting
            let spawn = GroupMotionMath.spawnPosition(
                mainCenter: mainCenter,
                offset: companion.config.spawnOffset,
                visibleFrame: visibleFrame,
                margin: tuning.spawnMargin
            )
            panel.setFrameOrigin(origin(for: spawn))
            panel.orderFrontRegardless()
            panels[companion.config.id] = panel
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func transition(to newState: GroupSequenceState) {
        guard model.advance(to: newState) else { return }
        phaseStart = Date()
        if newState == .finishing || newState == .cancelled {
            fadeStart = Date()
        }
    }

    private func tick() {
        switch model.state {
        case .inactive:
            break
        case .appearing:
            let elapsed = Date().timeIntervalSince(phaseStart)
            for companion in model.companions {
                let config = companion.config
                let alpha = GroupMotionMath.appearAlpha(
                    at: elapsed,
                    delay: config.appearDelay,
                    duration: tuning.appearFadeDuration
                )
                updatePanel(id: config.id) { panel in
                    panel.alphaValue = alpha
                    if alpha > 0 {
                        panel.setFrameOrigin(self.origin(for: self.spawnPosition(for: config)))
                    }
                }
            }
            if elapsed >= appearPhaseTotal {
                transition(to: .gathering)
            }
        case .gathering:
            let elapsed = Date().timeIntervalSince(phaseStart)
            for companion in model.companions {
                let config = companion.config
                let t = CGFloat(min(elapsed / config.gatherDuration, 1))
                let spawn = spawnPosition(for: config)
                let gather = gatherPosition(for: config)
                let position = GroupMotionMath.gatherPosition(at: t, from: spawn, to: gather)
                updatePanel(id: config.id) { panel in
                    panel.alphaValue = 1
                    panel.setFrameOrigin(self.origin(for: position))
                }
            }
            if elapsed >= model.companions.map(\.config.gatherDuration).max() ?? 0 {
                transition(to: .hovering)
            }
        case .hovering:
            let elapsed = Date().timeIntervalSince(phaseStart)
            for companion in model.companions {
                let config = companion.config
                let base = gatherPosition(for: config)
                let offset = GroupMotionMath.hoverOffset(at: elapsed, config: config, tuning: tuning)
                let position = CGPoint(x: base.x + offset.dx, y: base.y + offset.dy)
                updatePanel(id: config.id) { panel in
                    panel.alphaValue = 1
                    panel.setFrameOrigin(self.origin(for: position))
                }
            }
            if elapsed >= tuning.hoverDuration {
                transition(to: .ascending)
            }
        case .ascending:
            let elapsed = Date().timeIntervalSince(phaseStart)
            for companion in model.companions {
                let config = companion.config
                let base = gatherPosition(for: config)
                let offset = GroupMotionMath.ascentOffset(at: elapsed, config: config, tuning: tuning)
                let position = CGPoint(x: base.x + offset.dx, y: base.y + offset.dy)
                updatePanel(id: config.id) { panel in
                    panel.alphaValue = 1
                    panel.setFrameOrigin(self.origin(for: position))
                }
            }
            if elapsed >= tuning.ascentDuration {
                transition(to: .finishing)
            }
        case .finishing, .cancelled:
            let fadeElapsed = Date().timeIntervalSince(fadeStart)
            let alpha = GroupMotionMath.fadeAlpha(
                at: fadeElapsed,
                duration: tuning.fadeOutDuration
            )
            for panel in panels.values {
                panel.alphaValue = alpha
            }
            if fadeElapsed >= tuning.fadeOutDuration {
                cleanup()
            }
        }
    }

    private func cleanup() {
        timer?.invalidate()
        timer = nil
        for panel in panels.values {
            panel.close()
        }
        panels.removeAll()
        model.removeAllCompanions()
        _ = model.advance(to: .inactive)
        onActiveChanged?(false)
    }

    private func updatePanel(id: Int, apply: (CompanionPetPanel) -> Void) {
        guard let panel = panels[id] else { return }
        apply(panel)
    }

    // MARK: - Geometry helpers

    private var mainCenter: CGPoint {
        guard let frame = windowController?.currentFrame else { return .zero }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private var visibleFrame: CGRect {
        ScreenGeometry.visibleFrame(for: windowController?.currentFrame ?? .zero)
    }

    private func spawnPosition(for config: CompanionConfig) -> CGPoint {
        GroupMotionMath.spawnPosition(
            mainCenter: mainCenter,
            offset: config.spawnOffset,
            visibleFrame: visibleFrame,
            margin: tuning.spawnMargin
        )
    }

    private func gatherPosition(for config: CompanionConfig) -> CGPoint {
        CGPoint(x: mainCenter.x + config.gatherOffset.dx, y: mainCenter.y + config.gatherOffset.dy)
    }

    private func origin(for center: CGPoint) -> CGPoint {
        CGPoint(x: center.x - tuning.companionPanelSize / 2, y: center.y - tuning.companionPanelSize / 2)
    }
}
