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
    /// True while ANY bottle-form presentation is active (including a
    /// frozen mid-morph silhouette) — the pet layer suspends its whole
    /// autonomous machinery while this is true.
    @Published private(set) var bottleFormActive = false
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
    /// The letter closed moments ago whose local read may not be
    /// published yet: excluded from the next tap so a fast close/re-open
    /// never presents the SAME letter twice.
    private var recentlyClosedID: String?
    private var recentlyClosedAt: Date = .distantPast
    private static let recentlyClosedExclusion: TimeInterval = 1.5

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
                // The recently-closed letter is now durably read: the
                // fast re-open exclusion can retire.
                if let id = self.recentlyClosedID,
                   !self.mailbox.letters.contains(where: { $0.id == id && $0.isUnread }) {
                    self.recentlyClosedID = nil
                }
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

    /// The user closed the reading window — the ONLY reading-completion
    /// entry (there is no put-away button anymore). Order matters:
    /// 1. leave `.reading` FIRST so every re-entry path (including a
    ///    repeated windowWillClose) is a no-op — this is what makes the
    ///    close path reentrancy-free;
    /// 2. THEN submit the local-first read (async server reconcile
    ///    stays as-is);
    /// 3. the mailbox publish drives the next step (unread > 0 stays a
    ///    bottle; unread == 0 starts the reverse poof).
    /// Never closes any window itself, never terminates anything.
    func readingWindowClosed() {
        guard visualState == .reading else { return }

        let finishedID = readingLetterID
        readingLetterID = nil
        visualState = .bottleIdle
        updateTimerIfNeeded()

        if let id = finishedID {
            recentlyClosedID = id
            recentlyClosedAt = nowProvider()
            mailbox.markOpened(letterID: id)
        }

        // Idempotent evaluate: drives the revert immediately when the
        // read was already published, and stays inert otherwise (the
        // mailbox subscription re-evaluates on the publish).
        evaluate(now: nowProvider())
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
                    // Delayed start: remember where the suspension came
                    // from so the resume path restarts the morph.
                    suspendedFrom = .normal
                    visualState = .suspended
                } else {
                    beginMorph(direction: .toBottle, at: now)
                }
            }
        case .suspended:
            if busy { break }
            if suspendedFrom == .bottleOpening {
                resumeOpening(at: now)
            } else if suspendedFrom == .normal {
                // Delayed start (busy blocked the morph before it
                // began): begin only if mail is still waiting.
                if unread > 0 {
                    beginMorph(direction: .toBottle, at: now)
                } else {
                    visualState = .normal
                    updateTimerIfNeeded()
                }
            } else {
                // A frozen in-flight morph (toBottle or back): resume it
                // REGARDLESS of the unread count — the in-flight cases
                // handle a mid-freeze unread change themselves (a read
                // mid-freeze reverses, new mail mid-reverse turns back).
                resumeMorph(at: now)
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
                let nextUnread = mailbox.letters
                    .filter { $0.isUnread && $0.id != activeRecentExclusion(at: now) }
                    .sorted { $0.seq < $1.seq }
                    .first
                guard let id = nextUnread?.id else {
                    // Nothing left to read (everything was closed in a
                    // previous session): fall back to the idle bottle —
                    // the unread==0 rule drives the revert.
                    readingLetterID = nil
                    visualState = .bottleIdle
                    updateTimerIfNeeded()
                    return
                }
                readingLetterID = id
                visualState = .reading
                updateTimerIfNeeded()
                onOpenReadingRequested?(id)
            }
        case .reading:
            // The reading window close is the ONLY completion entry
            // (`readingWindowClosed`). Nothing here may close the
            // window, mark anything read, or terminate anything — the
            // mailbox publish drives the revert via the .bottleIdle
            // rule. This keeps the close path free of reentrancy.
            break
        }

        // Publish the timeline + the hidden form step. The form only
        // flips at the timeline's switch point, where the occlusion
        // smoke is fully opaque (BottlePoofTimeline invariant).
        let timeline = min(max(rawProgress, 0), 1)
        morphProgress = timeline
        formProgress = BottlePoofTimeline.formProgress(at: timeline)
        bottleFormActive = isBottleForm
        if !poofFired {
            // The poof sound fires when THIS direction's smoke first
            // appears: forward at poofPoint, reverse at smokeFadeEnd
            // (the reversed dissipation tail) — never late, never twice.
            let onset = BottlePoofTimeline.smokeOnset(for: direction)
            let crossed: Bool
            switch direction {
            case .toBottle: crossed = timeline >= onset
            case .toNormal: crossed = timeline <= onset
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

    /// The letter just closed is excluded from the next tap until its
    /// read is durably published (or the exclusion window passes) — a
    /// fast close/re-open can never present the same letter twice.
    private func activeRecentExclusion(at now: Date) -> String? {
        guard let id = recentlyClosedID else { return nil }
        if now.timeIntervalSince(recentlyClosedAt) > Self.recentlyClosedExclusion {
            recentlyClosedID = nil
            return nil
        }
        return id
    }

    var isBottleForm: Bool {
        if visualState.isBottleForm { return true }
        // Suspended mid-morph still shows the frozen silhouette.
        return visualState == .suspended && rawProgress > 0
    }

    /// The stable bottle is completely static per the acceptance
    /// feedback: no floating sway, no idle bob — only the poof timeline
    /// keeps its own jump/landing inertia.
    var swayEnabled: Bool {
        false
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
