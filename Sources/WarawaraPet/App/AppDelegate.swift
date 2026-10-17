import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petWindowController: PetWindowController?
    private var statusItemController: StatusItemController?
    private var birthdayCoordinator: BirthdayEventCoordinator?
    private var birthdayPresenter: BirthdayPresenter?
    private var birthdayMonitorTimer: Timer?
    private var pendingReplayRequested = false
    private var pendingShowLetterRequested = false
    private var meteorController: MeteorEventController?
    private var meteorPresenter: MeteorEventPresenter?
    private var pendingMeteorReplay = false
    private var wearableController: WearableController?
    private var firstLaunchHandler: FirstLaunchCelebration?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load sprite assets BEFORE the first pet render so the
        // character view draws the artwork instead of the placeholder.
        // Failures are recorded and logged; the UI marks the fallback.
        WarawaraSpriteLoader.shared.loadDefaultResources()
        // The layered rig is the primary rendering direction; when
        // absent this logs clearly and the single-sprite pipeline runs.
        WarawaraRigLoader.shared.loadDefaultRig()
        // Final-gift artwork (wearables + meteor), verified lazily.
        GiftAssetStore.shared.verifyAllRequiredAssets()

        // The status item is created once and held strongly for the
        // lifetime of the app.
        statusItemController = StatusItemController()

        let controller = PetWindowController()
        controller.showPet()
        petWindowController = controller

        wireBirthdayEvent(windowController: controller)
        wireWearables(windowController: controller)
        wireMeteor(windowController: controller)
        wireFirstLaunchCelebration(windowController: controller)
    }

    /// Creates the birthday coordinator + presenter and starts the light
    /// monitoring tick (4 Hz logic-only; no polling of input devices).
    private func wireBirthdayEvent(windowController: PetWindowController) {
        let coordinator = BirthdayEventCoordinator(
            clock: SystemBirthdayClock(),
            persistence: BirthdayPersistence()
        )
        let presenter = BirthdayPresenter(
            windowController: windowController,
            coordinator: coordinator,
            store: .shared
        )
        coordinator.presenter = presenter
        coordinator.isPetBusy = { [weak windowController] in
            windowController?.isPetDragging ?? false
        }
        windowController.addGroupActiveObserver { [weak presenter] active in
            presenter?.groupActivityChanged(active)
        }
        windowController.setCompanionCentersObserver { [weak presenter] centers in
            presenter?.companionCentersChanged(centers)
        }
        windowController.setCompanionPanelsOrderedObserver { [weak presenter] in
            // Companions were just (re-)ordered front (fresh panels AND
            // pooled reuse): keep the carried props visually in front.
            presenter?.reassertLayering()
        }
        windowController.setCompanionAscentObserver { [weak presenter] in
            // Companions are leaving: the main pet gazes toward the exit.
            presenter?.companionAscentBegan()
        }
        windowController.onPetDoubleClick = { [weak presenter] in
            presenter?.openLetterForDoubleClick()
        }
        presenter.reassertPetVisibility = { [weak windowController, weak presenter] in
            // Closing the letter re-orders the main pet panel front; the
            // props must go back above it so the cake stays visible.
            windowController?.reassertPetVisibility()
            presenter?.reassertLayering()
        }

        birthdayCoordinator = coordinator
        birthdayPresenter = presenter
        presenter.setup()

        if pendingReplayRequested {
            coordinator.requestTrigger(.replay)
        }
        if pendingShowLetterRequested {
            presenter.openLetterForLaunchFlag()
        }

        birthdayMonitorTimer = Timer.scheduledTimer(
            withTimeInterval: 0.25,
            repeats: true
        ) { [weak self] _ in
            self?.birthdayTick()
        }
    }

    /// The birthday hat wearable (October 17 + first-launch surprise).
    private func wireWearables(windowController: PetWindowController) {
        let controller = WearableController(runtime: windowController.wearableRuntime)
        wearableController = controller
        controller.start()
    }

    /// The rare meteor event: independent world-space flight.
    private func wireMeteor(windowController: PetWindowController) {
        let controller = MeteorEventController(
            clock: SystemBirthdayClock(),
            persistence: MeteorPersistence()
        )
        let presenter = MeteorEventPresenter(
            windowController: windowController,
            controller: controller,
            store: .shared
        )
        controller.presenter = presenter
        controller.isPetBusy = { [weak windowController] in
            guard let windowController else { return false }
            return windowController.isPetDragging
                || windowController.isPetSleeping
                || LetterWindowController.isOpen
        }
        controller.isBirthdayBlocking = { [weak self] in
            guard let coordinator = self?.birthdayCoordinator else { return false }
            return coordinator.isRunning || coordinator.shouldTriggerAutomatically
        }
        controller.completionObservers.append { [weak self] trigger in
            guard EventDiagnostics.smokeMode, trigger == .replay else { return }
            exit(0)
        }
        meteorController = controller
        meteorPresenter = presenter
        if pendingMeteorReplay {
            controller.requestTrigger(.replay)
        }
    }

    /// Once-only first-launch birthday surprise (works even when the
    /// first launch is after October 17).
    private func wireFirstLaunchCelebration(windowController: PetWindowController) {
        guard let birthdayCoordinator else { return }
        let handler = FirstLaunchCelebration(
            coordinator: birthdayCoordinator,
            windowController: windowController,
            clock: SystemBirthdayClock()
        )
        handler.setCelebrationHat = { [weak self] active in
            self?.wearableController?.celebrationRequestsBirthdayHat = active
        }
        firstLaunchHandler = handler
        handler.start()
    }

    private func birthdayTick() {
        guard let coordinator = birthdayCoordinator else { return }
        coordinator.checkAutomaticTrigger()
        coordinator.servicePendingTrigger()
        coordinator.advance()
        meteorController?.tick()
        wearableController?.tick()
    }

    /// Called from the main entry point for --replay-meteor.
    func requestMeteorReplay() {
        if let controller = meteorController {
            controller.requestTrigger(.replay)
        } else {
            pendingMeteorReplay = true
        }
    }

    /// Called from the main entry point after argument parsing.
    func requestBirthdayReplay() {
        if let coordinator = birthdayCoordinator {
            coordinator.requestTrigger(.replay)
        } else {
            pendingReplayRequested = true
        }
    }

    /// Called from the main entry point for the --show-letter flag.
    func requestShowLetter() {
        if let presenter = birthdayPresenter {
            presenter.openLetterForLaunchFlag()
        } else {
            pendingShowLetterRequested = true
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // The pet is a nonactivating panel, not a regular window: closing
        // the letter window must NEVER terminate or hide the pet. Quit is
        // always explicit via the status item.
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        birthdayMonitorTimer?.invalidate()
        birthdayMonitorTimer = nil
        wearableController?.stop()
        meteorPresenter?.cleanup()
        petWindowController?.saveCurrentPosition()
    }
}
