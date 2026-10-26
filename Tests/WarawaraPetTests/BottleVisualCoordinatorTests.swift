import Combine
import Foundation
import XCTest
@testable import WarawaraPet

/// Phase 8C visual state machine coverage against a REAL
/// BottleMailCoordinator (mock transport + temp-file store): morph
/// triggering, single-morph batching, reading lifecycle, busy gating,
/// freeze/resume, restart recovery and offline reconciliation.
@MainActor
final class BottleVisualCoordinatorTests: XCTestCase {
    typealias MockTransport = BottleMailCoordinatorTests.MockTransport

    private var directory: URL!
    private var fileURL: URL!
    private var currentDate = Date(timeIntervalSinceReferenceDate: 0)
    private var petBusy = false
    private var presentedBatches: [[String]] = []
    private var openedReadingRequests: [String] = []

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BottleVisualCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("mailbox.json")
        currentDate = Date(timeIntervalSinceReferenceDate: 0)
        petBusy = false
        presentedBatches = []
        openedReadingRequests = []
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func remote(_ seq: Int, id: String = UUID().uuidString) -> BottleMailRemoteLetter {
        BottleMailRemoteLetter(
            id: id, seq: seq, body: "信 \(seq)", createdAt: "2026-10-17T00:00:00Z", openedAt: nil
        )
    }

    private func makeHarness() -> (BottleMailCoordinator, MockTransport, BottleVisualCoordinator) {
        let transport = MockTransport()
        let credentials = InMemoryBottleMailCredentialStore()
        let coordinator = BottleMailCoordinator(
            transport: transport,
            credentials: credentials,
            store: BottleMailFileStore(fileURL: fileURL)
        )
        coordinator.pollIntervalRange = 0.05...0.05
        coordinator.backoffBase = 0.01
        coordinator.backoffMax = 0.5
        coordinator.pendingDeliveryRetryInterval = 0.05
        coordinator.openRetryInterval = 600
        coordinator.delayProvider = { $0.lowerBound }
        coordinator.localOpenedAtProvider = { "LOCAL_STAMP" }

        let visual = BottleVisualCoordinator(mailbox: coordinator)
        visual.morphDuration = 0.4
        visual.openingDuration = 0.2
        visual.nowProvider = { [weak self] in self?.currentDate ?? Date() }
        visual.isPetBusy = { [weak self] in self?.petBusy ?? false }
        visual.reduceMotion = { false }
        visual.onPresented = { [weak self] ids in
            self?.presentedBatches.append(ids)
            ids.forEach { coordinator.acknowledgeDelivery($0) }
        }
        visual.onOpenReadingRequested = { [weak self] id in
            self?.openedReadingRequests.append(id)
        }
        return (coordinator, transport, visual)
    }

    private func advanceTime(_ seconds: TimeInterval, visual: BottleVisualCoordinator) {
        currentDate = currentDate.addingTimeInterval(seconds)
        // The visual runs on main; the test is MainActor-isolated.
        visual.advance(now: currentDate)
    }

    /// Pumps the MAIN runloop so queued @Published updates execute.
    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            await MainActor.run {}
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition(), "waitUntil condition never became true")
    }

    // MARK: - Delivery -> morph -> read -> revert

    func testOneLetterMorphsOpensReadsAndReverts() async throws {
        let (coordinator, transport, visual) = makeHarness()
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        let id = UUID().uuidString
        transport.onFetch = { after, _, _ in
            after == 0
                ? BottleMailPage(letters: [self.remote(1, id: id)], nextAfter: 1)
                : BottleMailPage(letters: [], nextAfter: after)
        }
        transport.onOpen = { _, _ in "2026-10-17T01:00:00Z" }
        visual.start(usingTimer: false)
        try await coordinator.activate(code: "C", label: "Mac")

        await waitUntil { coordinator.snapshotForTesting().letters.count == 1 }
        await waitUntil { visual.snapshotForTesting().state == .transformingToBottle }

        // Morph completes -> bottleIdle + the delivery is acknowledged.
        advanceTime(0.5, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .bottleIdle)
        XCTAssertEqual(visual.snapshotForTesting().formProgress, 1)
        XCTAssertEqual(Set(presentedBatches.flatMap { $0 }), Set([id]))
        await waitUntil { coordinator.snapshotForTesting().deliveryQueue.isEmpty }
        XCTAssertEqual(makeStore().snapshot().letters.first?.delivered, true,
                       "presentation completion persists the delivery ACK")

        // Tap opens the bottle: cork animation, then the reading window.
        XCTAssertTrue(visual.handleBottleTap())
        XCTAssertEqual(visual.snapshotForTesting().state, .bottleOpening)
        advanceTime(0.3, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .reading)
        XCTAssertEqual(visual.snapshotForTesting().readingLetterID, id)
        XCTAssertEqual(openedReadingRequests, [id])

        // Closing the reading window IS the reading-completion action:
        // local read + server reconcile + reverse poof.
        visual.readingWindowClosed()
        XCTAssertEqual(visual.snapshotForTesting().state, .bottleIdle,
                       "closing leaves .reading FIRST (reentrancy-free)")
        await waitUntil { coordinator.snapshotForTesting().unread == 0 }
        // The read completed locally (the server confirm may already
        // have overwritten the stamp — the OFFLINE test pins the exact
        // local value).
        XCTAssertNotNil(coordinator.snapshotForTesting().letters.first?.openedAt)
        await waitUntil { visual.snapshotForTesting().state == .transformingBack }
        advanceTime(0.5, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .normal)
        XCTAssertEqual(visual.snapshotForTesting().formProgress, 0)
        await waitUntil {
            coordinator.snapshotForTesting().letters.first?.openedAt == "2026-10-17T01:00:00Z"
        }
    }

    func testMultipleLettersMorphOnceAndAreReadInOrder() async throws {
        let (coordinator, transport, visual) = makeHarness()
        var states: [BottleVisualState] = []
        var cancellable: AnyCancellable?
        cancellable = visual.$visualState.sink { states.append($0) }
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        let id1 = UUID().uuidString
        let id2 = UUID().uuidString
        transport.onFetch = { after, _, _ in
            after == 0
                ? BottleMailPage(
                    letters: [self.remote(1, id: id1), self.remote(2, id: id2)],
                    nextAfter: 2
                )
                : BottleMailPage(letters: [], nextAfter: after)
        }
        transport.onOpen = { _, _ in "2026-10-17T01:00:00Z" }
        visual.start(usingTimer: false)
        try await coordinator.activate(code: "C", label: "Mac")

        await waitUntil { coordinator.snapshotForTesting().letters.count == 2 }
        await waitUntil { visual.snapshotForTesting().state == .transformingToBottle }
        advanceTime(0.5, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .bottleIdle)
        // ONE morph presents BOTH letters; both ACKed together.
        XCTAssertEqual(states.filter { $0 == .transformingToBottle }.count, 1)
        XCTAssertEqual(presentedBatches.count, 1)
        XCTAssertEqual(Set(presentedBatches[0]), Set([id1, id2]))

        XCTAssertTrue(visual.handleBottleTap())
        advanceTime(0.3, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .reading)
        let firstUnread = coordinator.snapshotForTesting().letters
            .filter(\.isUnread).sorted { $0.seq < $1.seq }.first?.id
        XCTAssertEqual(visual.snapshotForTesting().readingLetterID, firstUnread)
        XCTAssertEqual(firstUnread, id1)

        // Close the paper for the first letter: it is marked read, the
        // bottle STAYS (a second letter remains), and the next tap
        // presents the next one.
        visual.readingWindowClosed()
        await waitUntil { coordinator.snapshotForTesting().unread == 1 }
        XCTAssertEqual(visual.snapshotForTesting().state, .bottleIdle)
        XCTAssertTrue(visual.handleBottleTap())
        advanceTime(0.3, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .reading)
        XCTAssertEqual(visual.snapshotForTesting().readingLetterID, id2,
                       "the next tap opens the next unread letter")

        // Close the last paper: finish + revert.
        visual.readingWindowClosed()
        await waitUntil { coordinator.snapshotForTesting().unread == 0 }
        await waitUntil { visual.snapshotForTesting().state == .transformingBack }
        advanceTime(0.5, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .normal)
        XCTAssertEqual(states.filter { $0 == .transformingBack }.count, 1)
        _ = cancellable
    }

    func testClosingReadingWindowCompletesTheRead() async throws {
        // The NEW acceptance flow: closing the paper IS the read —
        // there is no put-away button anymore.
        let (coordinator, transport, visual) = makeHarness()
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        let id = UUID().uuidString
        transport.onFetch = { after, _, _ in
            after == 0
                ? BottleMailPage(letters: [self.remote(1, id: id)], nextAfter: 1)
                : BottleMailPage(letters: [], nextAfter: after)
        }
        transport.onOpen = { _, _ in "2026-10-17T01:00:00Z" }
        visual.start(usingTimer: false)
        try await coordinator.activate(code: "C", label: "Mac")
        await waitUntil { coordinator.snapshotForTesting().letters.count == 1 }
        await waitUntil { visual.snapshotForTesting().state == .transformingToBottle }
        advanceTime(0.5, visual: visual)
        XCTAssertTrue(visual.handleBottleTap())
        advanceTime(0.3, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .reading)

        // Close: the letter is read, the reverse poof follows.
        visual.readingWindowClosed()
        await waitUntil { coordinator.snapshotForTesting().unread == 0 }
        XCTAssertNotNil(coordinator.snapshotForTesting().letters.first?.openedAt,
                        "closing marks the letter read")
        await waitUntil { visual.snapshotForTesting().state == .transformingBack }
        advanceTime(0.5, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .normal)
    }

    func testWindowCloseIsIdempotentAndNeverReentrant() async throws {
        let (coordinator, transport, visual) = makeHarness()
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        let id = UUID().uuidString
        transport.onFetch = { after, _, _ in
            after == 0
                ? BottleMailPage(letters: [self.remote(1, id: id)], nextAfter: 1)
                : BottleMailPage(letters: [], nextAfter: after)
        }
        transport.onOpen = { _, _ in "2026-10-17T01:00:00Z" }
        visual.start(usingTimer: false)
        try await coordinator.activate(code: "C", label: "Mac")
        await waitUntil { coordinator.snapshotForTesting().letters.count == 1 }
        await waitUntil { visual.snapshotForTesting().state == .transformingToBottle }
        advanceTime(0.5, visual: visual)
        XCTAssertTrue(visual.handleBottleTap())
        advanceTime(0.3, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .reading)

        // A duplicated windowWillClose (AppKit may deliver the delegate
        // callback more than once) must be a pure no-op: no second
        // markOpened, no reentrancy, no crash.
        visual.readingWindowClosed()
        visual.readingWindowClosed()
        visual.readingWindowClosed()
        await waitUntil { coordinator.snapshotForTesting().unread == 0 }
        try? await Task.sleep(nanoseconds: 300_000_000)
        // The LOCAL read completes exactly once (the letter is marked
        // read, the confirmation never re-marks a read letter). The
        // /open channel itself is idempotent server-side and may be
        // resubmitted by a concurrent poll — but every call must target
        // the SAME letter.
        XCTAssertEqual(coordinator.snapshotForTesting().unread, 0)
        XCTAssertNotNil(coordinator.snapshotForTesting().letters.first?.openedAt)
        XCTAssertTrue(
            transport.openCalls.allSatisfy { $0.id == id },
            "every /open resubmission targets the same letter"
        )
        await waitUntil { visual.snapshotForTesting().state == .transformingBack }
        advanceTime(0.5, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .normal,
                       "the flow completes cleanly after duplicate closes")
    }

    func testRapidCloseReopenNeverPresentsTheSameLetter() async throws {
        let (coordinator, transport, visual) = makeHarness()
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        let id = UUID().uuidString
        transport.onFetch = { after, _, _ in
            after == 0
                ? BottleMailPage(letters: [self.remote(1, id: id)], nextAfter: 1)
                : BottleMailPage(letters: [], nextAfter: after)
        }
        transport.onOpen = { _, _ in "2026-10-17T01:00:00Z" }
        visual.start(usingTimer: false)
        try await coordinator.activate(code: "C", label: "Mac")
        await waitUntil { coordinator.snapshotForTesting().letters.count == 1 }
        await waitUntil { visual.snapshotForTesting().state == .transformingToBottle }
        advanceTime(0.5, visual: visual)
        XCTAssertTrue(visual.handleBottleTap())
        advanceTime(0.3, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .reading)

        // Close and IMMEDIATELY tap again — before the async local read
        // may be published. The just-closed letter must never re-open.
        visual.readingWindowClosed()
        XCTAssertTrue(visual.handleBottleTap())
        advanceTime(0.3, visual: visual)
        if let reopened = visual.snapshotForTesting().readingLetterID {
            XCTAssertNotEqual(reopened, id,
                              "the just-closed letter must not be presented again")
        } else {
            XCTAssertEqual(visual.snapshotForTesting().state, .bottleIdle,
                           "with nothing left to read the bottle idles")
        }
        // Everything settles: the letter is read, the pet reverts.
        await waitUntil { coordinator.snapshotForTesting().unread == 0 }
        await waitUntil { visual.snapshotForTesting().state == .transformingBack }
        advanceTime(0.5, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .normal)
    }

    func testNewLetterArrivesWhileReadingStaysBottle() async throws {
        let (coordinator, transport, visual) = makeHarness()
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        let id1 = UUID().uuidString
        let id2 = UUID().uuidString
        var deliverSecond = false
        transport.onFetch = { after, _, _ in
            if after == 0 {
                return BottleMailPage(letters: [self.remote(1, id: id1)], nextAfter: 1)
            }
            if deliverSecond {
                return BottleMailPage(letters: [self.remote(2, id: id2)], nextAfter: 2)
            }
            return BottleMailPage(letters: [], nextAfter: after)
        }
        transport.onOpen = { _, _ in "2026-10-17T01:00:00Z" }
        visual.start(usingTimer: false)
        try await coordinator.activate(code: "C", label: "Mac")
        await waitUntil { coordinator.snapshotForTesting().letters.count == 1 }
        await waitUntil { visual.snapshotForTesting().state == .transformingToBottle }
        advanceTime(0.5, visual: visual)
        XCTAssertTrue(visual.handleBottleTap())
        advanceTime(0.3, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .reading)

        // A second letter lands while reading: stays a bottle, the new
        // delivery is acknowledged immediately (presented by the
        // standing bottle), NO second morph happens.
        deliverSecond = true
        await waitUntil { coordinator.snapshotForTesting().letters.count == 2 }
        await waitUntil { self.presentedBatches.count == 2 }
        XCTAssertEqual(visual.snapshotForTesting().state, .reading)
        XCTAssertEqual(Set(presentedBatches[1]), Set([id2]))
        await waitUntil { coordinator.snapshotForTesting().deliveryQueue.isEmpty }
        XCTAssertEqual(visual.snapshotForTesting().formProgress, 1)
    }

    // MARK: - Busy gating

    func testBusyConflictsDelayTheMorph() async throws {
        let (coordinator, transport, visual) = makeHarness()
        petBusy = true
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        let id = UUID().uuidString
        transport.onFetch = { after, _, _ in
            after == 0
                ? BottleMailPage(letters: [self.remote(1, id: id)], nextAfter: 1)
                : BottleMailPage(letters: [], nextAfter: after)
        }
        transport.onOpen = { _, _ in "2026-10-17T01:00:00Z" }
        visual.start(usingTimer: false)
        try await coordinator.activate(code: "C", label: "Mac")
        await waitUntil { coordinator.snapshotForTesting().letters.count == 1 }

        // Pet busy (sleep/drag/event): the morph is suspended, not
        // started — progress stays 0.
        await waitUntil { visual.snapshotForTesting().state == .suspended }
        advanceTime(1, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .suspended)
        XCTAssertEqual(visual.snapshotForTesting().rawProgress, 0)

        // Free again: the morph proceeds.
        petBusy = false
        advanceTime(0.05, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .transformingToBottle)
        advanceTime(0.5, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .bottleIdle)
        XCTAssertEqual(Set(presentedBatches.flatMap { $0 }), Set([id]))
    }

    func testMorphWaitsForInFlightHopOrFloatToFinish() async throws {
        // The acceptance rule: mail arriving mid-hop/mid-float must not
        // start the morph until the current motion has landed (the
        // morph never hard-cancels a motion, so the position never
        // jumps).
        let (coordinator, transport, visual) = makeHarness()
        var transientMotion = true
        visual.isPetBusy = { transientMotion }
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        let id = UUID().uuidString
        transport.onFetch = { after, _, _ in
            after == 0
                ? BottleMailPage(letters: [self.remote(1, id: id)], nextAfter: 1)
                : BottleMailPage(letters: [], nextAfter: after)
        }
        transport.onOpen = { _, _ in "2026-10-17T01:00:00Z" }
        visual.start(usingTimer: false)
        try await coordinator.activate(code: "C", label: "Mac")
        await waitUntil { coordinator.snapshotForTesting().letters.count == 1 }
        await waitUntil { visual.snapshotForTesting().state == .suspended }
        advanceTime(1, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .suspended,
                       "the morph waits for the in-flight motion")
        // The hop/float lands: the morph proceeds.
        transientMotion = false
        advanceTime(0.05, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .transformingToBottle)
        advanceTime(0.5, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .bottleIdle)
    }

    func testMorphFreezesWhenBusyMidFlightAndResumesContinuously() async throws {
        let (coordinator, transport, visual) = makeHarness()
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        let id = UUID().uuidString
        transport.onFetch = { after, _, _ in
            after == 0
                ? BottleMailPage(letters: [self.remote(1, id: id)], nextAfter: 1)
                : BottleMailPage(letters: [], nextAfter: after)
        }
        transport.onOpen = { _, _ in "2026-10-17T01:00:00Z" }
        visual.start(usingTimer: false)
        try await coordinator.activate(code: "C", label: "Mac")
        await waitUntil { coordinator.snapshotForTesting().letters.count == 1 }
        await waitUntil { visual.snapshotForTesting().state == .transformingToBottle }

        // Halfway through, the user starts dragging: the morph freezes.
        advanceTime(0.2, visual: visual)
        let frozen = visual.snapshotForTesting().rawProgress
        XCTAssertEqual(frozen, 0.5, accuracy: 0.001)
        petBusy = true
        advanceTime(0.1, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .suspended)
        XCTAssertEqual(visual.snapshotForTesting().rawProgress, frozen, accuracy: 0.001)

        // Released: it resumes from the frozen progress, no jump.
        petBusy = false
        advanceTime(0.05, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .transformingToBottle)
        XCTAssertEqual(visual.snapshotForTesting().rawProgress, frozen, accuracy: 0.01)
        advanceTime(0.3, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .bottleIdle)
    }

    // MARK: - Restart + offline

    func testPoofMomentFiresExactlyOncePerTransition() async throws {
        let (coordinator, transport, visual) = makeHarness()
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        let id = UUID().uuidString
        transport.onFetch = { after, _, _ in
            after == 0
                ? BottleMailPage(letters: [self.remote(1, id: id)], nextAfter: 1)
                : BottleMailPage(letters: [], nextAfter: after)
        }
        transport.onOpen = { _, _ in "2026-10-17T01:00:00Z" }
        var poofCount = 0
        visual.onPoofMoment = { poofCount += 1 }
        visual.start(usingTimer: false)
        try await coordinator.activate(code: "C", label: "Mac")

        await waitUntil { coordinator.snapshotForTesting().letters.count == 1 }
        await waitUntil { visual.snapshotForTesting().state == .transformingToBottle }
        // Forward: the sound fires at the forward smoke onset.
        advanceTime(0.15, visual: visual)
        XCTAssertEqual(poofCount, 1, "the poof fires once on the way to the bottle")
        // Completing the transition never re-fires it.
        advanceTime(0.5, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .bottleIdle)
        XCTAssertEqual(poofCount, 1)
        // New mail while already a bottle must NOT re-play the poof.
        XCTAssertEqual(poofCount, 1)

        // Reverse: close the paper for the last letter. The reverse
        // poof fires at the REVERSE smoke onset (timeline <=
        // smokeFadeEnd), not at the forward poofPoint.
        XCTAssertTrue(visual.handleBottleTap())
        advanceTime(0.3, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .reading)
        visual.readingWindowClosed()
        await waitUntil { coordinator.snapshotForTesting().unread == 0 }
        await waitUntil { visual.snapshotForTesting().state == .transformingBack }
        // Still early in the reverse timeline (1.0 > smokeFadeEnd): no
        // sound yet.
        advanceTime(0.08, visual: visual)
        XCTAssertEqual(poofCount, 1, "the reverse poof must not fire before its own smoke onset")
        // Cross the reverse onset: exactly one fire.
        advanceTime(0.08, visual: visual)
        XCTAssertEqual(poofCount, 2, "the reverse transition fires exactly one poof")
        advanceTime(0.5, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .normal)
        XCTAssertEqual(poofCount, 2, "no extra poofs after the reverse completes")
    }

    func testPoofFreezeResumeNeverDuplicatesTheSound() async throws {
        let (coordinator, transport, visual) = makeHarness()
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        let id = UUID().uuidString
        transport.onFetch = { after, _, _ in
            after == 0
                ? BottleMailPage(letters: [self.remote(1, id: id)], nextAfter: 1)
                : BottleMailPage(letters: [], nextAfter: after)
        }
        transport.onOpen = { _, _ in "2026-10-17T01:00:00Z" }
        var poofCount = 0
        visual.onPoofMoment = { poofCount += 1 }
        visual.start(usingTimer: false)
        try await coordinator.activate(code: "C", label: "Mac")
        await waitUntil { coordinator.snapshotForTesting().letters.count == 1 }
        await waitUntil { visual.snapshotForTesting().state == .transformingToBottle }

        // FORWARD: freeze BEFORE the forward onset — no sound while
        // frozen, exactly one after the resume.
        advanceTime(0.05, visual: visual) // timeline 0.125 < poofPoint
        XCTAssertEqual(poofCount, 0)
        petBusy = true
        advanceTime(0.1, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .suspended)
        XCTAssertEqual(poofCount, 0, "no poof while frozen before the onset")
        petBusy = false
        advanceTime(0.05, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .transformingToBottle)
        advanceTime(0.1, visual: visual) // crosses poofPoint
        XCTAssertEqual(poofCount, 1, "exactly one poof after the forward resume")
        advanceTime(0.5, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .bottleIdle)

        // REVERSE: freeze BEFORE the reverse onset, resume, exactly one
        // more fire; freezing again AFTER the onset adds nothing.
        XCTAssertTrue(visual.handleBottleTap())
        advanceTime(0.3, visual: visual)
        visual.readingWindowClosed()
        await waitUntil { coordinator.snapshotForTesting().unread == 0 }
        await waitUntil { visual.snapshotForTesting().state == .transformingBack }
        advanceTime(0.06, visual: visual) // timeline ~0.85 > smokeFadeEnd
        XCTAssertEqual(poofCount, 1, "still before the reverse onset")
        petBusy = true
        advanceTime(0.1, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .suspended)
        XCTAssertEqual(poofCount, 1, "no poof while frozen before the reverse onset")
        petBusy = false
        advanceTime(0.05, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .transformingBack)
        advanceTime(0.1, visual: visual) // crosses smokeFadeEnd (0.726)
        XCTAssertEqual(poofCount, 2, "exactly one poof after the reverse resume")
        advanceTime(0.5, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .normal)
        XCTAssertEqual(poofCount, 2, "no duplicate poofs")
    }

    func testFormProgressStepsOnlyAtTheSmokeCoveredSwitch() async throws {
        let (coordinator, transport, visual) = makeHarness()
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        let id = UUID().uuidString
        transport.onFetch = { after, _, _ in
            after == 0
                ? BottleMailPage(letters: [self.remote(1, id: id)], nextAfter: 1)
                : BottleMailPage(letters: [], nextAfter: after)
        }
        transport.onOpen = { _, _ in "2026-10-17T01:00:00Z" }
        visual.start(usingTimer: false)
        try await coordinator.activate(code: "C", label: "Mac")

        await waitUntil { coordinator.snapshotForTesting().letters.count == 1 }
        await waitUntil { visual.snapshotForTesting().state == .transformingToBottle }
        // Before the switch: still the Warawara form.
        advanceTime(0.1, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().formProgress, 0)
        // Cross the switch: the form flips — and the timeline guarantees
        // the core smoke is fully opaque exactly there.
        advanceTime(0.1, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().formProgress, 1)
        XCTAssertEqual(
            BottlePoofTimeline.coreSmokeOpacity(t: BottlePoofTimeline.switchPoint), 1,
            accuracy: 0.001
        )
    }

    func testRestartWithUnreadLettersMorphsWithoutRedelivery() async throws {
        // A mailbox with a delivered-but-unread letter (the app was
        // killed after the delivery ACK, before reading).
        let id = UUID().uuidString
        let store = BottleMailFileStore(fileURL: fileURL)
        try store.merge(remote: [remote(1, id: id)], advancingCursorTo: 1)
        try store.markDeliveredLocally(id: id)

        let transport = MockTransport()
        let coordinator = BottleMailCoordinator(
            transport: transport,
            credentials: InMemoryBottleMailCredentialStore(),
            store: BottleMailFileStore(fileURL: fileURL)
        )
        coordinator.openRetryInterval = 600
        let visual = BottleVisualCoordinator(mailbox: coordinator)
        visual.morphDuration = 0.4
        visual.nowProvider = { [weak self] in self?.currentDate ?? Date() }
        visual.isPetBusy = { false }
        visual.onPresented = { [weak self] ids in self?.presentedBatches.append(ids) }
        coordinator.start()
        visual.start(usingTimer: false)

        await waitUntil { coordinator.snapshotForTesting().letters.count == 1 }
        await waitUntil { visual.snapshotForTesting().state == .transformingToBottle }
        advanceTime(0.5, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .bottleIdle)
        XCTAssertTrue(presentedBatches.isEmpty,
                      "delivered letters must not be re-presented")
    }

    func testOfflineReadCompletesLocallyAndReconcilesAfterNetworkReturns() async throws {
        let (coordinator, transport, visual) = makeHarness()
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        let id = UUID().uuidString
        var offline = true
        transport.onFetch = { after, _, _ in
            after == 0
                ? BottleMailPage(letters: [self.remote(1, id: id)], nextAfter: 1)
                : BottleMailPage(letters: [], nextAfter: after)
        }
        transport.onOpen = { _, _ in
            if offline { throw BottleMailAPIError.network("offline") }
            return "2026-10-17T01:00:00Z"
        }
        visual.start(usingTimer: false)
        try await coordinator.activate(code: "C", label: "Mac")
        await waitUntil { coordinator.snapshotForTesting().letters.count == 1 }
        await waitUntil { visual.snapshotForTesting().state == .transformingToBottle }
        advanceTime(0.5, visual: visual)
        XCTAssertTrue(visual.handleBottleTap())
        advanceTime(0.3, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .reading)

        // Offline: the read completes LOCALLY, the revert does NOT wait
        // for the server.
        visual.readingWindowClosed()
        await waitUntil { coordinator.snapshotForTesting().unread == 0 }
        XCTAssertEqual(coordinator.snapshotForTesting().letters.first?.openedAt, "LOCAL_STAMP")
        await waitUntil { visual.snapshotForTesting().state == .transformingBack }
        advanceTime(0.5, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .normal)

        // Network returns: the pending /open reconciles automatically.
        offline = false
        coordinator.handleNetworkRecovery()
        await waitUntil {
            coordinator.snapshotForTesting().letters.first?.openedAt == "2026-10-17T01:00:00Z"
        }
        XCTAssertGreaterThanOrEqual(transport.openCalls.count, 1)
        XCTAssertEqual(visual.snapshotForTesting().state, .normal,
                       "reconciliation must not re-open the bottle")
    }

    // MARK: - Interaction edges

    func testClicksWithNoUnreadLettersAreNotConsumed() {
        let (_, _, visual) = makeHarness()
        visual.start(usingTimer: false)
        advanceTime(0.1, visual: visual)
        XCTAssertFalse(visual.handleBottleTap())
        XCTAssertEqual(visual.snapshotForTesting().state, .normal)
    }

    func testReduceMotionDoesNotEnableDecorativeSway() async throws {
        // Reach bottleIdle via a delivered-but-unread mailbox.
        let id = UUID().uuidString
        let store = BottleMailFileStore(fileURL: fileURL)
        try store.merge(remote: [remote(1, id: id)], advancingCursorTo: 1)
        try store.markDeliveredLocally(id: id)

        let transport = MockTransport()
        let coordinator = BottleMailCoordinator(
            transport: transport,
            credentials: InMemoryBottleMailCredentialStore(),
            store: BottleMailFileStore(fileURL: fileURL)
        )
        coordinator.openRetryInterval = 600
        let visual = BottleVisualCoordinator(mailbox: coordinator)
        visual.morphDuration = 0.4
        visual.nowProvider = { [weak self] in self?.currentDate ?? Date() }
        visual.isPetBusy = { false }
        visual.reduceMotion = { false }
        coordinator.start()
        visual.start(usingTimer: false)

        await waitUntil { coordinator.snapshotForTesting().letters.count == 1 }
        await waitUntil { visual.snapshotForTesting().state == .transformingToBottle }
        advanceTime(0.5, visual: visual)
        XCTAssertEqual(visual.snapshotForTesting().state, .bottleIdle)

        // The stable bottle is COMPLETELY static per the acceptance
        // feedback: no decorative sway in ANY state (the poof timeline
        // keeps its own jump/landing inertia).
        XCTAssertFalse(visual.swayEnabled)
        XCTAssertTrue(visual.bottleFormActive,
                      "the pet layer suspends while the bottle form is up")
        advanceTime(2, visual: visual)
        XCTAssertFalse(visual.swayEnabled)
    }

    // MARK: - Helpers

    private func makeStore() -> BottleMailFileStore {
        BottleMailFileStore(fileURL: fileURL)
    }
}
