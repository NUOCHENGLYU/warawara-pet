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
    private var phase: SeasonalPhase = .idle
    private var phaseStart = Date()
    private var sceneStart = Date()
    private var lastUpdateLog = Date(timeIntervalSince1970: 0)
    private var attentionDirection: CGVector?

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
        startChoreographyTimer()
    }

    func settleProp() {
        phase = .present
        phaseStart = Date()
    }

    func celebrateScene() {
        phase = .celebrate
        phaseStart = Date()
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
    }

    func clearAttention() {
        attentionDirection = nil
        windowController?.setEventAttention(nil)
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
        let anchors = EventAnchorSystem(petFrame: petFrame)
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
        let size = SeasonalSceneMath.panelSize(for: kind)
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

    private func placePanels(pose: SeasonalPropPose, kind: SeasonalEventKind, petFrame: CGRect) {
        guard let propPanel else { return }
        let visible = ScreenGeometry.visibleFrame(for: petFrame)
        let size = SeasonalSceneMath.panelSize(for: kind)
        let origin = SeasonalSceneMath.origin(anchoredAt: pose.position, kind: kind)
        // The paper airplane flies ACROSS screen edges by design: no
        // clamping on its flight path.
        let clamped = kind == .paperAirplane
            ? origin
            : SeasonalSceneMath.clampedOrigin(origin, panelSize: size, visibleFrame: visible)
        propPanel.setFrameOrigin(clamped)
        propPanel.alphaValue = min(max(pose.alpha, 0), 1)

        if let effectPanel {
            let body = BirthdayPropLayout.petBodyRect(petFrame: petFrame)
            let effectFrame = CGRect(
                x: body.midX - 160, y: body.minY - 30,
                width: 320, height: 320
            )
            let clamped = SeasonalSceneMath.clampedOrigin(
                effectFrame.origin, panelSize: effectFrame.size, visibleFrame: visible
            )
            effectPanel.setFrame(CGRect(origin: clamped, size: effectFrame.size), display: false)
            effectPanel.alphaValue = min(max(effectModel.alpha, 0), 1)
        }
    }

    // MARK: - Attention

    private func applyAttention(target: CGPoint, petFrame: CGRect) {
        let direction = SeasonalSceneMath.attentionDirection(petFrame: petFrame, target: target)
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
