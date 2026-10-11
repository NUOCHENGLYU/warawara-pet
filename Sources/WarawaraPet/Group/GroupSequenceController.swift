import AppKit
import SwiftUI

/// Orchestrates the temporary companion group sequence with persistent,
/// per-companion kinematic state so motion carries inertia and phase
/// transitions are exactly position-continuous. Companions are
/// lightweight non-interactive panels; the main pet's core state model is
/// never touched.
final class GroupSequenceController {
    private struct CompanionRuntime {
        let config: CompanionConfig
        var kinematics: CompanionKinematics
        var hoverBase = CGPoint.zero
        var ascentStart = CGPoint.zero
        var fadeElapsed: TimeInterval?
    }

    private weak var windowController: PetWindowController?

    private let tuning = GroupTuning.default
    private var model = GroupSequenceModel()
    private var rng = SystemRandomSource()
    private var panels: [Int: CompanionPetPanel] = [:]
    private var runtimes: [CompanionRuntime] = []
    private var timer: Timer?
    private var phaseStart = Date()
    private var lastTickTime = ProcessInfo.processInfo.systemUptime
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
        guard model.begin(
            mainCenter: mainCenter,
            visibleFrame: visibleFrame,
            using: &rng,
            tuning: tuning
        ) else { return }
        onActiveChanged?(true)
        appearPhaseTotal = GroupMotionMath.appearPhaseDuration(
            configs: model.companions.map(\.config),
            fadeDuration: tuning.appearFadeDuration
        )
        createPanels()
        lastTickTime = ProcessInfo.processInfo.systemUptime
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
            runtimes.append(
                CompanionRuntime(
                    config: companion.config,
                    kinematics: CompanionKinematics(position: spawn, velocity: .zero)
                )
            )
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
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastTickTime
        lastTickTime = now

        switch model.state {
        case .inactive:
            break
        case .appearing:
            let elapsed = Date().timeIntervalSince(phaseStart)
            for runtime in runtimes {
                let alpha = GroupMotionMath.appearAlpha(
                    at: elapsed,
                    delay: runtime.config.appearDelay,
                    duration: tuning.appearFadeDuration
                )
                updatePanel(id: runtime.config.id) { $0.alphaValue = alpha }
            }
            if elapsed >= appearPhaseTotal {
                transition(to: .gathering)
            }
        case .gathering:
            let elapsed = Date().timeIntervalSince(phaseStart)
            stepGathering(dt: dt)
            let settled = runtimes.allSatisfy { runtime in
                let target = formationTarget(for: runtime.config.id)
                return runtime.kinematics.speed < tuning.gatherSettleSpeed
                    && runtime.kinematics.distance(to: target) < tuning.gatherSettleDistance
            }
            if settled || elapsed >= tuning.gatherMaxDuration {
                for index in runtimes.indices {
                    runtimes[index].hoverBase = runtimes[index].kinematics.position
                }
                transition(to: .hovering)
            }
        case .hovering:
            let elapsed = Date().timeIntervalSince(phaseStart)
            for runtime in runtimes {
                let offset = GroupMotionMath.hoverOffset(
                    at: elapsed,
                    rampInDuration: tuning.hoverRampInDuration,
                    config: runtime.config,
                    tuning: tuning
                )
                let position = CGPoint(
                    x: runtime.hoverBase.x + offset.dx,
                    y: runtime.hoverBase.y + offset.dy
                )
                updatePanel(id: runtime.config.id) {
                    $0.alphaValue = 1
                    $0.setFrameOrigin(self.origin(for: position))
                }
            }
            if elapsed >= tuning.hoverDuration {
                for index in runtimes.indices {
                    let offset = GroupMotionMath.hoverOffset(
                        at: tuning.hoverDuration,
                        rampInDuration: tuning.hoverRampInDuration,
                        config: runtimes[index].config,
                        tuning: tuning
                    )
                    let rendered = CGPoint(
                        x: runtimes[index].hoverBase.x + offset.dx,
                        y: runtimes[index].hoverBase.y + offset.dy
                    )
                    runtimes[index].ascentStart = rendered
                    runtimes[index].kinematics = CompanionKinematics(
                        position: rendered,
                        velocity: .zero
                    )
                }
                transition(to: .ascending)
            }
        case .ascending:
            let elapsed = Date().timeIntervalSince(phaseStart)
            stepAscent(dt: dt, elapsed: elapsed)
            if runtimes.allSatisfy({ $0.fadeElapsed != nil && ($0.fadeElapsed ?? 0) >= tuning.exitFadeDuration })
                || runtimes.isEmpty {
                transition(to: .finishing)
                cleanup()
            }
        case .finishing, .cancelled:
            let fadeElapsed = Date().timeIntervalSince(fadeStart)
            let alpha = GroupMotionMath.fadeAlpha(at: fadeElapsed, duration: tuning.fadeOutDuration)
            for panel in panels.values {
                panel.alphaValue = alpha
            }
            if fadeElapsed >= tuning.fadeOutDuration {
                cleanup()
            }
        }
    }

    // MARK: - Motion steps

    private func stepGathering(dt: TimeInterval) {
        var positions = runtimes.map(\.kinematics.position)
        var targets = runtimes.map { formationTarget(for: $0.config.id) }
        targets = GroupMotionMath.separationAdjustedTargets(
            positions: positions,
            targets: targets,
            minSpacing: tuning.companionMinSpacing,
            strength: tuning.separationStrength
        )
        for index in runtimes.indices {
            let config = runtimes[index].config
            runtimes[index].kinematics.step(
                toward: targets[index],
                dt: dt,
                springStrength: config.springStrength,
                damping: config.damping
            )
            let position = runtimes[index].kinematics.position
            positions[index] = position
            updatePanel(id: config.id) {
                $0.alphaValue = 1
                $0.setFrameOrigin(self.origin(for: position))
            }
        }
    }

    private func stepAscent(dt: TimeInterval, elapsed: TimeInterval) {
        var activeIndices: [Int] = []
        for index in runtimes.indices where runtimes[index].fadeElapsed == nil {
            activeIndices.append(index)
        }

        var positions = runtimes.map(\.kinematics.position)
        var targets = runtimes.map(\.ascentStart)
        for index in activeIndices {
            let config = runtimes[index].config
            let e = CGFloat(max(elapsed - config.exitStagger, 0))
            let sway = GroupMotionMath.ascentSway(
                at: e, config: config, tuning: tuning
            )
            targets[index].x += config.exitTargetOffset.dx + sway
            targets[index].y += config.exitTargetOffset.dy
        }
        targets = GroupMotionMath.separationAdjustedTargets(
            positions: positions,
            targets: targets,
            minSpacing: tuning.companionMinSpacing,
            strength: tuning.separationStrength
        )

        for index in activeIndices {
            let config = runtimes[index].config
            runtimes[index].kinematics.step(
                toward: targets[index],
                dt: dt,
                springStrength: tuning.ascentSpringStrength,
                damping: tuning.ascentDamping
            )
            let position = runtimes[index].kinematics.position
            positions[index] = position
            let topY = position.y + tuning.companionPanelSize / 2
            updatePanel(id: config.id) {
                $0.alphaValue = 1
                $0.setFrameOrigin(self.origin(for: position))
            }

            // Individual exit: fade near the top edge and remove once
            // fully gone — companions leave one by one.
            if runtimes[index].fadeElapsed == nil {
                if GroupMotionMath.isAboveExitFadeZone(
                    panelTopY: topY, visibleFrame: visibleFrame, margin: tuning.exitFadeTopMargin
                ) || elapsed >= tuning.ascentMaxDuration {
                    runtimes[index].fadeElapsed = 0
                }
            }
        }

        for index in runtimes.indices {
            guard var fade = runtimes[index].fadeElapsed else { continue }
            fade += dt
            runtimes[index].fadeElapsed = fade
            let alpha = GroupMotionMath.fadeAlpha(
                at: fade, duration: tuning.exitFadeDuration
            )
            panels[runtimes[index].config.id]?.alphaValue = alpha
            if fade >= tuning.exitFadeDuration {
                panels[runtimes[index].config.id]?.close()
                panels.removeValue(forKey: runtimes[index].config.id)
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
        runtimes.removeAll()
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

    private func formationTarget(for id: Int) -> CGPoint {
        guard id < model.formationOffsets.count else { return mainCenter }
        let vector = model.formationOffsets[id]
        return CGPoint(x: mainCenter.x + vector.dx, y: mainCenter.y + vector.dy)
    }

    private func origin(for center: CGPoint) -> CGPoint {
        CGPoint(x: center.x - tuning.companionPanelSize / 2, y: center.y - tuning.companionPanelSize / 2)
    }
}
