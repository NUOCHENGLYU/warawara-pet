import AppKit
import SwiftUI

/// Orchestrates the temporary companion group sequence with persistent,
/// per-companion kinematic state so motion carries inertia and phase
/// transitions are exactly position-continuous. Companions also carry a
/// velocity-responsive soft-body pose (CompanionPoseEstimator) rendered
/// through CompanionPoseModel.
///
/// Lifecycle invariant: companion panels are POOLED, never closed or
/// ordered out while the app runs. They enter from fully off-screen,
/// travel through the choreography, exit through the top edge in a slow
/// staged crossing, and are parked off-screen (invisible) until the next
/// sequence. The main pet panel is never affected.
final class GroupSequenceController {
    private struct CompanionRuntime {
        let config: CompanionConfig
        var kinematics: CompanionKinematics
        var hoverBase = CGPoint.zero
        var ascentStart = CGPoint.zero
        var released = false
        var exited = false
        var viewportActive = false
        var viewportFrame = CGRect.zero
        let poseModel = CompanionPoseModel()
        var poseEstimator = CompanionPoseEstimator()
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

    /// Fired AFTER companion panels have been (re-)ordered front, so the
    /// birthday layering can re-assert props above them. Without this the
    /// cake/envelope sink behind every companion body.
    var onCompanionPanelsOrdered: (() -> Void)?

    /// Live companion centers (id -> screen position) each tick; the
    /// birthday presenter uses this to carry props with companions.
    var onCompanionCenters: (([Int: CGPoint]) -> Void)?

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
            x: physicalFrame.minX + CompanionMetrics.size,
            y: physicalFrame.minY - CompanionMetrics.size - 60
        )
    }

    private func preparePanels() {
        for companion in model.companions {
            let panel: CompanionPetPanel
            if let pooled = panelPool.popLast() {
                panel = pooled
            } else {
                panel = CompanionPetPanel(size: CompanionMetrics.size)
            }
            let runtime = CompanionRuntime(
                config: companion.config,
                kinematics: CompanionKinematics(
                    position: companion.config.entryPoint,
                    velocity: .zero
                )
            )
            let hosting = NSHostingView(
                rootView: CompanionPetView(scale: companion.config.scale, pose: runtime.poseModel)
            )
            hosting.frame = NSRect(
                origin: .zero,
                size: CGSize(width: CompanionMetrics.size, height: CompanionMetrics.size)
            )
            panel.contentView = hosting
            panel.alphaValue = 1
            panel.setFrame(
                CGRect(
                    origin: origin(for: companion.config.entryPoint),
                    size: CGSize(width: CompanionMetrics.size, height: CompanionMetrics.size)
                ),
                display: false
            )
            panel.orderFrontRegardless()
            panels[companion.config.id] = panel
            runtimes.append(runtime)
        }
        // Companions were just ordered ABOVE every other floating panel
        // (including the carried birthday props): tell the layering so it
        // can re-assert the cake/envelope in front of the carriers.
        onCompanionPanelsOrdered?()
    }

    private func parkPanel(id: Int) {
        guard let panel = panels.removeValue(forKey: id) else { return }
        if let index = runtimes.firstIndex(where: { $0.config.id == id }) {
            runtimes[index].poseModel.deformation = .neutral
            runtimes[index].poseModel.breathing = 1
            runtimes[index].poseModel.contentOffset = .zero
            runtimes[index].poseEstimator.reset()
            runtimes[index].viewportActive = false
        }
        panel.alphaValue = 0
        // Restore the standard panel size so pooled reuse is safe even
        // after a viewport-resized exit.
        panel.setFrame(
            CGRect(origin: restingPosition, size: CGSize(width: CompanionMetrics.size, height: CompanionMetrics.size)),
            display: false
        )
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

        publishCompanionCenters()

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
                    updatePose(index: index, now: now)
                    updatePanel(id: config.id) {
                        $0.setFrameOrigin(self.origin(for: self.renderedPosition(of: self.runtimes[index])))
                    }
                }
            }
            if elapsed >= releasePhaseTotal {
                transition(to: .gathering)
            }
        case .gathering:
            let elapsed = Date().timeIntervalSince(phaseStart)
            stepGathering(dt: dt, now: now)
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
            for index in runtimes.indices {
                let runtime = runtimes[index]
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
                runtime.poseModel.deformation = .neutral
                runtime.poseModel.breathing = CompanionPoseEstimator.breathingScale(
                    at: elapsed, config: runtime.config, tuning: tuning
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
            stepAscent(dt: dt, elapsed: elapsed, now: now)
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

    private func updatePose(index: Int, now: TimeInterval) {
        let velocity = runtimes[index].kinematics.velocity
        runtimes[index].poseEstimator.update(velocity: velocity, at: now)
        runtimes[index].poseModel.deformation = runtimes[index].poseEstimator.pose
        runtimes[index].poseModel.breathing = 1
    }

    private func stepGathering(dt: TimeInterval, now: TimeInterval) {
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
            updatePose(index: index, now: now)
            updatePanel(id: config.id) {
                $0.alphaValue = 1
                $0.setFrameOrigin(self.origin(for: self.renderedPosition(of: self.runtimes[index])))
            }
        }
    }

    private func stepAscent(dt: TimeInterval, elapsed: TimeInterval, now: TimeInterval) {
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
            let beforeY = runtimes[index].kinematics.position.y
            runtimes[index].kinematics.step(
                toward: adjusted[index],
                dt: dt,
                springStrength: tuning.ascentSpringStrength,
                damping: tuning.ascentDamping
            )

            // Staged exit across the VISIBLE top boundary: once the body
            // top is inside the slow zone, rise at a slow constant speed.
            // After the timeout the same slow progression is forced
            // instead of hiding anything.
            let bodyHalfHeight = CompanionMetrics.blobHeight * config.scale / 2
            let bodyTopY = runtimes[index].kinematics.position.y + bodyHalfHeight
            let exitTopY = visibleFrame.maxY
            if GroupMotionMath.isInExitSlowZone(
                bodyTopY: bodyTopY,
                topY: exitTopY,
                zoneHeight: tuning.exitSlowZoneHeight
            ) || elapsed >= tuning.ascentMaxDuration {
                // Continuous handoff into the slow exit speed: the
                // vertical velocity eases toward exitSlowSpeed instead
                // of snapping, so position and velocity both stay
                // continuous through the boundary crossing.
                runtimes[index].kinematics.velocity.dy = GroupMotionMath.exitVelocityBlend(
                    current: runtimes[index].kinematics.velocity.dy,
                    target: config.exitSlowSpeed,
                    dt: dt,
                    timeConstant: tuning.exitSlowBlendTimeConstant
                )
                runtimes[index].kinematics.position.y = beforeY + runtimes[index].kinematics.velocity.dy * CGFloat(dt)
            }

            updatePose(index: index, now: now)
            let position = runtimes[index].kinematics.position

            // Screen-contained top-exit viewport handoff: once the body
            // top is near the visible boundary, freeze the panel with its
            // top edge exactly at the boundary and let the character keep
            // rising inside it, clipped by the panel's top edge. The
            // character's global position, velocity, and pose all remain
            // continuous (the local offset is derived from the same
            // world-space position).
            if !runtimes[index].viewportActive,
               bodyTopY >= exitTopY - tuning.exitHandoffMargin {
                let frame = GroupMotionMath.exitViewportFrame(
                    characterCenter: position,
                    topY: exitTopY,
                    visibleFrame: visibleFrame,
                    tuning: tuning
                )
                runtimes[index].viewportFrame = frame
                runtimes[index].viewportActive = true
                panels[config.id]?.setFrame(frame, display: true)
                panels[config.id]?.contentView?.frame = CGRect(origin: .zero, size: frame.size)
            }

            if runtimes[index].viewportActive {
                let offset = GroupMotionMath.localOffset(
                    characterCenter: position,
                    viewportFrame: runtimes[index].viewportFrame
                )
                runtimes[index].poseModel.contentOffset = CGPoint(x: offset.dx, y: offset.dy)
            } else {
                updatePanel(id: config.id) {
                    $0.alphaValue = 1
                    $0.setFrameOrigin(self.origin(for: position))
                }
            }

            // Recycle only after the ENTIRE rendered body (global
            // character bounds) has passed the visible top boundary.
            if GroupMotionMath.isCharacterFullyAboveTopEdge(
                characterCenterY: position.y,
                scale: config.scale,
                topY: exitTopY,
                margin: tuning.exitTopMargin
            ) {
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

    private func publishCompanionCenters() {
        guard let onCompanionCenters else { return }
        var centers: [Int: CGPoint] = [:]
        for runtime in runtimes {
            centers[runtime.config.id] = renderedPosition(of: runtime)
        }
        onCompanionCenters(centers)
    }

    /// The RENDERED companion center: kinematic position plus the
    /// approach hop/bob (appearing and gathering only). Carried props
    /// follow THIS position so they share the exact same hop motion.
    private func renderedPosition(of runtime: CompanionRuntime) -> CGPoint {
        var position = runtime.kinematics.position
        if model.state == .appearing || model.state == .gathering {
            let elapsed = Date().timeIntervalSince(phaseStart)
            let bob = GroupMotionMath.approachBob(
                speed: runtime.kinematics.speed,
                maxAmplitude: tuning.approachBobAmplitude,
                phase: CGFloat(runtime.config.releaseDelay) * 7,
                time: elapsed,
                hopPeriod: tuning.approachBobPeriod
            )
            position.y += bob
        }
        return position
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
        CGPoint(x: center.x - CompanionMetrics.size / 2, y: center.y - CompanionMetrics.size / 2)
    }
}
