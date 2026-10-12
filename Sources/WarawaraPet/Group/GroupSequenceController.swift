import AppKit
import SwiftUI

/// Orchestrates the temporary companion group sequence with persistent,
/// per-companion kinematic state so motion carries inertia and phase
/// transitions are exactly position-continuous.
///
/// Lifecycle invariant: companion panels are POOLED, never closed or
/// ordered out while the app runs. They enter from fully off-screen,
/// travel through the choreography, exit spatially beyond the physical
/// top edge, and are parked off-screen (invisible) until the next
/// sequence. This guarantees the main pet panel is never affected by
/// window-close window-server maintenance and always remains visible.
final class GroupSequenceController {
    private struct CompanionRuntime {
        let config: CompanionConfig
        var kinematics: CompanionKinematics
        var hoverBase = CGPoint.zero
        var ascentStart = CGPoint.zero
        var released = false
        var exited = false
    }

    private weak var windowController: PetWindowController?

    private let tuning = GroupTuning.default
    private var model = GroupSequenceModel()
    private var rng = SystemRandomSource()
    private var panelPool: [CompanionPetPanel] = []
    private var panels: [Int: CompanionPetPanel] = [:]
    private var runtimes: [CompanionRuntime] = []
    private var timer: Timer?
    private var phaseStart = Date()
    private var lastTickTime = ProcessInfo.processInfo.systemUptime
    private var fadeStart = Date()
    private var releasePhaseTotal: TimeInterval = 1

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
            physicalFrame: physicalFrame,
            visibleFrame: visibleFrame,
            using: &rng,
            tuning: tuning
        ) else { return }
        onActiveChanged?(true)
        releasePhaseTotal = GroupMotionMath.releasePhaseDuration(
            configs: model.companions.map(\.config)
        )
        preparePanels()
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

    // MARK: - Panel lifecycle (pooling; never closes mid-session)

    /// Off-screen parking spot below the physical screen, far enough that
    /// parked panels are entirely invisible and never intercept input
    /// (they ignore mouse events anyway).
    private var restingPosition: CGPoint {
        CGPoint(
            x: physicalFrame.minX + tuning.companionPanelSize,
            y: physicalFrame.minY - tuning.companionPanelSize - 60
        )
    }

    private func preparePanels() {
        for companion in model.companions {
            let panel: CompanionPetPanel
            if let pooled = panelPool.popLast() {
                panel = pooled
                let hosting = NSHostingView(
                    rootView: CompanionPetView(scale: companion.config.scale)
                )
                hosting.frame = NSRect(
                    origin: .zero,
                    size: CGSize(
                        width: tuning.companionPanelSize,
                        height: tuning.companionPanelSize
                    )
                )
                panel.contentView = hosting
            } else {
                panel = CompanionPetPanel(size: tuning.companionPanelSize)
                let hosting = NSHostingView(
                    rootView: CompanionPetView(scale: companion.config.scale)
                )
                hosting.frame = NSRect(
                    origin: .zero,
                    size: CGSize(
                        width: tuning.companionPanelSize,
                        height: tuning.companionPanelSize
                    )
                )
                panel.contentView = hosting
            }
            panel.alphaValue = 1
            panel.setFrameOrigin(origin(for: companion.config.entryPoint))
            panel.orderFrontRegardless()
            panels[companion.config.id] = panel
            runtimes.append(
                CompanionRuntime(
                    config: companion.config,
                    kinematics: CompanionKinematics(
                        position: companion.config.entryPoint,
                        velocity: .zero
                    )
                )
            )
        }
    }

    private func parkPanel(id: Int) {
        guard let panel = panels.removeValue(forKey: id) else { return }
        panel.alphaValue = 0
        panel.setFrameOrigin(restingPosition)
        panelPool.append(panel)
    }

    private func parkAllPanels() {
        for id in Array(panels.keys) {
            parkPanel(id: id)
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
            for index in runtimes.indices {
                let config = runtimes[index].config
                if !runtimes[index].released, elapsed >= config.releaseDelay {
                    runtimes[index].released = true
                }
                if runtimes[index].released {
                    runtimes[index].kinematics.step(
                        toward: formationTarget(for: config.id),
                        dt: dt,
                        springStrength: config.springStrength,
                        damping: config.damping
                    )
                    updatePanel(id: config.id) {
                        $0.setFrameOrigin(self.origin(for: self.runtimes[index].kinematics.position))
                    }
                }
            }
            if elapsed >= releasePhaseTotal {
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
            if runtimes.allSatisfy(\.exited) || runtimes.isEmpty {
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
        let positions = runtimes.map(\.kinematics.position)
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
            updatePanel(id: config.id) {
                $0.alphaValue = 1
                $0.setFrameOrigin(self.origin(for: self.runtimes[index].kinematics.position))
            }
        }
    }

    private func stepAscent(dt: TimeInterval, elapsed: TimeInterval) {
        let activeIndices = runtimes.indices.filter { !runtimes[$0].exited }

        let positions = runtimes.map(\.kinematics.position)
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
        let adjusted = GroupMotionMath.separationAdjustedTargets(
            positions: positions,
            targets: targets,
            minSpacing: tuning.companionMinSpacing,
            strength: tuning.separationStrength
        )

        for index in activeIndices {
            let config = runtimes[index].config
            runtimes[index].kinematics.step(
                toward: adjusted[index],
                dt: dt,
                springStrength: tuning.ascentSpringStrength,
                damping: tuning.ascentDamping
            )
            let position = runtimes[index].kinematics.position
            updatePanel(id: config.id) {
                $0.alphaValue = 1
                $0.setFrameOrigin(self.origin(for: position))
            }

            // Individual spatial exit: park only once the ENTIRE panel
            // body is beyond the physical top edge. The emergency timeout
            // parks even if still on screen (should not normally fire).
            let panelFrame = CGRect(
                origin: origin(for: position),
                size: CGSize(width: tuning.companionPanelSize, height: tuning.companionPanelSize)
            )
            if GroupMotionMath.isFullyAboveTopEdge(
                panelFrame: panelFrame,
                physicalFrame: physicalFrame,
                margin: tuning.exitTopMargin
            ) || elapsed >= tuning.ascentMaxDuration {
                runtimes[index].exited = true
                parkPanel(id: config.id)
            }
        }
    }

    /// Idempotent: parks every remaining companion panel (never closes),
    /// clears runtime state, ends the sequence, and resumes scheduling
    /// exactly once.
    private func cleanup() {
        timer?.invalidate()
        timer = nil
        parkAllPanels()
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

    private var physicalFrame: CGRect {
        ScreenGeometry.physicalFrame(for: windowController?.currentFrame ?? .zero)
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
