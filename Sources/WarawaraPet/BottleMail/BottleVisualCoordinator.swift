import AppKit
import Combine
import Foundation

/// The pet's bottle form: an independent VISUAL state machine that
/// composes with (never replaces) the established `PetState` machine.
///
/// Responsibilities:
/// - drive the continuous, reversible morph parameter (0 = Warawara,
///   1 = bottle) from wall time + an easing curve;
/// - decide when the morph may start (busy conflicts delay it);
/// - acknowledge deliveries exactly once when the presentation
///   animation completes;
/// - manage the reading lifecycle (open/close/put-away) and revert to
///   the normal form when the last unread letter is put away.
enum BottleVisualState: Equatable {
    /// Original Warawara form.
    case normal
    /// Continuous morph toward the bottle (morphProgress 0 -> 1).
    case transformingToBottle
    /// Fully presented bottle, waiting for interaction.
    case bottleIdle
    /// Cork lifts, the paper scroll emerges (short, timed).
    case bottleOpening
    /// The reading window is open.
    case reading
    /// Continuous morph back to Warawara (morphProgress 1 -> 0).
    case transformingBack
    /// A busy conflict (sleep/drag/birthday/meteor/group) delays or
    /// freezes the morph; progress is preserved and resumes later.
    case suspended

    /// True while any part of the bottle presentation is visible.
    var isBottleForm: Bool {
        switch self {
        case .normal: return false
        case .transformingToBottle, .bottleIdle, .bottleOpening,
             .reading, .transformingBack: return true
        case .suspended: return false
        }
    }
}

/// Pure morph math: one reversible parameter, time + easing driven.
/// Reversing direction NEVER jumps the value — the new start date is
/// derived from the current progress.
enum BottleMorphMath {
    enum Direction: Equatable {
        case toBottle
        case toNormal
    }

    /// Smoothstep easing: slow start/stop, linear middle.
    static func eased(_ linear: Double) -> Double {
        let t = min(max(linear, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Raw (uneased) progress 0...1 for the given direction and time.
    static func rawProgress(
        at now: Date,
        startedAt: Date,
        direction: Direction,
        duration: TimeInterval
    ) -> Double {
        guard duration > 0 else { return direction == .toBottle ? 1 : 0 }
        let elapsed = now.timeIntervalSince(startedAt)
        let linear = min(max(elapsed / duration, 0), 1)
        return direction == .toBottle ? linear : 1 - linear
    }

    /// A start date such that `rawProgress(at: now, ...)` == `progress`
    /// — reversal continuity, never a visual jump.
    static func startDate(
        forCurrentProgress progress: Double,
        at now: Date,
        direction: Direction,
        duration: TimeInterval
    ) -> Date {
        let clamped = min(max(progress, 0), 1)
        let fraction = direction == .toBottle ? clamped : 1 - clamped
        return now.addingTimeInterval(-fraction * max(duration, 0.001))
    }
}

/// Lightweight bridge between the pet window (created first, before
/// Bottle Mail wiring) and the visual coordinator (created later by
/// AppDelegate). PetView observes the provider; once the coordinator is
/// attached, the provider relays its objectWillChange so every morph
/// tick re-renders the pet.
final class BottleVisualProvider: ObservableObject {
    @Published var coordinator: BottleVisualCoordinator?
    private var relay: AnyCancellable?

    func attach(_ coordinator: BottleVisualCoordinator) {
        self.coordinator = coordinator
        relay?.cancel()
        relay = coordinator.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
}

/// Drives the bottle visual state machine on the MAIN thread (all
/// published state, callbacks and busy checks are main-thread only).
/// The mailbox coordinator publishes letters/unread/deliveries on main,
/// so Combine subscriptions receive everything here without hops.
final class BottleVisualCoordinator: ObservableObject {
    // MARK: - Published (main thread)

    @Published private(set) var visualState: BottleVisualState = .normal
    /// Timeline position 0...1 over the poof transition (raw piecewise
    /// time; the choreography's easing lives inside BottlePoofTimeline).
    @Published private(set) var morphProgress: Double = 0
    /// Which form is visible: 0 = Warawara, 1 = bottle. A hard step at
    /// the timeline's switch point — the swap is hidden behind full
    /// occlusion smoke, so the step is never seen.
    @Published private(set) var formProgress: Double = 0
    /// Cork lift + paper unfold amount 0...1 (during .bottleOpening and
    /// held at 1 while .reading).
    @Published private(set) var openingProgress: Double = 0
    /// The letter the reading window should present (nil = none).
    @Published private(set) var readingLetterID: String?

    // MARK: - Dependencies

    let mailbox: BottleMailCoordinator
    /// Conflict gate (sleep/drag/birthday/meteor/letter/group),
    /// evaluated on the MAIN thread.
    var isPetBusy: () -> Bool = { false }
    /// macOS "Reduce Motion" — disables decorative sway only; the morph
    /// itself is core state and still plays.
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var nowProvider: () -> Date = { Date() }
    var morphDuration: TimeInterval = BottlePoofTimeline.duration
    var openingDuration: TimeInterval = 0.4
    var tickInterval: TimeInterval = 1.0 / 30.0

    /// Fired once per transition at the poof instant (0.43 s) — the app
    /// layer plays the one-shot soft sound. Fires for BOTH directions
    /// (forward and back), exactly once each.
    var onPoofMoment: (() -> Void)?

    /// Fired once per presentation batch with the delivery ids whose
    /// animation completed — the app layer ACKs them (persisted exactly
    /// once). Also fired immediately for arrivals while already in
    /// bottle form (the standing bottle presents them).
    var onPresented: (([String]) -> Void)?
    /// The opening animation finished: show the reading window for
    /// this letter id.
    var onOpenReadingRequested: ((String) -> Void)?
    /// The last unread letter was put away: close the reading window.
    var onReadingFinished: (() -> Void)?

    // MARK: - Internals

    private var cancellables: Set<AnyCancellable> = []
    private var timer: Timer?
    private var rawProgress: Double = 0
    private var direction: BottleMorphMath.Direction = .toBottle
    private var morphStartedAt = Date.distantPast
    private var openingStartedAt: Date?
    private var frozenOpeningElapsed: TimeInterval?
    private var suspendedFrom: BottleVisualState = .transformingToBottle
    private var knownDeliveryIDs: Set<String> = []
    private var pendingPresentationACKs: [String] = []
    private var lastUnread = 0
    private var started = false
    /// The one-shot poof sound per morph run (forward AND back each
    /// fire once).
    private var poofFired = false

    init(mailbox: BottleMailCoordinator) {
        self.mailbox = mailbox
    }

    // MARK: - Lifecycle

    /// Subscribes to the mailbox and evaluates the initial state.
    /// `usingTimer: false` lets tests drive time via `advance(now:)`.
    func start(usingTimer: Bool = true) {
        guard !started else { return }
        started = true
        lastUnread = mailbox.unreadCount
        knownDeliveryIDs = Set(mailbox.deliveryQueue.map(\.id))
        mailbox.$unreadCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] unread in
                guard let self else { return }
                self.lastUnread = unread
                self.evaluate(now: self.nowProvider())
            }
            .store(in: &cancellables)
        mailbox.$deliveryQueue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] queue in
                guard let self else { return }
                self.deliveriesChanged(queue)
                self.evaluate(now: self.nowProvider())
            }
            .store(in: &cancellables)
        evaluate(now: nowProvider())
        updateTimerIfNeeded(usingTimer: usingTimer)
    }

    /// Stops the drive timer (test hygiene / app teardown).
    func stop() {
        timer?.invalidate()
        timer = nil
        cancellables.removeAll()
    }

    // MARK: - External events (main thread)

    /// A single click on the bottle: open the letter (bottleIdle), or
    /// re-front the reading window while reading. Returns true when the
    /// click was consumed — the click squash is skipped.
    func handleBottleTap() -> Bool {
        switch visualState {
        case .bottleIdle:
            openingStartedAt = nowProvider()
            openingProgress = 0
            visualState = .bottleOpening
            updateTimerIfNeeded()
            return true
        case .reading:
            onOpenReadingRequested?(readingLetterID ?? "")
            return true
        default:
            return false
        }
    }

    /// The reading window's explicit "put away" action: completes the
    /// read LOCALLY (server reconciliation stays async) and advances to
    /// the next unread letter — or finishes when none remain.
    func letterPutAway(id: String) {
        guard visualState == .reading else { return }
        mailbox.markOpened(letterID: id)
        let next = mailbox.letters
            .filter { $0.isUnread && $0.id != id }
            .sorted { $0.seq < $1.seq }
            .first
        readingLetterID = next?.id
    }

    /// The user closed the reading window without explicitly finishing
    /// the letter: the letter stays unread, the bottle stays.
    func readingWindowClosed() {
        guard visualState == .reading else { return }
        readingLetterID = nil
        if lastUnread == 0 {
            // Everything was already put away (window closed right at
            // the end): run the normal finish flow.
            evaluate(now: nowProvider())
        } else {
            visualState = .bottleIdle
            updateTimerIfNeeded()
        }
    }

    // MARK: - Evaluation

    /// Advances time-derived values and applies state transitions.
    /// Called by the timer and by every mailbox event. Idempotent.
    func advance(now: Date) {
        evaluate(now: now)
    }

    private func evaluate(now: Date) {
        let unread = lastUnread
        let busy = isPetBusy()

        switch visualState {
        case .normal:
            if unread > 0 {
                if busy {
                    visualState = .suspended
                } else {
                    beginMorph(direction: .toBottle, at: now)
                }
            }
        case .suspended:
            if busy { break }
            if unread > 0 {
                if suspendedFrom == .bottleOpening {
                    resumeOpening(at: now)
                } else {
                    resumeMorph(at: now)
                }
            } else {
                visualState = .normal
                updateTimerIfNeeded()
            }
        case .transformingToBottle:
            if busy {
                freezeMorph()
                break
            }
            rawProgress = BottleMorphMath.rawProgress(
                at: now, startedAt: morphStartedAt,
                direction: .toBottle, duration: morphDuration
            )
            if unread == 0 {
                // Everything was read mid-morph: reverse from here.
                beginMorph(direction: .toNormal, at: now)
                break
            }
            if rawProgress >= 1 {
                rawProgress = 1
                visualState = .bottleIdle
                acknowledgePresented()
                updateTimerIfNeeded()
            }
        case .transformingBack:
            if busy {
                freezeMorph()
                break
            }
            rawProgress = BottleMorphMath.rawProgress(
                at: now, startedAt: morphStartedAt,
                direction: .toNormal, duration: morphDuration
            )
            if unread > 0 {
                // New mail mid-reverse: turn around continuously.
                beginMorph(direction: .toBottle, at: now)
                break
            }
            if rawProgress <= 0 {
                rawProgress = 0
                visualState = .normal
                updateTimerIfNeeded()
            }
        case .bottleIdle:
            if unread == 0 && !busy {
                beginMorph(direction: .toNormal, at: now)
            }
        case .bottleOpening:
            if busy {
                // Pause the opening: remember how far it had progressed.
                frozenOpeningElapsed = openingStartedAt.map { now.timeIntervalSince($0) }
                freezeMorph()
                break
            }
            guard let startedAt = openingStartedAt else {
                openingStartedAt = now
                break
            }
            let elapsed = now.timeIntervalSince(startedAt)
            openingProgress = openingDuration > 0
                ? min(elapsed / openingDuration, 1)
                : 1
            if openingProgress >= 1 {
                readingLetterID = mailbox.letters
                    .filter(\.isUnread)
                    .sorted { $0.seq < $1.seq }
                    .first?.id
                visualState = .reading
                updateTimerIfNeeded()
                if let id = readingLetterID {
                    onOpenReadingRequested?(id)
                }
            }
        case .reading:
            if unread == 0 {
                // Last letter put away: finish (the window closes via
                // onReadingFinished) and revert when the pet is free.
                readingLetterID = nil
                onReadingFinished?()
                if busy {
                    visualState = .bottleIdle
                    updateTimerIfNeeded()
                } else {
                    beginMorph(direction: .toNormal, at: now)
                }
            }
        }

        // Publish the timeline + the hidden form step. The form only
        // flips at the timeline's switch point, where the occlusion
        // smoke is fully opaque (BottlePoofTimeline invariant).
        let timeline = min(max(rawProgress, 0), 1)
        morphProgress = timeline
        formProgress = BottlePoofTimeline.formProgress(at: timeline)
        if !poofFired {
            let crossed: Bool
            switch direction {
            case .toBottle: crossed = timeline >= BottlePoofTimeline.poofPoint
            case .toNormal: crossed = timeline <= BottlePoofTimeline.poofPoint
            }
            if crossed {
                poofFired = true
                onPoofMoment?()
            }
        }
    }

    // MARK: - Morph bookkeeping

    private func beginMorph(direction newDirection: BottleMorphMath.Direction, at now: Date) {
        direction = newDirection
        poofFired = false
        morphStartedAt = BottleMorphMath.startDate(
            forCurrentProgress: rawProgress,
            at: now,
            direction: newDirection,
            duration: morphDuration
        )
        visualState = newDirection == .toBottle ? .transformingToBottle : .transformingBack
        updateTimerIfNeeded()
    }

    private func resumeMorph(at now: Date) {
        morphStartedAt = BottleMorphMath.startDate(
            forCurrentProgress: rawProgress,
            at: now,
            direction: direction,
            duration: morphDuration
        )
        visualState = direction == .toBottle ? .transformingToBottle : .transformingBack
        updateTimerIfNeeded()
    }

    private func resumeOpening(at now: Date) {
        openingStartedAt = now.addingTimeInterval(-(frozenOpeningElapsed ?? 0))
        frozenOpeningElapsed = nil
        visualState = .bottleOpening
        updateTimerIfNeeded()
    }

    private func freezeMorph() {
        suspendedFrom = visualState
        visualState = .suspended
        updateTimerIfNeeded()
    }

    private func deliveriesChanged(_ queue: [PendingBottleDelivery]) {
        let ids = Set(queue.map(\.id))
        let newIDs = ids.subtracting(knownDeliveryIDs)
        knownDeliveryIDs = ids
        guard !newIDs.isEmpty else { return }
        pendingPresentationACKs.append(contentsOf: newIDs.sorted())
        // Arrivals while the bottle is already standing are presented
        // immediately by the bottle itself.
        switch visualState {
        case .bottleIdle, .bottleOpening, .reading:
            acknowledgePresented()
        default:
            break
        }
    }

    private func acknowledgePresented() {
        guard !pendingPresentationACKs.isEmpty else { return }
        let ids = pendingPresentationACKs
        pendingPresentationACKs.removeAll()
        onPresented?(ids)
    }

    // MARK: - Timer

    private func updateTimerIfNeeded(usingTimer: Bool = true) {
        guard usingTimer else {
            timer?.invalidate()
            timer = nil
            return
        }
        let needsTimer: Bool
        switch visualState {
        case .transformingToBottle, .transformingBack, .bottleOpening, .suspended:
            needsTimer = true
        case .bottleIdle:
            // Waiting with everything read for the busy conflict to end
            // (the revert-back is deferred) — keep polling the gate.
            needsTimer = lastUnread == 0
        case .normal, .reading:
            needsTimer = false
        }
        if needsTimer, timer == nil {
            let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.advance(now: self.nowProvider())
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !needsTimer {
            timer?.invalidate()
            timer = nil
        }
    }

    // MARK: - Test access

    var isBottleForm: Bool {
        if visualState.isBottleForm { return true }
        // Suspended mid-morph still shows the frozen silhouette.
        return visualState == .suspended && rawProgress > 0
    }

    var swayEnabled: Bool {
        switch visualState {
        case .bottleIdle, .reading, .bottleOpening:
            return !reduceMotion()
        default:
            return false
        }
    }

    func snapshotForTesting() -> (
        state: BottleVisualState,
        rawProgress: Double,
        formProgress: Double,
        opening: Double,
        readingLetterID: String?,
        pendingACKs: [String]
    ) {
        (visualState, rawProgress, formProgress, openingProgress,
         readingLetterID, pendingPresentationACKs)
    }
}
