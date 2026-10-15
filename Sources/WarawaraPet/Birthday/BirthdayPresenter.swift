import AppKit
import SwiftUI

/// Production realization of the birthday event UI: transparent prop
/// panels positioned around the MAIN PET window (never replacing it),
/// companion grouping via the existing Phase 3 infrastructure, and the
/// activatable letter window. All decorative panels are pooled-created
/// once and kept for the app lifetime.
final class BirthdayPresenter: BirthdayEventPresenting {
    private weak var windowController: PetWindowController?
    private weak var coordinator: BirthdayEventCoordinator?
    private let store: BirthdayAssetStore

    private var cakePanel: BirthdayPropPanel?
    private var envelopePanel: BirthdayPropPanel?
    private var letterWindowController: LetterWindowController?
    private var positionTimer: Timer?
    private var envelopeWasShown = false

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
    }

    /// Called once at startup: shows the persistent envelope when it is
    /// already unlocked (or it is the birthday today).
    func setup() {
        if coordinator?.shouldShowEnvelope == true {
            showEnvelope(animated: false)
        }
    }

    // MARK: - BirthdayEventPresenting

    func presentCake() {
        ensureCakePanel()
        guard let cakePanel else { return }
        cakePanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 1.4
            cakePanel.animator().alphaValue = 1
        }
        positionPanels()
        startPositionTimerIfNeeded()
    }

    func hideCake() {
        guard let cakePanel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.8
            cakePanel.animator().alphaValue = 0
        }
    }

    func presentSparkles() {
        // Sparkles are part of the cake content and twinkle on their own;
        // nothing additional is required here.
    }

    func hideSparkles() {
        // Handled by hideCake (same panel).
    }

    func presentEnvelope() {
        showEnvelope(animated: true)
    }

    func hideEnvelope() {
        guard let envelopePanel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.6
            envelopePanel.animator().alphaValue = 0
        }
        envelopeWasShown = false
        stopPositionTimerIfIdle()
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
        envelopeWasShown = true
    }

    // MARK: - Group lifecycle forwarding

    /// Called by the app wiring: forwards group activity to the
    /// coordinator so the event phases stay in sync with Phase 3.
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
        let panel = BirthdayPropPanel(size: envelopePanelSize, interactive: true)
        let view = EnvelopePropView(
            store: store,
            envelopeSize: envelopeSize,
            onOpenLetter: { [weak self] in self?.showLetterWindow() }
        )
        let hosting = BirthdayPropHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: envelopePanelSize)
        panel.contentView = hosting
        panel.alphaValue = 0
        envelopePanel = panel
    }

    private func showEnvelope(animated: Bool) {
        ensureEnvelopePanel()
        guard let envelopePanel else { return }
        envelopePanel.orderFrontRegardless()
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 1.6
                envelopePanel.animator().alphaValue = 1
            }
        } else {
            envelopePanel.alphaValue = 1
        }
        envelopeWasShown = true
        positionPanels()
        startPositionTimerIfNeeded()
    }

    // MARK: - Letter window

    private func showLetterWindow() {
        if letterWindowController == nil {
            letterWindowController = LetterWindowController(store: store)
        }
        letterWindowController?.showLetter()
    }

    /// Opens the letter directly (--show-letter launch flag); creates
    /// the envelope in its unlocked state as well.
    func openLetterForLaunchFlag() {
        showEnvelope(animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.showLetterWindow()
        }
    }

    // MARK: - Positioning

    private func positionPanels() {
        guard let petFrame = windowController?.currentFrame, petFrame != .zero else { return }
        let visible = ScreenGeometry.visibleFrame(for: petFrame)

        if let cakePanel, cakePanel.alphaValue > 0.01 {
            var origin = CGPoint(
                x: petFrame.midX - cakePanelSize.width / 2,
                y: petFrame.maxY - 26
            )
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - cakePanelSize.width - 4)
            origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - cakePanelSize.height - 4)
            cakePanel.setFrameOrigin(origin)
        }

        if let envelopePanel, envelopePanel.alphaValue > 0.01 {
            var origin = CGPoint(
                x: petFrame.maxX + 8,
                y: petFrame.minY + 18
            )
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - envelopePanelSize.width - 4)
            origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - envelopePanelSize.height - 4)
            envelopePanel.setFrameOrigin(origin)
        }
    }

    private func startPositionTimerIfNeeded() {
        guard positionTimer == nil else { return }
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.positionPanels()
        }
    }

    private func stopPositionTimerIfIdle() {
        let anyVisible = (cakePanel?.alphaValue ?? 0) > 0.01 || (envelopePanel?.alphaValue ?? 0) > 0.01
        guard !anyVisible else { return }
        positionTimer?.invalidate()
        positionTimer = nil
    }
}
