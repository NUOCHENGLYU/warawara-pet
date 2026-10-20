import AppKit
import SwiftUI

final class PetWindowController: NSObject {
    static let petSize = PetMetrics.size
    static let windowMargin: CGFloat = 8

    private var panel: PetPanel?
    private var hostingView: PetHostingView?
    private var controller: PetController?
    private var motionController: PetMotionController?
    private var interactionController: PetInteractionController?
    /// Invoked when the user double-clicks the main pet (birthday
    /// letter reopen path).
    var onPetDoubleClick: (() -> Void)?
    private var positionStore: PetPositionStore?
    private var screenObserver: NSObjectProtocol?
    private var groupSequenceController: GroupSequenceController?
    private var groupActiveObservers: [(Bool) -> Void] = []
    /// Sleep/wake + display lifecycle recovery (throttled, non-activating).
    private var lifecycleMonitor: WindowLifecycleMonitor?

    var currentFrame: CGRect {
        panel?.frame ?? .zero
    }

    /// The pet panel (lifecycle recovery + tests).
    var petPanel: PetPanel? { panel }

    /// Restores the pet panel when it was hidden or ended up off-screen
    /// (e.g. the display it lived on was unplugged during sleep). This
    /// only restores the WINDOW — it never wakes a sleepy/sleeping pet.
    @discardableResult
    func restorePetWindow(reason: String) -> Bool {
        guard let panel else { return false }
        let frame = panel.frame
        let screens = ScreenGeometry.screenVisibleFrames()
        // Defense in depth (same guard as the monitor): a transiently
        // empty screen list must never move a healthy panel into the
        // hardcoded fallback box. Defer and let the next real check run.
        guard !screens.isEmpty else {
            LifecycleDiagnostics.log("RECOVERY_DEFERRED_NO_SCREENS", details: "reason=\(reason)")
            return false
        }
        let needs = WindowRecovery.needsRecovery(
            frame: frame, screens: screens, isVisible: panel.isVisible
        )
        guard needs else { return false }
        let mainVisible = NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let recovered = WindowRecovery.recoveryFrame(
            frame, screens: screens, mainScreenVisible: mainVisible,
            margin: Self.windowMargin
        )
        panel.setFrame(recovered, display: true)
        panel.orderFrontRegardless()
        LifecycleDiagnostics.log("WINDOW_RECOVERED", details: "reason=\(reason)")
        return true
    }

    // MARK: - Fault injection (development only; explicit CLI flags)

    /// Moves the panel far off every screen (simulates an unplugged
    /// display restoring a stale frame).
    func injectOffscreenFrame() {
        guard let panel else { return }
        panel.setFrameOrigin(CGPoint(x: 999_999, y: 999_999))
        LifecycleDiagnostics.log("FAULT_INJECT", details: "name=offscreen-frame")
    }

    /// Hides the panel entirely (simulates the hidden-after-wake case).
    func injectHiddenPanel() {
        guard let panel else { return }
        panel.orderOut(nil)
        LifecycleDiagnostics.log("FAULT_INJECT", details: "name=hidden-panel")
    }

    /// True while the user is actively dragging the main pet (birthday
    /// triggering is deferred while this is true).
    var isPetDragging: Bool {
        controller?.state == .dragged
    }

    /// True while the pet is dozing or asleep (seasonal/daily events
    /// never interrupt sleep).
    var isPetSleeping: Bool {
        controller?.state == .sleepy || controller?.state == .sleeping
    }

    /// Registers an observer for companion-group activity (birthday
    /// coordinator uses this to know when gathering/ascension ends).
    func addGroupActiveObserver(_ observer: @escaping (Bool) -> Void) {
        groupActiveObservers.append(observer)
    }

    /// Starts the companion group sequence through the existing Phase 3
    /// infrastructure (never a second group system).
    func startCompanionGroupSequence() {
        groupSequenceController?.start()
    }

    func cancelCompanionGroupSequence() {
        groupSequenceController?.cancel()
    }

    /// Small celebratory hop of the main pet (public birthday hook into
    /// the existing hop motion).
    func performBirthdayHop() {
        controller?.performBirthdayHop()
    }

    /// Small deterministic celebration hop (seasonal/daily celebrate).
    func performCelebrationHop() {
        controller?.performCelebrationHop()
    }

    /// Event-driven attention: the pet turns to look at a specific
    /// direction (birthday choreography).
    func setEventAttention(_ direction: CGVector?) {
        controller?.setEventAttention(direction)
    }

    /// Per-frame event-attention tracking update (moving props).
    func updateEventAttention(_ direction: CGVector) {
        controller?.updateEventAttention(direction)
    }

    /// The meteor wish beat: eyes close softly while active.
    func setWishing(_ on: Bool) {
        controller?.setWishing(on)
    }

    /// Companion center positions observer (birthday props ride along
    /// with carrier companions during delivery).
    func setCompanionCentersObserver(_ observer: @escaping ([Int: CGPoint]) -> Void) {
        groupSequenceController?.onCompanionCenters = observer
    }

    /// Companion panel ordering observer (birthday layering re-asserts
    /// props above carriers whenever companions are (re-)ordered front).
    func setCompanionPanelsOrderedObserver(_ observer: @escaping () -> Void) {
        groupSequenceController?.onCompanionPanelsOrdered = observer
    }

    /// Companion ascent observer (the main pet gazes toward the exit).
    func setCompanionAscentObserver(_ observer: @escaping () -> Void) {
        groupSequenceController?.onAscentBegan = observer
    }

    /// Test hook: installs a bare pet panel at a known frame without the
    /// autonomous machinery, so production presenters can be exercised
    /// against a REAL AppKit window boundary.
    func configureForTesting(frame: CGRect) {
        let panel = PetPanel(size: frame.size)
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// Re-asserts the pet panel's visibility (defensive recovery after
    /// the letter window closes or app deactivation).
    func reassertPetVisibility() {
        panel?.orderFrontRegardless()
    }

    func setWindowFrame(_ frame: CGRect, animated: Bool) {
        guard let panel else { return }
        let clamped = ScreenGeometry.clampFrame(
            frame,
            to: ScreenGeometry.visibleFrame(for: frame),
            margin: Self.windowMargin
        )
        panel.setFrame(clamped, display: true, animate: animated)
    }

    func showPet() {
        let store = PetPositionStore()
        let motion = PetMotionController(windowController: self)
        let petController = PetController(
            windowController: self,
            motionController: motion,
            positionStore: store
        )
        let interaction = PetInteractionController(windowController: self, controller: petController)

        // Assign the store and controllers BEFORE any restoration logic
        // reads them; otherwise the saved position is silently ignored.
        self.positionStore = store
        self.controller = petController
        self.motionController = motion
        self.interactionController = interaction

        let panel = PetPanel(size: Self.petSize)

        let hostingView = PetHostingView(rootView: PetView(controller: petController))
        hostingView.frame = NSRect(origin: .zero, size: Self.petSize)
        hostingView.interactionController = interaction
        interaction.onDoubleClick = { [weak self] in
            self?.onPetDoubleClick?()
        }

        panel.contentView = hostingView
        panel.setFrame(restoredPositionFrame(using: store), display: false)
        panel.orderFrontRegardless()

        self.panel = panel
        self.hostingView = hostingView

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let frame = self.panel?.frame else { return }
            LifecycleDiagnostics.screenChange(screenCount: NSScreen.screens.count)
            // Clamp into the current displays; if the panel was hidden
            // or lost its screen, recover it (throttled, non-activating).
            self.setWindowFrame(frame, animated: false)
            self.lifecycleMonitor?.checkAndRestore(reason: "screen-change")
        }

        petController.startAutonomousBehavior()
        wireGroupSequence()
        startLifecycleMonitor()
    }

    private func startLifecycleMonitor() {
        guard lifecycleMonitor == nil else { return }
        let monitor = WindowLifecycleMonitor(windowController: self)
        monitor.start()
        lifecycleMonitor = monitor
    }

    /// Runs one recovery check (reopen/wake paths use this). The monitor
    /// is created lazily so test harnesses and fault injection work even
    /// without the full showPet() pipeline.
    @discardableResult
    func runRecoveryCheck(reason: String) -> Bool {
        startLifecycleMonitor()
        return lifecycleMonitor?.checkAndRestore(reason: reason) ?? false
    }

    // MARK: - Group sequence (Phase 3)

    private func wireGroupSequence() {
        let sequence = GroupSequenceController(windowController: self)
        sequence.onActiveChanged = { [weak self] active in
            guard let self else { return }
            self.controller?.setGroupSequenceActive(active)
            for observer in self.groupActiveObservers {
                observer(active)
            }
        }
        controller?.onUserInteraction = { [weak self] in
            // User interaction always wins: cancel the group sequence.
            self?.groupSequenceController?.cancel()
        }
        groupSequenceController = sequence

        GroupLaunchTrigger.startIfRequested { [weak self] in
            self?.groupSequenceController?.start()
        }
    }

    func saveCurrentPosition() {
        guard let positionStore, let panel else { return }
        // Never persist transient mid-hop/mid-float/mid-drag frames; a quit
        // during motion restores the last grounded position instead.
        if controller?.isInTransientMotion == true { return }
        positionStore.saveOrigin(panel.frame.origin)
    }

    private func restoredPositionFrame(using store: PetPositionStore) -> CGRect {
        ScreenGeometry.restoredPositionFrame(
            savedOrigin: store.loadOrigin(),
            petSize: Self.petSize,
            visibleFrames: ScreenGeometry.screenVisibleFrames(),
            restoreMargin: 32,
            defaultVisibleFrame: FrameMath.currentScreenVisibleFrame()
        )
    }
}
