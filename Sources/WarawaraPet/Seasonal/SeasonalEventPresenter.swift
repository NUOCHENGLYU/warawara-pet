import AppKit
import SwiftUI

/// Pose published to the production scene view each choreography tick.
final class SeasonalSceneModel: ObservableObject {
    @Published var pose = SeasonalPropPose()
}

/// Effect overlay state (rain/confetti) for the second pooled panel.
final class SeasonalEffectModel: ObservableObject {
    @Published var asset: String = ""
    @Published var alpha: CGFloat = 0
}

/// Production realization of the seasonal + daily scenes, rewritten as a
/// POSE-DRIVEN choreography renderer:
/// - every frame's world position comes from `SeasonalChoreography`
///   through the semantic `EventAnchorSystem` anchors (held/grounded
///   props never drift to a screen corner);
/// - panels are sized from the painted content extents + margins, so
///   artwork can never be clipped by its own window;
/// - the pet's attention is ACQUIRED, TRACKED (~30 Hz) and RELEASED in
///   sync with the choreography;
/// - entrances differ per event (fall, materialize, reveal, reach,
///   emerge, flyby) and interactions run inside the scene phases.
final class SeasonalEventPresenter: SeasonalEventPresenting {
    private weak var windowController: PetWindowController?
    private weak var coordinator: SeasonalEventCoordinator?
    private let store: SeasonalAssetStore

    private var propPanel: BirthdayPropPanel?
    private var effectPanel: BirthdayPropPanel?
    private let sceneModel = SeasonalSceneModel()
    private let effectModel = SeasonalEffectModel()
    private var choreographyTimer: Timer?
    private var staticDebugTimer: Timer?
    private var phase: SeasonalPhase = .idle
    private var phaseStart = Date()
    private var sceneStart = Date()
    private var lastUpdateLog = Date(timeIntervalSince1970: 0)
    private var attentionDirection: CGVector?
    /// GROUNDED props keep a frozen world anchor captured at scene start:
    /// they never follow a pet window that moves during hop/float.
    private var frozenAnchors: EventAnchorSystem?

    /// Production-path observability (tests assert against the REAL
    /// presenter, not a fake).
    private(set) var presentCallCount = 0
    private(set) var rejectionReasons: [String] = []
    private(set) var departCallCount = 0
    var presentedPanel: BirthdayPropPanel? { propPanel }

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
        guard let kind = coordinator?.kind, let petFrame = windowController?.currentFrame,
              petFrame != .zero else { return }
        // The pet first looks toward where the prop will arrive from.
        let anchors = EventAnchorSystem(petFrame: petFrame)
        let target: CGPoint
        switch kind {
        case .cny:
            target = anchors.aboveHead
        case .paperAirplane:
            target = CGPoint(x: anchors.headCenter.x - 120, y: anchors.headCenter.y + 30)
        default:
            target = anchorPoint(kind: kind, anchors: anchors)
        }
        applyAttention(target: target, petFrame: petFrame)
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
        verifyAssets(kind: kind)
        ensurePanels(kind: kind)
        guard let propPanel else {
            reject(id: kind.replayArgument, reason: "panel-creation-failed")
            return
        }

        // First frame: entrance start position (alpha 0) at the anchor.
        phase = .approach
        phaseStart = Date()
        sceneStart = Date()
        frozenAnchors = EventAnchorSystem(petFrame: petFrame)
        let anchors = EventAnchorSystem(petFrame: petFrame)
        let startPose = SeasonalChoreography.pose(
            kind: kind, phase: .approach, elapsedInPhase: 0, totalElapsed: 0,
            anchors: anchors, visibleFrame: ScreenGeometry.visibleFrame(for: petFrame),
            timing: coordinator?.timing ?? .forKind(kind)
        )
        sceneModel.pose = startPose
        placePanels(pose: startPose, kind: kind, petFrame: petFrame)
        propPanel.orderFrontRegardless()
        effectPanel?.orderFrontRegardless()
        EventReplayLog.visible(id: kind.replayArgument)
        EventReplayLog.anchor(id: kind.replayArgument, anchor: anchorName(for: kind))
        verifyPresentedWindow(kind: kind, panel: propPanel)
        logPropGeometry(kind: kind, label: "first-appearance", petFrame: petFrame)
        startChoreographyTimer()
    }

    func settleProp() {
        phase = .present
        phaseStart = Date()
        if let kind = coordinator?.kind, let petFrame = windowController?.currentFrame {
            logPropGeometry(kind: kind, label: "held", petFrame: petFrame)
        }
    }

    func celebrateScene() {
        phase = .celebrate
        phaseStart = Date()
        if let kind = coordinator?.kind, let petFrame = windowController?.currentFrame {
            logPropGeometry(kind: kind, label: "max-extent", petFrame: petFrame)
        }
        // Release the gaze so the small celebration hop can run, then the
        // choreography loop re-acquires attention once the hop finishes.
        windowController?.setEventAttention(nil)
        attentionDirection = nil
        windowController?.performCelebrationHop()
    }

    func departScene() {
        departCallCount += 1
        phase = .depart
        phaseStart = Date()
        if let kind = coordinator?.kind, let petFrame = windowController?.currentFrame {
            logPropGeometry(kind: kind, label: "before-removal", petFrame: petFrame)
        }
    }

    func clearAttention() {
        attentionDirection = nil
        windowController?.setEventAttention(nil)
    }

    // MARK: - Developer static layout diagnostic (--prop-debug <kind>)

    /// Pins one prop at its semantic anchor, fully opaque, with NO
    /// choreography or random timing, logs the real runtime geometry once
    /// per second for six seconds, then exits. Uses the genuine
    /// SeasonalSceneView, real asset loading and real AppKit panels.
    func presentStaticProp(kind: SeasonalEventKind) {
        guard let petFrame = windowController?.currentFrame, petFrame != .zero else {
            EventReplayLog.sceneFailed(id: kind.replayArgument, reason: "invalid-geometry")
            exit(1)
        }
        verifyAssets(kind: kind)
        ensurePanels(kind: kind)
        guard let propPanel else {
            EventReplayLog.sceneFailed(id: kind.replayArgument, reason: "panel-creation-failed")
            exit(1)
        }
        let anchors = EventAnchorSystem(petFrame: petFrame)
        let visible = ScreenGeometry.visibleFrame(for: petFrame)
        let timing = SeasonalTiming.forKind(kind)
        var pose = SeasonalChoreography.pose(
            kind: kind, phase: .approach, elapsedInPhase: timing.approachDuration,
            totalElapsed: timing.approachDuration, anchors: anchors,
            visibleFrame: visible, timing: timing
        )
        if kind == .paperAirplane {
            // Park the plane at a fixed near-head point instead of
            // mid-flight.
            pose.position = CGPoint(x: anchors.headCenter.x + 46, y: anchors.headCenter.y + 30)
            pose.rotationDegrees = 0
            pose.showTrail = true
        }
        pose.alpha = 1
        sceneModel.pose = pose
        phase = .present
        placePanels(pose: pose, kind: kind, petFrame: petFrame)
        propPanel.alphaValue = 1
        propPanel.orderFrontRegardless()
        logPropGeometry(kind: kind, label: "static", petFrame: petFrame)

        var seconds = 0
        staticDebugTimer?.invalidate()
        staticDebugTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            seconds += 1
            self.logPropGeometry(kind: kind, label: "static+\(seconds)s", petFrame: petFrame)
            if seconds >= 6 {
                self.staticDebugTimer?.invalidate()
                self.staticDebugTimer = nil
                EventReplayLog.propDebugDone(id: kind.replayArgument)
                exit(0)
            }
        }
    }

    /// Emits the full runtime geometry record for the current prop panel.
    private func logPropGeometry(kind: SeasonalEventKind, label: String, petFrame: CGRect) {
        guard let propPanel else { return }
        let visible = ScreenGeometry.visibleFrame(for: petFrame)
        let panelFrame = propPanel.frame
        let extents = PropRenderGeometry.contentExtentRect(for: kind, lidLift: 1)
        let contentScreen = PropRenderGeometry.primaryContentScreenRect(
            panelFrame: panelFrame, kind: kind
        )
        let box = PropRenderGeometry.boxes[kind.primaryAsset]
        EventReplayLog.propGeometry(
            id: kind.replayArgument,
            asset: kind.primaryAsset,
            petFrame: petFrame,
            desiredWidth: (PropRenderGeometry.targetRatios[kind.primaryAsset] ?? 0)
                * PropRenderGeometry.petHeight,
            bboxPx: box.map { "\(Int($0.left)),\(Int($0.top)),\(Int($0.right)),\(Int($0.bottom))" } ?? "-",
            renderScale: PropRenderGeometry.scale(asset: kind.primaryAsset),
            contentFrameInPanel: extents,
            hostingBounds: propPanel.contentView?.bounds ?? .zero,
            panelFrame: panelFrame,
            screenFrame: visible,
            alpha: propPanel.alphaValue,
            level: propPanel.level,
            isVisible: propPanel.isVisible,
            phase: label,
            withinVisible: visible.intersects(contentScreen)
        )
    }

    // MARK: - Choreography loop (30 Hz — NOT the 1 Hz scheduler)

    private func startChoreographyTimer() {
        choreographyTimer?.invalidate()
        choreographyTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 30.0, repeats: true
        ) { [weak self] _ in
            self?.choreographyTick()
        }
    }

    private func stopChoreographyTimer() {
        choreographyTimer?.invalidate()
        choreographyTimer = nil
    }

    private func choreographyTick() {
        guard let kind = coordinator?.kind,
              let petFrame = windowController?.currentFrame, petFrame != .zero else { return }
        let now = Date()
        let elapsedInPhase = now.timeIntervalSince(phaseStart)
        let totalElapsed = now.timeIntervalSince(sceneStart)
        // Grounded props stay in their frozen world anchor; held/flying
        // props follow the live pet frame.
        let anchors = anchorsFor(kind: kind, livePetFrame: petFrame)
        let visible = ScreenGeometry.visibleFrame(for: petFrame)
        let timing = coordinator?.timing ?? .forKind(kind)

        let pose = SeasonalChoreography.pose(
            kind: kind, phase: phase, elapsedInPhase: elapsedInPhase,
            totalElapsed: totalElapsed, anchors: anchors,
            visibleFrame: visible, timing: timing
        )
        sceneModel.pose = pose
        placePanels(pose: pose, kind: kind, petFrame: petFrame)

        // Attention: acquired once, tracked every frame, released on
        // depart or fade-out.
        if let target = SeasonalChoreography.attentionTarget(
            kind: kind, phase: phase, elapsedInPhase: elapsedInPhase,
            totalElapsed: totalElapsed, anchors: anchors,
            visibleFrame: visible, timing: timing
        ) {
            applyAttention(target: target, petFrame: petFrame)
        } else if attentionDirection != nil {
            clearAttention()
        }

        // Effects panel alpha (rain/confetti) follows the pose.
        if let effectAsset = pose.effectAsset, pose.effectAlpha > 0 {
            effectModel.asset = effectAsset
            effectModel.alpha = pose.effectAlpha
        } else {
            effectModel.alpha = 0
        }

        // Depart fade-out ends the scene.
        if phase == .depart, pose.alpha <= 0.02 {
            finishScene()
        }

        // Throttled diagnostics (1 Hz).
        if now.timeIntervalSince(lastUpdateLog) >= 1 {
            lastUpdateLog = now
            EventReplayLog.sceneUpdated(id: kind.replayArgument, phase: String(describing: phase))
        }
    }

    private func finishScene() {
        stopChoreographyTimer()
        clearAttention()
        propPanel?.alphaValue = 0
        effectPanel?.alphaValue = 0
        effectModel.alpha = 0
    }

    // MARK: - Panels

    private func ensurePanels(kind: SeasonalEventKind) {
        let size = PropRenderGeometry.panelSize(for: kind)
        if propPanel == nil {
            let panel = BirthdayPropPanel(size: size, interactive: false)
            let hosting = NSHostingView(
                rootView: SeasonalSceneView(kind: kind, store: store, model: sceneModel)
            )
            hosting.frame = NSRect(origin: .zero, size: size)
            panel.contentView = hosting
            panel.alphaValue = 0
            propPanel = panel
        }
        if effectPanel == nil {
            let panel = BirthdayPropPanel(size: CGSize(width: 320, height: 320), interactive: false)
            let hosting = NSHostingView(
                rootView: SeasonalEffectView(store: store, model: effectModel)
            )
            hosting.frame = NSRect(origin: .zero, size: CGSize(width: 320, height: 320))
            panel.contentView = hosting
            panel.alphaValue = 0
            effectPanel = panel
        }
    }

    private func clampIntoVisible(_ origin: CGPoint, size: CGSize, visible: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, visible.minX + 4), max(visible.minX + 4, visible.maxX - size.width - 4)),
            y: min(max(origin.y, visible.minY + 4), max(visible.minY + 4, visible.maxY - size.height - 4))
        )
    }

    private func placePanels(pose: SeasonalPropPose, kind: SeasonalEventKind, petFrame: CGRect) {
        guard let propPanel else { return }
        let visible = ScreenGeometry.visibleFrame(for: petFrame)
        let size = PropRenderGeometry.panelSize(for: kind)
        let origin = PropRenderGeometry.panelOrigin(anchor: pose.position, kind: kind)
        // The paper airplane flies ACROSS screen edges by design: no
        // clamping on its flight path.
        let clamped = kind == .paperAirplane
            ? origin
            : clampIntoVisible(origin, size: size, visible: visible)
        propPanel.setFrameOrigin(clamped)
        propPanel.alphaValue = min(max(pose.alpha, 0), 1)

        if let effectPanel {
            let body = BirthdayPropLayout.petBodyRect(petFrame: petFrame)
            let effectFrame = CGRect(
                x: body.midX - 160, y: body.minY - 30,
                width: 320, height: 320
            )
            let clampedEffect = clampIntoVisible(
                effectFrame.origin, size: effectFrame.size, visible: visible
            )
            effectPanel.setFrame(CGRect(origin: clampedEffect, size: effectFrame.size), display: false)
            effectPanel.alphaValue = min(max(effectModel.alpha, 0), 1)
        }
    }

    // MARK: - Attention

    private func applyAttention(target: CGPoint, petFrame: CGRect) {
        let body = BirthdayPropLayout.petBodyRect(petFrame: petFrame)
        let direction = EventAttentionMath.direction(
            from: CGPoint(x: body.midX, y: body.midY),
            to: target
        )
        if direction == .zero { return }
        if attentionDirection == nil {
            attentionDirection = direction
            windowController?.setEventAttention(direction)
        } else if direction != attentionDirection {
            attentionDirection = direction
            windowController?.updateEventAttention(direction)
        }
    }

    // MARK: - Anchors

    /// Grounded props (christmas/newYear/cocoa/sprout) keep their frozen
    /// world anchor; held/flying props (cny/umbrella/airplane) track the
    /// live pet frame.
    private func anchorsFor(kind: SeasonalEventKind, livePetFrame: CGRect) -> EventAnchorSystem {
        switch kind {
        case .christmas, .newYear, .hotCocoa, .sprout:
            return frozenAnchors ?? EventAnchorSystem(petFrame: livePetFrame)
        case .cny, .umbrella, .paperAirplane:
            return EventAnchorSystem(petFrame: livePetFrame)
        }
    }

    private func anchorPoint(kind: SeasonalEventKind, anchors: EventAnchorSystem) -> CGPoint {
        switch kind {
        case .cny: return anchors.handFront
        case .christmas, .newYear: return anchors.groundBesidePet
        case .umbrella: return anchors.umbrellaGrip
        case .hotCocoa: return anchors.nearRightFoot
        case .sprout: return anchors.nearLeftFoot
        case .paperAirplane: return anchors.headCenter
        }
    }

    private func anchorName(for kind: SeasonalEventKind) -> String {
        switch kind {
        case .cny: return "handFront"
        case .christmas, .newYear: return "groundBesidePet"
        case .umbrella: return "umbrellaGrip"
        case .hotCocoa: return "nearRightFoot"
        case .sprout: return "nearLeftFoot"
        case .paperAirplane: return "independentFlightPath"
        }
    }

    // MARK: - Assets + presentation verification

    private func verifyAssets(kind: SeasonalEventKind) {
        for name in kind.displayedAssets {
            if store.image(named: name) != nil {
                EventReplayLog.assetLoaded(id: kind.replayArgument, name: name)
            } else {
                EventReplayLog.assetMissing(id: kind.replayArgument, name: name)
                reject(id: kind.replayArgument, reason: "missing-asset:\(name)")
            }
        }
        // Log the optional v3 layers actually used by this scene.
        for name in optionalAssetsUsed(by: kind) {
            if store.optionalImage(named: name) != nil {
                EventReplayLog.assetLoaded(id: kind.replayArgument, name: name)
            } else {
                EventReplayLog.assetMissing(id: kind.replayArgument, name: name)
            }
        }
    }

    private func optionalAssetsUsed(by kind: SeasonalEventKind) -> [String] {
        switch kind {
        case .cny: return ["cny_hongbao_open.png"]
        case .christmas: return ["xmas_gift_open_base.png", "xmas_gift_lid.png"]
        case .newYear: return ["newyear_confetti_overlay.png"]
        case .umbrella: return ["rain_drops_overlay.png"]
        case .paperAirplane: return ["paper_airplane_trail.png"]
        case .hotCocoa, .sprout: return []
        }
    }

    private func verifyPresentedWindow(kind: SeasonalEventKind, panel: BirthdayPropPanel) {
        let frame = panel.frame
        guard !frame.isEmpty,
              frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite else {
            reject(id: kind.replayArgument, reason: "invalid-window-frame")
            return
        }
        guard panel.contentView is NSHostingView<SeasonalSceneView> else {
            reject(id: kind.replayArgument, reason: "empty-content-view")
            return
        }
        EventReplayLog.windowPresented(
            id: kind.replayArgument,
            visible: panel.isVisible,
            frame: frame,
            level: panel.level,
            alpha: 1
        )
    }

    private func reject(id: String, reason: String) {
        rejectionReasons.append(reason)
        EventReplayLog.sceneFailed(id: id, reason: reason)
    }
}
