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
    private var positionStore: PetPositionStore?
    private var screenObserver: NSObjectProtocol?
    private var groupSequenceController: GroupSequenceController?
    private var groupActiveObservers: [(Bool) -> Void] = []

    var currentFrame: CGRect {
        panel?.frame ?? .zero
    }

    /// True while the user is actively dragging the main pet (birthday
    /// triggering is deferred while this is true).
    var isPetDragging: Bool {
        controller?.state == .dragged
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

    /// Event-driven attention: the pet turns to look at a specific
    /// direction (birthday choreography).
    func setEventAttention(_ direction: CGVector?) {
        controller?.setEventAttention(direction)
    }

    /// Companion center positions observer (birthday props ride along
    /// with carrier companions during delivery).
    func setCompanionCentersObserver(_ observer: @escaping ([Int: CGPoint]) -> Void) {
        groupSequenceController?.onCompanionCenters = observer
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
            self.setWindowFrame(frame, animated: false)
        }

        petController.startAutonomousBehavior()
        wireGroupSequence()
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
