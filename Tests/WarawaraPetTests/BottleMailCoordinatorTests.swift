import Combine
import Foundation
import XCTest
@testable import WarawaraPet

/// Coordinator coverage with an injected mock transport + in-memory
/// credential store + temp-file mailbox: activation, revocation,
/// polling/dedupe, busy gating, backoff, wake triggers, read
/// confirmation with automatic retry, main-thread publishing, stale
/// async-result protection, and the consumable delivery queue.
final class BottleMailCoordinatorTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!

    final class MockTransport: BottleMailAPITransport {
        var onActivate: ((String, String) async throws -> BottleMailActivation)?
        var onFetch: ((Int, Int, String) async throws -> BottleMailPage)?
        var onOpen: ((String, String) async throws -> String?)?
        private(set) var fetchCalls: [(after: Int, limit: Int, token: String)] = []
        private(set) var openCalls: [(id: String, token: String)] = []
        private(set) var activateCalls: [(code: String, label: String)] = []

        func activate(code: String, label: String) async throws -> BottleMailActivation {
            activateCalls.append((code, label))
            guard let onActivate else { throw BottleMailAPIError.network("no handler") }
            return try await onActivate(code, label)
        }

        func fetchLetters(after: Int, limit: Int, token: String) async throws -> BottleMailPage {
            fetchCalls.append((after, limit, token))
            guard let onFetch else { throw BottleMailAPIError.network("no handler") }
            return try await onFetch(after, limit, token)
        }

        func markOpened(id: String, token: String) async throws -> String? {
            openCalls.append((id, token))
            guard let onOpen else { throw BottleMailAPIError.network("no handler") }
            return try await onOpen(id, token)
        }
    }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BottleMailCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("mailbox.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func remote(_ seq: Int, id: String = UUID().uuidString, body: String? = nil) -> BottleMailRemoteLetter {
        BottleMailRemoteLetter(
            id: id,
            seq: seq,
            body: body ?? "信 \(seq)",
            createdAt: "2026-10-17T00:00:00Z",
            openedAt: nil
        )
    }

    private func makeStore(fileURL: URL? = nil) -> BottleMailFileStore {
        BottleMailFileStore(fileURL: fileURL ?? self.fileURL)
    }

    private func makeHarness() -> (BottleMailCoordinator, MockTransport, InMemoryBottleMailCredentialStore) {
        let transport = MockTransport()
        let credentials = InMemoryBottleMailCredentialStore()
        let coordinator = BottleMailCoordinator(
            transport: transport,
            credentials: credentials,
            store: makeStore()
        )
        coordinator.pollIntervalRange = 0.05...0.05
        coordinator.backoffBase = 0.01
        coordinator.backoffMax = 0.5
        coordinator.pendingDeliveryRetryInterval = 0.05
        coordinator.openRetryInterval = 0.05
        coordinator.delayProvider = { $0.lowerBound }
        return (coordinator, transport, credentials)
    }

    /// Pumps the MAIN runloop so queued `@Published` updates execute —
    /// every published mutation in the coordinator happens on main.
    /// A silent timeout hides races (the condition may be satisfied
    /// vacuously by the initial published state), so timeouts fail the
    /// test loudly at the call site.
    private func waitUntil(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            await MainActor.run {}
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition(), "waitUntil condition never became true", file: file, line: line)
    }

    // MARK: - Activation

    func testActivationSuccessStoresCredentialAndPollsImmediately() async throws {
        let (coordinator, transport, credentials) = makeHarness()
        transport.onActivate = { code, label in
            XCTAssertEqual(code, "CODE12345")
            return BottleMailActivation(deviceId: "d-1", deviceToken: "tok-1", label: label)
        }
        transport.onFetch = { _, _, token in
            XCTAssertEqual(token, "tok-1")
            return BottleMailPage(letters: [], nextAfter: 0)
        }
        try await coordinator.activate(code: "CODE12345", label: "她的Mac")
        await waitUntil { credentials.credential != nil }
        XCTAssertEqual(credentials.credential?.token, "tok-1")
        await waitUntil { transport.fetchCalls.count >= 1 }
        await waitUntil {
            if case .activated = coordinator.snapshotForTesting().activation { return true }
            return false
        }
        if case .activated(let label) = coordinator.snapshotForTesting().activation {
            XCTAssertEqual(label, "她的Mac")
        } else {
            XCTFail("expected activated")
        }
    }

    func testActivationFailureMapsToUserMessages() async {
        let (coordinator, transport, _) = makeHarness()
        transport.onActivate = { _, _ in throw BottleMailAPIError.http(status: 409, code: "code_used") }
        do {
            try await coordinator.activate(code: "X", label: "Mac")
            XCTFail("expected failure")
        } catch let error as BottleMailActivationError {
            XCTAssertEqual(error, .codeUsed)
            XCTAssertTrue(error.message.contains("已经"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    // MARK: - Polling / dedupe / persistence

    func testPollMergesDedupesAndDeliversInSeqOrder() async throws {
        let (coordinator, transport, _) = makeHarness()
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        let id1 = UUID().uuidString
        let id2 = UUID().uuidString
        var callCount = 0
        transport.onFetch = { after, _, _ in
            callCount += 1
            if callCount == 1 {
                return BottleMailPage(letters: [self.remote(1, id: id1)], nextAfter: 1)
            }
            return BottleMailPage(
                letters: [self.remote(1, id: id1), self.remote(2, id: id2)],
                nextAfter: 2
            )
        }
        try await coordinator.activate(code: "C", label: "Mac")
        await waitUntil { coordinator.snapshotForTesting().letters.count == 2 }
        XCTAssertEqual(coordinator.snapshotForTesting().letters.map(\.seq), [1, 2])
        XCTAssertEqual(coordinator.snapshotForTesting().unread, 2)
        await waitUntil { transport.fetchCalls.count >= 4 }
        XCTAssertEqual(coordinator.snapshotForTesting().letters.count, 2)
        XCTAssertGreaterThanOrEqual(transport.fetchCalls.last?.after ?? 0, 1)
    }

    func testRestartRecoversMailboxAndContinuesPolling() async throws {
        let (first, transport, credentials) = makeHarness()
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        transport.onFetch = { after, _, _ in
            after == 0
                ? BottleMailPage(letters: [self.remote(1)], nextAfter: 1)
                : BottleMailPage(letters: [], nextAfter: after)
        }
        try await first.activate(code: "C", label: "Mac")
        await waitUntil { first.snapshotForTesting().letters.count == 1 }

        let secondTransport = MockTransport()
        secondTransport.onFetch = { after, _, _ in
            BottleMailPage(letters: [], nextAfter: after)
        }
        let second = BottleMailCoordinator(
            transport: secondTransport,
            credentials: credentials,
            store: makeStore()
        )
        second.pollIntervalRange = 0.05...0.05
        second.delayProvider = { $0.lowerBound }
        second.start()
        await waitUntil { second.snapshotForTesting().letters.count == 1 }
        XCTAssertEqual(second.snapshotForTesting().unread, 1)
        await waitUntil { secondTransport.fetchCalls.count >= 1 }
        XCTAssertEqual(secondTransport.fetchCalls.first?.after, 1, "restart resumes from the persisted cursor")
    }

    // MARK: - Busy gating + consumable delivery queue

    func testBusyPetHoldsMailInPendingUntilFree() async throws {
        let (coordinator, transport, _) = makeHarness()
        var busy = true
        coordinator.isPetBusy = { busy }
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        transport.onFetch = { _, _, _ in
            BottleMailPage(letters: [self.remote(1), self.remote(2)], nextAfter: 2)
        }
        try await coordinator.activate(code: "C", label: "Mac")
        await waitUntil { coordinator.snapshotForTesting().pending == 2 }
        XCTAssertEqual(coordinator.snapshotForTesting().deliveryQueue.count, 0, "nothing delivered while busy")
        busy = false
        await waitUntil { coordinator.snapshotForTesting().deliveryQueue.count == 2 }
        XCTAssertEqual(coordinator.snapshotForTesting().deliveryQueue.map(\.letter.seq), [1, 2])
        XCTAssertEqual(coordinator.snapshotForTesting().pending, 0)
    }

    func testAcknowledgeDeliveryPopsOnceAndPersistsForRestart() async throws {
        let (coordinator, transport, credentials) = makeHarness()
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        transport.onFetch = { after, _, _ in
            after == 0
                ? BottleMailPage(letters: [self.remote(1), self.remote(2)], nextAfter: 2)
                : BottleMailPage(letters: [], nextAfter: after)
        }
        try await coordinator.activate(code: "C", label: "Mac")
        await waitUntil { coordinator.snapshotForTesting().deliveryQueue.count == 2 }
        let firstDelivery = coordinator.snapshotForTesting().deliveryQueue[0]
        coordinator.acknowledgeDelivery(firstDelivery.id)
        await waitUntil { coordinator.snapshotForTesting().deliveryQueue.count == 1 }
        XCTAssertEqual(coordinator.snapshotForTesting().deliveryQueue[0].letter.seq, 2)
        // Double-ack is a no-op.
        coordinator.acknowledgeDelivery(firstDelivery.id)
        await waitUntil { coordinator.snapshotForTesting().deliveryQueue.count == 1 }

        // Restart: the acked letter stays out of the queue; the unacked
        // one is re-enqueued exactly once.
        let secondTransport = MockTransport()
        secondTransport.onFetch = { after, _, _ in
            BottleMailPage(letters: [], nextAfter: after)
        }
        let second = BottleMailCoordinator(
            transport: secondTransport,
            credentials: credentials,
            store: makeStore()
        )
        second.pollIntervalRange = 0.05...0.05
        second.delayProvider = { $0.lowerBound }
        second.start()
        await waitUntil { second.snapshotForTesting().deliveryQueue.count == 1 }
        XCTAssertEqual(second.snapshotForTesting().deliveryQueue[0].letter.seq, 2,
                       "restart re-delivers only unacknowledged letters")
    }

    func testRapidAcksNeverLoseOrDuplicateDeliveries() async throws {
        let (coordinator, transport, credentials) = makeHarness()
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        transport.onFetch = { after, _, _ in
            after == 0
                ? BottleMailPage(letters: [self.remote(1), self.remote(2), self.remote(3)], nextAfter: 3)
                : BottleMailPage(letters: [], nextAfter: after)
        }
        try await coordinator.activate(code: "C", label: "Mac")
        await waitUntil { coordinator.snapshotForTesting().deliveryQueue.count == 3 }

        // Ack all three back-to-back without waiting between calls.
        let ids = coordinator.snapshotForTesting().deliveryQueue.map(\.id)
        for deliveryID in ids {
            coordinator.acknowledgeDelivery(deliveryID)
        }
        await waitUntil { coordinator.snapshotForTesting().deliveryQueue.isEmpty }
        XCTAssertEqual(coordinator.snapshotForTesting().letters.count, 3,
                       "letters remain in the mailbox after acks")
        // Exactly-once persistence: every letter carries delivered=true.
        let mailbox = makeStore().snapshot()
        XCTAssertEqual(mailbox.letters.count, 3)
        XCTAssertTrue(mailbox.letters.allSatisfy(\.delivered))
        // And nothing is lost or duplicated in the published snapshot.
        XCTAssertEqual(coordinator.snapshotForTesting().pending, 0)
    }

    // MARK: - Failure handling / revocation / backoff

    func testRevocationStopsPollingClearsTokenAndKeepsLetters() async throws {
        let (coordinator, transport, credentials) = makeHarness()
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        var revoked = false
        transport.onFetch = { after, _, _ in
            if revoked { throw BottleMailAPIError.http(status: 401, code: "unauthorized") }
            return BottleMailPage(
                letters: after == 0 ? [self.remote(1)] : [],
                nextAfter: after == 0 ? 1 : after
            )
        }
        try await coordinator.activate(code: "C", label: "Mac")
        await waitUntil { coordinator.snapshotForTesting().letters.count == 1 }
        let callsBefore = transport.fetchCalls.count
        revoked = true
        await waitUntil { coordinator.snapshotForTesting().activation == .revoked }
        XCTAssertNil(credentials.credential, "the revoked token must be discarded")
        XCTAssertEqual(coordinator.snapshotForTesting().letters.count, 1, "received letters survive revocation")
        let callsAfter = transport.fetchCalls.count
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(transport.fetchCalls.count, callsAfter)
        XCTAssertGreaterThanOrEqual(callsBefore, 1)
    }

    func testWakeAndNetworkRecoveryDoNotEraseRevokedState() async throws {
        let (coordinator, transport, credentials) = makeHarness()
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        var revoked = false
        transport.onFetch = { after, _, _ in
            if revoked { throw BottleMailAPIError.http(status: 401, code: "unauthorized") }
            return BottleMailPage(letters: [], nextAfter: after)
        }
        try await coordinator.activate(code: "C", label: "Mac")
        await waitUntil { transport.fetchCalls.count >= 1 }
        revoked = true
        await waitUntil { coordinator.snapshotForTesting().activation == .revoked }
        let callsAfterRevoke = transport.fetchCalls.count

        coordinator.handleWake()
        coordinator.handleNetworkRecovery()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(coordinator.snapshotForTesting().activation, .revoked,
                       "wake/network recovery must not erase the revoked state")
        XCTAssertEqual(transport.fetchCalls.count, callsAfterRevoke,
                       "no syncing without a token")
        XCTAssertNil(credentials.credential)
    }

    func testRevokedLettersRemainReadableAndReactivationResumes() async throws {
        let (coordinator, transport, credentials) = makeHarness()
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        var revoked = false
        transport.onFetch = { after, _, _ in
            if revoked { throw BottleMailAPIError.http(status: 401, code: "unauthorized") }
            return BottleMailPage(
                letters: after == 0 ? [self.remote(1)] : [],
                nextAfter: after == 0 ? 1 : after
            )
        }
        try await coordinator.activate(code: "C", label: "Mac")
        await waitUntil { coordinator.snapshotForTesting().letters.count == 1 }
        revoked = true
        await waitUntil { coordinator.snapshotForTesting().activation == .revoked }
        // Offline reading: the mailbox snapshot is still there.
        XCTAssertEqual(coordinator.snapshotForTesting().letters.count, 1)

        // Re-activate with a new code: syncing resumes and the revoked
        // flag is cleared.
        revoked = false
        transport.onActivate = { code, label in
            BottleMailActivation(deviceId: "d2", deviceToken: "tok2", label: label)
        }
        try await coordinator.activate(code: "NEWCODE", label: "Mac")
        await waitUntil {
            if case .activated = coordinator.snapshotForTesting().activation { return true }
            return false
        }
        await waitUntil { transport.fetchCalls.count >= 2 }
        XCTAssertEqual(makeStore().snapshot().isRevoked, false)
    }

    func testNoOpenConfirmationWithoutToken() async throws {
        let (coordinator, transport, _) = makeHarness()
        coordinator.markOpened(letterID: "x")
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(transport.openCalls.count, 0)
    }

    func testRevokedMailboxKeepsFullLettersAndNeverSubmitsOpen() async throws {
        let (coordinator, transport, _) = makeHarness()
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        let body = "完整正文内容，撤销后仍可阅读。"
        let id = UUID().uuidString
        var revoked = false
        transport.onFetch = { after, _, _ in
            if revoked { throw BottleMailAPIError.http(status: 401, code: "unauthorized") }
            return BottleMailPage(
                letters: after == 0 ? [self.remote(1, id: id, body: body)] : [],
                nextAfter: after == 0 ? 1 : after
            )
        }
        try await coordinator.activate(code: "C", label: "Mac")
        await waitUntil { coordinator.snapshotForTesting().letters.count == 1 }
        revoked = true
        await waitUntil { coordinator.snapshotForTesting().activation == .revoked }

        // Full offline reading: the complete body is still published.
        XCTAssertEqual(coordinator.snapshotForTesting().letters.first?.body, body)
        XCTAssertEqual(coordinator.snapshotForTesting().unread, 1)

        // No token: open confirmations are never submitted.
        coordinator.markOpened(letterID: id)
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(transport.openCalls.count, 0,
                       "a revoked device must never submit open confirmations")
    }

    func testNetworkFailureBacksOffThenRecovers() async throws {
        let (coordinator, transport, _) = makeHarness()
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        var fail = true
        transport.onFetch = { _, _, _ in
            if fail { throw BottleMailAPIError.network("offline") }
            return BottleMailPage(letters: [self.remote(1)], nextAfter: 1)
        }
        try await coordinator.activate(code: "C", label: "Mac")
        await waitUntil {
            coordinator.currentDelayForTesting() > coordinator.backoffBase
        }
        XCTAssertEqual(coordinator.snapshotForTesting().lastSyncError, "网络不可用")
        fail = false
        await waitUntil { coordinator.snapshotForTesting().letters.count == 1 }
        await waitUntil { coordinator.snapshotForTesting().lastSyncError == nil }
    }

    func testWakeAndNetworkRecoveryTriggerImmediatePolls() async throws {
        let (coordinator, transport, _) = makeHarness()
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        transport.onFetch = { after, _, _ in
            BottleMailPage(letters: [], nextAfter: after)
        }
        try await coordinator.activate(code: "C", label: "Mac")
        await waitUntil { transport.fetchCalls.count >= 1 }
        let before = transport.fetchCalls.count
        coordinator.handleWake()
        coordinator.handleNetworkRecovery()
        await waitUntil { transport.fetchCalls.count >= before + 2 }
    }

    // MARK: - Stale async results

    func testStaleInFlightPollIsDiscardedAfterReactivation() async throws {
        let (coordinator, transport, _) = makeHarness()
        transport.onActivate = { code, _ in
            BottleMailActivation(deviceId: "d-\(code)", deviceToken: "tok-\(code)", label: "Mac")
        }
        let gate = DispatchSemaphore(value: 0)
        var blocked = true
        var callCount = 0
        transport.onFetch = { after, _, _ in
            callCount += 1
            if blocked { gate.wait() }
            return after == 0
                ? BottleMailPage(letters: [self.remote(1)], nextAfter: 1)
                : BottleMailPage(letters: [], nextAfter: after)
        }
        try await coordinator.activate(code: "A", label: "Mac")
        await waitUntil { callCount == 1 } // first poll in flight (blocked)

        // Re-activate while the first poll is still in flight: the epoch
        // bumps, so the stale result must be discarded.
        try await coordinator.activate(code: "B", label: "Mac")
        blocked = false
        gate.signal()
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(coordinator.snapshotForTesting().letters.count, 0,
                       "stale poll letters must not be persisted")
        guard case .activated = coordinator.snapshotForTesting().activation else {
            return XCTFail("reactivation must stay activated")
        }
        // A fresh poll with the NEW token eventually runs.
        await waitUntil { transport.fetchCalls.contains { $0.token == "tok-B" } }
    }

    // MARK: - Read completion (local-first + async server reconciliation)

    func testServerPendingOpenSurvivesRestartAndResumesAutomatically() async throws {
        let (first, transport, credentials) = makeHarness()
        // Keep the retry timer out of the first session: the single
        // direct /open attempt from markOpened must fail, nothing else
        // may race the "restart".
        first.openRetryInterval = 600
        first.localOpenedAtProvider = { "LOCAL_STAMP" }
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        let id = UUID().uuidString
        var openShouldFail = true
        transport.onFetch = { after, _, _ in
            after == 0
                ? BottleMailPage(letters: [self.remote(1, id: id)], nextAfter: 1)
                : BottleMailPage(letters: [], nextAfter: after)
        }
        transport.onOpen = { _, _ in
            if openShouldFail { throw BottleMailAPIError.network("offline") }
            return "2026-10-17T01:00:00Z"
        }
        try await first.activate(code: "C", label: "Mac")
        await waitUntil { first.snapshotForTesting().letters.count == 1 }
        first.markOpened(letterID: id)
        await waitUntil { transport.openCalls.count >= 1 }
        // Local-first: the read completed even though the server was
        // unreachable; only the server reconciliation stays pending.
        XCTAssertEqual(first.snapshotForTesting().unread, 0)
        XCTAssertEqual(first.snapshotForTesting().letters.first?.openedAt, "LOCAL_STAMP")
        // The pending confirmation is persisted before the "restart".
        await waitUntil {
            self.makeStore().snapshot().pendingOpenIds.contains(id)
        }
        first.stop()

        // Restart: the pending /open is restored and re-submitted
        // automatically without any user action.
        openShouldFail = false
        let secondTransport = MockTransport()
        secondTransport.onFetch = { after, _, _ in
            BottleMailPage(letters: [], nextAfter: after)
        }
        secondTransport.onOpen = { _, _ in "2026-10-17T01:00:00Z" }
        let second = BottleMailCoordinator(
            transport: secondTransport,
            credentials: credentials,
            store: makeStore()
        )
        second.pollIntervalRange = 0.05...0.05
        second.openRetryInterval = 0.05
        second.delayProvider = { $0.lowerBound }
        second.start()
        // The initial published state is empty until start()'s queue
        // block publishes the restored mailbox — wait for that first.
        await waitUntil { second.snapshotForTesting().letters.count == 1 }
        await waitUntil { secondTransport.openCalls.count >= 1 }
        await waitUntil {
            second.snapshotForTesting().letters.first?.openedAt == "2026-10-17T01:00:00Z"
        }
        XCTAssertEqual(second.snapshotForTesting().letters.first?.openedAt, "2026-10-17T01:00:00Z",
                       "the server's opened_at replaces the local stamp on reconciliation")
    }

    func testConfirmedBacklogSurvivesRestartWithoutReopeningServerSide() async throws {
        let store = makeStore()
        let credentials = InMemoryBottleMailCredentialStore()
        let transport = MockTransport()
        let first = BottleMailCoordinator(
            transport: transport,
            credentials: credentials,
            store: store
        )
        first.pollIntervalRange = 0.05...0.05
        first.openRetryInterval = 600 // keep the auto-retry out of the way
        first.delayProvider = { $0.lowerBound }

        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        let id = UUID().uuidString
        transport.onFetch = { after, _, _ in
            after == 0
                ? BottleMailPage(letters: [self.remote(1, id: id)], nextAfter: 1)
                : BottleMailPage(letters: [], nextAfter: after)
        }
        var openCalls = 0
        transport.onOpen = { _, _ in
            openCalls += 1
            return "2026-10-17T01:00:00Z"
        }
        // Fail ONLY the confirmed-open local write (the letter with
        // openedAt set); the pending-state persist that runs before the
        // /open must succeed so the backlog is durably stored.
        var failLetterPersist = false
        store.persistOverride = { data, tempURL, fileURL in
            if failLetterPersist,
               let mailbox = try? JSONDecoder().decode(BottleMailMailbox.self, from: data),
               mailbox.letters.first?.openedAt != nil {
                throw CocoaError(.fileWriteUnknown)
            }
            try BottleMailFileStore.defaultPersist(data: data, tempURL: tempURL, fileURL: fileURL)
        }
        try await first.activate(code: "C", label: "Mac")
        await waitUntil { first.snapshotForTesting().letters.count == 1 }

        // Server confirms; the local write fails -> backlog persisted.
        failLetterPersist = true
        first.markOpened(letterID: id)
        await waitUntil { openCalls == 1 }
        await waitUntil {
            self.makeStore().snapshot().confirmedOpenBacklog[id] == "2026-10-17T01:00:00Z"
        }
        XCTAssertEqual(first.snapshotForTesting().unread, 1,
                       "the letter stays locally unread while the backlog is pending")
        first.stop()

        // Restart: the backlog is restored and flushed LOCALLY — the
        // server is never called again, and the original opened_at is
        // preserved exactly.
        let secondTransport = MockTransport()
        secondTransport.onFetch = { after, _, _ in
            BottleMailPage(letters: [], nextAfter: after)
        }
        secondTransport.onOpen = { _, _ in
            XCTFail("a restored confirmed backlog must not re-call /open")
            return "should-not-happen"
        }
        let second = BottleMailCoordinator(
            transport: secondTransport,
            credentials: credentials,
            store: makeStore()
        )
        second.pollIntervalRange = 0.05...0.05
        second.openRetryInterval = 0.05
        second.delayProvider = { $0.lowerBound }
        second.start()
        // Same ordering guard as the pending-open test: the restored
        // mailbox must be published before unread can be observed.
        await waitUntil { second.snapshotForTesting().letters.count == 1 }
        await waitUntil { second.snapshotForTesting().unread == 0 }
        XCTAssertEqual(second.snapshotForTesting().letters.first?.openedAt, "2026-10-17T01:00:00Z",
                       "the server's original opened_at is preserved")
        XCTAssertEqual(secondTransport.openCalls.count, 0)
    }

    func testOpenCompletesLocallyThenReconcilesWithServer() async throws {
        let (coordinator, transport, _) = makeHarness()
        coordinator.localOpenedAtProvider = { "LOCAL_STAMP" }
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        let id = UUID().uuidString
        var openShouldFail = true
        transport.onFetch = { after, _, _ in
            after == 0
                ? BottleMailPage(letters: [self.remote(1, id: id)], nextAfter: 1)
                : BottleMailPage(letters: [], nextAfter: after)
        }
        transport.onOpen = { _, _ in
            if openShouldFail { throw BottleMailAPIError.http(status: 500, code: "internal_error") }
            return "2026-10-17T01:00:00Z"
        }
        try await coordinator.activate(code: "C", label: "Mac")
        await waitUntil { coordinator.snapshotForTesting().letters.count == 1 }

        // Local-first: the read completes immediately even though the
        // server fails — the pet never waits on the network.
        coordinator.markOpened(letterID: id)
        await waitUntil { coordinator.snapshotForTesting().unread == 0 }
        XCTAssertEqual(coordinator.snapshotForTesting().letters.first?.isUnread, false)
        XCTAssertEqual(coordinator.snapshotForTesting().letters.first?.openedAt, "LOCAL_STAMP")
        await waitUntil { transport.openCalls.count >= 1 }

        // Network recovers: the pending /open reconciles and the server
        // timestamp replaces the local one.
        openShouldFail = false
        coordinator.handleNetworkRecovery()
        await waitUntil {
            coordinator.snapshotForTesting().letters.first?.openedAt == "2026-10-17T01:00:00Z"
        }
        XCTAssertGreaterThanOrEqual(transport.openCalls.count, 2,
                                    "the idempotent /open may be retried several times")
    }

    func testOpenRetriesAutomaticallyOnNetworkRecovery() async throws {
        let (coordinator, transport, _) = makeHarness()
        coordinator.localOpenedAtProvider = { "LOCAL_STAMP" }
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        let id = UUID().uuidString
        var openShouldFail = true
        transport.onFetch = { after, _, _ in
            after == 0
                ? BottleMailPage(letters: [self.remote(1, id: id)], nextAfter: 1)
                : BottleMailPage(letters: [], nextAfter: after)
        }
        transport.onOpen = { _, _ in
            if openShouldFail { throw BottleMailAPIError.network("offline") }
            return "2026-10-17T01:00:00Z"
        }
        try await coordinator.activate(code: "C", label: "Mac")
        await waitUntil { coordinator.snapshotForTesting().letters.count == 1 }

        coordinator.markOpened(letterID: id)
        await waitUntil { transport.openCalls.count >= 1 }
        XCTAssertEqual(coordinator.snapshotForTesting().unread, 0,
                       "local-first: the read completes while offline")
        XCTAssertEqual(coordinator.snapshotForTesting().letters.first?.openedAt, "LOCAL_STAMP")

        // Network comes back: the failed confirmation is re-submitted
        // WITHOUT the user pressing the button again.
        openShouldFail = false
        coordinator.handleNetworkRecovery()
        await waitUntil {
            coordinator.snapshotForTesting().letters.first?.openedAt == "2026-10-17T01:00:00Z"
        }
        XCTAssertGreaterThanOrEqual(transport.openCalls.count, 2,
                                    "the failed /open is automatically re-submitted")
    }

    func testServerConfirmedButLocalPersistFailedRecovers() async throws {
        let (coordinator, transport, _) = makeHarness()
        let store = makeStore()
        let credentials = InMemoryBottleMailCredentialStore()
        let failingCoordinator = BottleMailCoordinator(
            transport: transport,
            credentials: credentials,
            store: store
        )
        failingCoordinator.pollIntervalRange = 0.05...0.05
        failingCoordinator.backoffBase = 0.01
        failingCoordinator.backoffMax = 0.5
        failingCoordinator.pendingDeliveryRetryInterval = 0.05
        failingCoordinator.openRetryInterval = 0.05
        failingCoordinator.delayProvider = { $0.lowerBound }

        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        let id = UUID().uuidString
        transport.onFetch = { after, _, _ in
            after == 0
                ? BottleMailPage(letters: [self.remote(1, id: id)], nextAfter: 1)
                : BottleMailPage(letters: [], nextAfter: after)
        }
        var openCalls = 0
        transport.onOpen = { _, _ in
            openCalls += 1
            return "2026-10-17T01:00:00Z"
        }
        // First local persist fails once, then works.
        var failNextPersist = false
        store.persistOverride = { data, tempURL, fileURL in
            if failNextPersist { throw CocoaError(.fileWriteUnknown) }
            try BottleMailFileStore.defaultPersist(data: data, tempURL: tempURL, fileURL: fileURL)
        }

        try await failingCoordinator.activate(code: "C", label: "Mac")
        await waitUntil { failingCoordinator.snapshotForTesting().letters.count == 1 }

        failNextPersist = true
        failingCoordinator.markOpened(letterID: id)
        await waitUntil { openCalls >= 1 }
        XCTAssertEqual(failingCoordinator.snapshotForTesting().unread, 1,
                       "server confirmed but local write failed: stays unread until retried")

        failNextPersist = false
        failingCoordinator.handleNetworkRecovery()
        await waitUntil { failingCoordinator.snapshotForTesting().unread == 0 }
        XCTAssertEqual(failingCoordinator.snapshotForTesting().letters.first?.openedAt, "2026-10-17T01:00:00Z")
        XCTAssertEqual(openCalls, 1,
                       "a server-confirmed open retries the LOCAL write, not the /open call")
    }

    // MARK: - Main-thread publishing

    func testPublishedUpdatesArriveOnTheMainThread() async throws {
        let (coordinator, transport, _) = makeHarness()
        transport.onActivate = { _, _ in
            BottleMailActivation(deviceId: "d", deviceToken: "tok", label: "Mac")
        }
        transport.onFetch = { after, _, _ in
            after == 0
                ? BottleMailPage(letters: [self.remote(1)], nextAfter: 1)
                : BottleMailPage(letters: [], nextAfter: after)
        }
        let expectation = expectation(description: "letters published")
        var receivedOnMain = false
        var subscription: AnyCancellable?
        subscription = coordinator.$letters.sink { updated in
            if !updated.isEmpty {
                receivedOnMain = Thread.isMainThread
                expectation.fulfill()
            }
        }
        try await coordinator.activate(code: "C", label: "Mac")
        await fulfillment(of: [expectation], timeout: 5)
        XCTAssertTrue(receivedOnMain, "@Published mutations must run on the main thread")
        _ = subscription
    }
}
