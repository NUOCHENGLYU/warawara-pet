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

    /// Panel factory (test injection): spy subclasses observe the real
    /// layering contract without changing production behavior.
    var makePropPanel: ((CGSize, Bool) -> BirthdayPropPanel)?

    private var cakePanel: BirthdayPropPanel?
    private var envelopePanel: BirthdayPropPanel?
    private var letterWindowController: LetterWindowController?

    private var attached = false
    /// True once the props were delivered to the front layout (internal
    /// so tests can exercise the post-delivery lifecycle directly).
    var delivered = false
    private var envelopeActive = false
    /// True after the prop panels were re-ordered ABOVE the companion
    /// panels (regression flag: the cake must render in FRONT of its
    /// carrier companion).
    private(set) var propsRaisedAboveCompanions = false
    /// Number of full layering re-asserts (tests verify the invariant is
    /// maintained, not applied only once).
    private(set) var layeringReassertCount = 0
    private(set) var letterReadCount = 0
    private(set) var letterPresentedCount = 0
    private(set) var envelopeRetiredThisSession = false
    private var lastAttentionDirection: CGVector?

    private let cakePanelSize = CGSize(width: 200, height: 230)
    private let envelopePanelSize = CGSize(width: 100, height: 100)
    private let cakeSize: CGFloat = 85
    private let envelopeSize: CGFloat = 62

    /// Optional carry-helper artwork. The v5 wooden tray is integrated;
    /// the envelope band slot stays nil until art exists.
    private var cakeCarryHelper: NSImage? { store.optionalImage(named: "cake_tray.png") }
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
        // The delivered desktop layout is the final accepted state:
        // re-assert the props in front of anything that may have been
        // ordered above them during delivery.
        reassertLayering()
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
            raisePropsAboveCompanions()
            coordinator?.companionGroupDidStart()
        } else {
            coordinator?.companionGroupDidEnd()
        }
    }

    /// The companion panels are ordered front when the group starts
    /// (AFTER the props were first shown), which would put the carrier
    /// body ON TOP of the carried cake. Re-order the prop panels above
    /// the companions so the cake/tray/envelope render in FRONT of the
    /// carrier silhouette. The companion-ordering observer re-asserts
    /// this AFTER every preparePanels() ordering pass.
    private func raisePropsAboveCompanions() {
        reassertLayering()
        propsRaisedAboveCompanions = true
    }

    /// Central birthday-window layering invariant: the carried/delivered
    /// props must always be visually in front of the pet and companion
    /// panels. Idempotent; called whenever companions are shown/reused/
    /// reordered, after delivery, and after the letter closes (which
    /// re-orders the main pet panel).
    func reassertLayering() {
        layeringReassertCount += 1
        cakePanel?.orderFrontRegardless()
        envelopePanel?.orderFrontRegardless()
        EventReplayLog.birthdayLayering(
            cakeWindow: cakePanel?.windowNumber,
            envelopeWindow: envelopePanel?.windowNumber
        )
    }

    // MARK: - Panels

    private func ensureCakePanel() {
        guard cakePanel == nil else { return }
        let panel = makePropPanel?(cakePanelSize, false)
            ?? BirthdayPropPanel(size: cakePanelSize, interactive: false)
        let view = CakePropView(store: store, cakeSize: cakeSize, carryHelper: cakeCarryHelper)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: cakePanelSize)
        panel.contentView = hosting
        panel.alphaValue = 0
        cakePanel = panel
    }

    private func ensureEnvelopePanel() {
        guard envelopePanel == nil else { return }
        let panel = makePropPanel?(envelopePanelSize, false)
            ?? BirthdayPropPanel(size: envelopePanelSize, interactive: false)
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
