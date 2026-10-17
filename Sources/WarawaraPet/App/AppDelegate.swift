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
    private var eventScheduler: EventScheduler?
    private var pendingSeasonalReplays: [SeasonalEventKind] = []
    private var pendingPropDebug: SeasonalEventKind?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load sprite assets BEFORE the first pet render so the
        // character view draws the artwork instead of the placeholder.
        // Failures are recorded and logged; the UI marks the fallback.
        WarawaraSpriteLoader.shared.loadDefaultResources()
        // The layered rig is the primary rendering direction; when
        // absent this logs clearly and the single-sprite pipeline runs.
        WarawaraRigLoader.shared.loadDefaultRig()

        // The status item is created once and held strongly for the
        // lifetime of the app.
        statusItemController = StatusItemController()

        let controller = PetWindowController()
        controller.showPet()
        petWindowController = controller

        wireBirthdayEvent(windowController: controller)
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

        wireSeasonalScheduler(windowController: windowController, birthdayCoordinator: coordinator)

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

    /// Creates the shared seasonal/daily scheduler. Priority: birthday
    /// (already wired) > CNY > Christmas > New Year > daily events.
    private func wireSeasonalScheduler(
        windowController: PetWindowController,
        birthdayCoordinator: BirthdayEventCoordinator
    ) {
        let scheduler = EventScheduler(
            clock: SystemBirthdayClock(),
            persistence: SeasonalPersistence()
        )
        scheduler.configure(windowController: windowController)
        scheduler.birthdayCoordinator = birthdayCoordinator
        scheduler.isPetBusy = { [weak windowController] in
            guard let windowController else { return false }
            return windowController.isPetDragging
                || windowController.isPetSleeping
                || LetterWindowController.isOpen
        }
        scheduler.isBirthdayBlocking = { [weak birthdayCoordinator] in
            guard let birthdayCoordinator else { return false }
            return birthdayCoordinator.isRunning || birthdayCoordinator.shouldTriggerAutomatically
        }
        if EventReplayLog.smokeMode {
            // CI smoke mode: exit as soon as the replayed scene completes.
            for coordinator in scheduler.coordinators.values {
                coordinator.completionObservers.append { kind, trigger in
                    guard trigger == .replay else { return }
                    EventReplayLog.completed(id: kind.replayArgument)
                    exit(0)
                }
            }
        }
        eventScheduler = scheduler
        for kind in pendingSeasonalReplays {
            scheduler.requestReplay(kind: kind)
        }
        pendingSeasonalReplays.removeAll()
        if let debugKind = pendingPropDebug {
            pendingPropDebug = nil
            // Developer static-layout diagnostic: pin the prop fully
            // opaque at its anchor and exit after the geometry dump.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak scheduler] in
                scheduler?.presenter(for: debugKind)?.presentStaticProp(kind: debugKind)
            }
        }
    }

    private func birthdayTick() {
        guard let coordinator = birthdayCoordinator else { return }
        coordinator.checkAutomaticTrigger()
        coordinator.servicePendingTrigger()
        coordinator.advance()
        eventScheduler?.tick()
    }

    /// Called from the main entry point for --replay-event <kind>.
    func requestSeasonalReplay(kind: SeasonalEventKind) {
        if let scheduler = eventScheduler {
            scheduler.requestReplay(kind: kind)
        } else {
            EventReplayLog.ready(id: kind.replayArgument)
            pendingSeasonalReplays.append(kind)
        }
    }

    /// Developer-only static layout diagnostic (--prop-debug <kind>).
    func requestPropDebug(kind: SeasonalEventKind) {
        pendingPropDebug = kind
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
        petWindowController?.saveCurrentPosition()
    }
}
