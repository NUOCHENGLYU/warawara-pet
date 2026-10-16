import AppKit
import SwiftUI

/// Production realization of the birthday event UI. Props arrive WITH
/// explicit carrier companions (attached to live carrier anchors),
/// are delivered to a stable front-of-pet desktop layout, and then STAY
/// there. After the first read the envelope retires gently and letter
/// access continues via double-clicking the main pet.
final class BirthdayPresenter: BirthdayEventPresenting {
    private weak var windowController: PetWindowController?
    private weak var coordinator: BirthdayEventCoordinator?
    private let store: BirthdayAssetStore
    private let persistence: BirthdayPersistence

    /// Injected by the app wiring (testable): re-asserts the main pet
    /// panel's visibility after the letter window closes.
    var reassertPetVisibility: (() -> Void)?

    private var cakePanel: BirthdayPropPanel?
    private var envelopePanel: BirthdayPropPanel?
    private var letterWindowController: LetterWindowController?

    private var attached = false
    /// True once the props were delivered to the front layout (internal
    /// so tests can exercise the post-delivery lifecycle directly).
    var delivered = false
    private var envelopeActive = false
    private(set) var letterReadCount = 0
    private(set) var letterPresentedCount = 0
    private(set) var envelopeRetiredThisSession = false
    private var lastAttentionDirection: CGVector?

    private let cakePanelSize = CGSize(width: 200, height: 230)
    private let envelopePanelSize = CGSize(width: 100, height: 100)
    private let cakeSize: CGFloat = 85
    private let envelopeSize: CGFloat = 62

    /// Optional carry-helper artwork (e.g. a tray or paper band). Nil
    /// until the v4 art package supplies them — no logic changes then.
    private var cakeCarryHelper: NSImage? { store.optionalImage(named: "carry_tray.png") }
    private var envelopeCarryHelper: NSImage? { store.optionalImage(named: "envelope_band.png") }

    init(
        windowController: PetWindowController,
        coordinator: BirthdayEventCoordinator,
        store: BirthdayAssetStore = .shared,
        persistence: BirthdayPersistence = BirthdayPersistence()
    ) {
        self.windowController = windowController
        self.coordinator = coordinator
        self.store = store
        self.persistence = persistence
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

    /// Called once at startup: shows the delivered envelope when it is
    /// still part of the current gift (unlocked but not yet retired).
    func setup() {
        guard let coordinator else { return }
        if coordinator.shouldShowEnvelope, !persistence.envelopeRetired {
            showEnvelopeDelivered(animated: false)
        }
    }

    // MARK: - BirthdayEventPresenting

    func noticeCompanionsArriving() {
        // Until the group starts there is no live carrier position yet:
        // aim down-left where the companions will enter.
        windowController?.setEventAttention(CGVector(dx: -0.5, dy: -0.18))
    }

    func clearAttention() {
        lastAttentionDirection = nil
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
        // The pet now looks at the delivered cake.
        aimAttention(at: CGPoint(
            x: origins.cake.x + cakePanelSize.width / 2,
            y: origins.cake.y + cakePanelSize.height / 2
        ))
    }

    func activateEnvelope() {
        envelopeActive = true
        envelopePanel?.ignoresMouseEvents = false
        // Attend the envelope briefly, then release.
        if let envelopePanel,
           let petFrame = windowController?.currentFrame, petFrame != .zero {
            aimAttention(at: CGPoint(
                x: envelopePanel.frame.midX,
                y: envelopePanel.frame.midY
            ))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.clearAttention()
        }
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

    // MARK: - Attention targeting

    private func aimAttention(at target: CGPoint) {
        guard let petFrame = windowController?.currentFrame, petFrame != .zero else { return }
        let direction = EventAttentionMath.direction(
            from: CGPoint(x: petFrame.midX, y: petFrame.midY),
            to: target
        )
        guard direction != .zero else { return }
        if let last = lastAttentionDirection, !EventAttentionMath.differs(last, direction) {
            return
        }
        lastAttentionDirection = direction
        windowController?.setEventAttention(direction)
    }

    // MARK: - Companion carrying

    /// Called by the app wiring with live companion centers. While the
    /// props are attached they ride with their carriers, and the pet's
    /// attention follows the LEAD carrier.
    func companionCentersChanged(_ centers: [Int: CGPoint]) {
        guard let coordinator else { return }
        if let lead = centers[0],
           coordinator.attentionTarget == .leadCompanion {
            aimAttention(at: lead)
        }
        guard attached, !delivered else { return }
        if let carrier = centers[0], let cakePanel {
            cakePanel.setFrameOrigin(CGPoint(
                x: carrier.x - cakePanelSize.width / 2,
                y: carrier.y - 4
            ))
        }
        if let carrier = centers[1], let envelopePanel {
            envelopePanel.setFrameOrigin(CGPoint(
                x: carrier.x + 26 - envelopePanelSize.width / 2,
                y: carrier.y + 10
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
        let view = CakePropView(store: store, cakeSize: cakeSize, carryHelper: cakeCarryHelper)
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
            carryHelper: envelopeCarryHelper,
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
        envelopeRetiredThisSession = false
    }

    /// Gently retires the large desktop envelope after the first read.
    /// Letter access continues via pet double-click.
    private func retireEnvelope() {
        guard !envelopeRetiredThisSession else { return }
        envelopeRetiredThisSession = true
        envelopeActive = false
        persistence.markEnvelopeRetired()
        guard let envelopePanel else { return }
        envelopePanel.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 1.0
            envelopePanel.animator().alphaValue = 0
        }
    }

    // MARK: - Letter window

    private func showLetterWindow() {
        letterPresentedCount += 1
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

    /// Double-clicking the main pet reopens the letter (the persistent
    /// access path after the envelope has retired).
    func openLetterForDoubleClick() {
        guard persistence.isLetterAvailable || coordinator?.isBirthdayToday == true else { return }
        showLetterWindow()
    }

    /// The letter window closed: re-assert the pet panel and, after the
    /// FIRST completed read, retire the large envelope.
    @objc private func letterDidClose() {
        reassertPetVisibility?()
        guard delivered else { return }
        letterReadCount += 1
        retireEnvelope()
    }
}
