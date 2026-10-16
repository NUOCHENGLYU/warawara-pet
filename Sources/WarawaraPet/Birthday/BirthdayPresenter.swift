import AppKit
import SwiftUI

/// Production realization of the birthday event UI: props arrive WITH
/// the companions (carried), are delivered to a stable front-of-pet
/// desktop layout, and then STAY there. The envelope is a stationary,
/// independently clickable desktop object — it never follows pet hop /
/// float motion and never flickers.
final class BirthdayPresenter: BirthdayEventPresenting {
    private weak var windowController: PetWindowController?
    private weak var coordinator: BirthdayEventCoordinator?
    private let store: BirthdayAssetStore

    /// Injected by the app wiring (testable): re-asserts the main pet
    /// panel's visibility after the letter window closes.
    var reassertPetVisibility: (() -> Void)?

    private var cakePanel: BirthdayPropPanel?
    private var envelopePanel: BirthdayPropPanel?
    private var letterWindowController: LetterWindowController?

    private var attached = false
    private var delivered = false
    private var envelopeActive = false

    private let cakePanelSize = CGSize(width: 200, height: 230)
    private let envelopePanelSize = CGSize(width: 100, height: 100)
    private let cakeSize: CGFloat = 85
    private let envelopeSize: CGFloat = 62

    init(
        windowController: PetWindowController,
        coordinator: BirthdayEventCoordinator,
        store: BirthdayAssetStore = .shared
    ) {
        self.windowController = windowController
        self.coordinator = coordinator
        self.store = store
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(letterDidClose),
            name: .birthdayLetterDidClose,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Called once at startup: shows the persistent envelope when it is
    /// already unlocked (or it is the birthday today).
    func setup() {
        if coordinator?.shouldShowEnvelope == true {
            showEnvelopeDelivered(animated: false)
        }
    }

    // MARK: - BirthdayEventPresenting

    func noticeCompanionsArriving() {
        // The pet turns to look down-left where the companions will enter.
        windowController?.setEventAttention(CGVector(dx: -0.5, dy: -0.18))
    }

    func clearAttention() {
        windowController?.setEventAttention(nil)
    }

    func presentCarriedProps() {
        ensureCakePanel()
        ensureEnvelopePanel()
        attached = true
        delivered = false
        guard let cakePanel, let envelopePanel else { return }
        cakePanel.alphaValue = 0
        envelopePanel.alphaValue = 0
        cakePanel.orderFrontRegardless()
        envelopePanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 1.2
            cakePanel.animator().alphaValue = 1
            envelopePanel.animator().alphaValue = 1
        }
    }

    func deliverPropsToPet() {
        guard let cakePanel, let envelopePanel,
              let petFrame = windowController?.currentFrame, petFrame != .zero else { return }
        attached = false
        delivered = true
        let visible = ScreenGeometry.visibleFrame(for: petFrame)
        let origins = BirthdayPropLayout.deliveryOrigins(
            petFrame: petFrame,
            cakePanelSize: cakePanelSize,
            envelopePanelSize: envelopePanelSize,
            visibleFrame: visible
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 1.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cakePanel.animator().setFrameOrigin(origins.cake)
            envelopePanel.animator().setFrameOrigin(origins.envelope)
        }
    }

    func activateEnvelope() {
        envelopeActive = true
        envelopePanel?.ignoresMouseEvents = false
    }

    func hideCake() {
        guard let cakePanel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 1.4
            cakePanel.animator().alphaValue = 0
        }
    }

    func startCompanionGroup() {
        windowController?.startCompanionGroupSequence()
    }

    func cancelCompanionGroup() {
        windowController?.cancelCompanionGroupSequence()
    }

    func performMainPetHop() {
        windowController?.performBirthdayHop()
    }

    func envelopeDidBecomeAvailable() {
        // Persistence was already written by the coordinator.
    }

    // MARK: - Companion carrying

    /// Called by the app wiring with live companion centers; while the
    /// props are attached they ride with their carriers.
    func companionCentersChanged(_ centers: [Int: CGPoint]) {
        guard attached, !delivered else { return }
        if let carrier = centers[0], let cakePanel {
            cakePanel.setFrameOrigin(CGPoint(
                x: carrier.x - cakePanelSize.width / 2,
                y: carrier.y - cakePanelSize.height * 0.82
            ))
        }
        if let carrier = centers[1], let envelopePanel {
            envelopePanel.setFrameOrigin(CGPoint(
                x: carrier.x - envelopePanelSize.width / 2 + 30,
                y: carrier.y - envelopePanelSize.height * 0.7
            ))
        }
    }

    /// Called by the app wiring when the group sequence ends.
    func groupActivityChanged(_ active: Bool) {
        if active {
            coordinator?.companionGroupDidStart()
        } else {
            coordinator?.companionGroupDidEnd()
        }
    }

    // MARK: - Panels

    private func ensureCakePanel() {
        guard cakePanel == nil else { return }
        let panel = BirthdayPropPanel(size: cakePanelSize, interactive: false)
        let view = CakePropView(store: store, cakeSize: cakeSize)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: cakePanelSize)
        panel.contentView = hosting
        panel.alphaValue = 0
        cakePanel = panel
    }

    private func ensureEnvelopePanel() {
        guard envelopePanel == nil else { return }
        let panel = BirthdayPropPanel(size: envelopePanelSize, interactive: false)
        let view = EnvelopePropView(
            store: store,
            envelopeSize: envelopeSize,
            onOpenLetter: { [weak self] in self?.showLetterWindow() }
        )
        let hosting = BirthdayPropHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: envelopePanelSize)
        panel.contentView = hosting
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        envelopePanel = panel
    }

    private func showEnvelopeDelivered(animated: Bool) {
        ensureEnvelopePanel()
        guard let envelopePanel,
              let petFrame = windowController?.currentFrame, petFrame != .zero else { return }
        let visible = ScreenGeometry.visibleFrame(for: petFrame)
        let origin = BirthdayPropLayout.envelopeOrigin(
            petFrame: petFrame, panelSize: envelopePanelSize
        )
        envelopePanel.setFrameOrigin(
            BirthdayPropLayout.clamped(origin, panelSize: envelopePanelSize, visibleFrame: visible)
        )
        envelopePanel.orderFrontRegardless()
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 1.6
                envelopePanel.animator().alphaValue = 1
            }
        } else {
            envelopePanel.alphaValue = 1
        }
        envelopePanel.ignoresMouseEvents = false
        envelopeActive = true
        delivered = true
    }

    // MARK: - Letter window

    private func showLetterWindow() {
        if letterWindowController == nil {
            letterWindowController = LetterWindowController(store: store)
        }
        letterWindowController?.showLetter()
    }

    func openLetterForLaunchFlag() {
        showEnvelopeDelivered(animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.showLetterWindow()
        }
    }

    /// The letter window closed: the pet must stay visible and the
    /// envelope must stay accessible. Nothing else changes.
    @objc private func letterDidClose() {
        reassertPetVisibility?()
        // The envelope re-closes visually (handled by EnvelopePropView)
        // and remains in place for the next read.
    }
}
