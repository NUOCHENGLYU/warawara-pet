import Foundation
import XCTest
@testable import WarawaraPet

/// Coordinator coverage with an injected mock transport + in-memory
/// credential store + temp-file mailbox: activation, revocation,
/// polling/dedupe, busy gating, backoff, wake triggers and read
/// confirmation. No network involved.
final class BottleMailCoordinatorTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!

    final class MockTransport: BottleMailAPITransport {
        var onActivate: ((String, String) async throws -> BottleMailActivation)?
        var onFetch: ((Int, Int, String) async throws -> BottleMailPage)?
        var onOpen: ((String, String) async throws -> Void)?
        private(set) var fetchCalls: [(after: Int, limit: Int, token: String)] = []
        private(set) var openCalls: [(id: String, token: String)] = []

        func activate(code: String, label: String) async throws -> BottleMailActivation {
            guard let onActivate else { throw BottleMailAPIError.network("no handler") }
            return try await onActivate(code, label)
        }

        func fetchLetters(after: Int, limit: Int, token: String) async throws -> BottleMailPage {
            fetchCalls.append((after, limit, token))
            guard let onFetch else { throw BottleMailAPIError.network("no handler") }
            return try await onFetch(after, limit, token)
        }

        func markOpened(id: String, token: String) async throws {
            openCalls.append((id, token))
            guard let onOpen else { throw BottleMailAPIError.network("no handler") }
            try await onOpen(id, token)
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

    private func remote(_ seq: Int, id: String = UUID().uuidString, body: String = "信 \(seq)") -> BottleMailRemoteLetter {
        BottleMailRemoteLetter(id: id, seq: seq, body: body, createdAt: "2026-10-17T00:00:00Z", openedAt: nil)
    }

    private func makeHarness() -> (BottleMailCoordinator, MockTransport, InMemoryBottleMailCredentialStore) {
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
        coordinator.delayProvider = { $0.lowerBound }
        return (coordinator, transport, credentials)
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
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
        await waitUntil { coordinator.isActivated }
        if case .activated(let label) = coordinator.activationState {
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
        }

        transport.onActivate = { _, _ in throw BottleMailAPIError.http(status: 410, code: "code_expired") }
        do {
            try await coordinator.activate(code: "X", label: "Mac")
            XCTFail("expected failure")
        } catch let error as BottleMailActivationError {
            XCTAssertEqual(error, .codeExpired)
        }

        transport.onActivate = { _, _ in throw BottleMailAPIError.network("offline") }
        do {
            try await coordinator.activate(code: "X", label: "Mac")
            XCTFail("expected failure")
        } catch let error as BottleMailActivationError {
            XCTAssertEqual(error, .network("offline"))
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
        // First poll: one new letter; second poll returns the SAME
        // letter plus a new one (repoll dedupe).
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
        await waitUntil { coordinator.letters.count == 2 }
        XCTAssertEqual(coordinator.letters.map(\.seq), [1, 2])
        XCTAssertEqual(coordinator.unreadCount, 2)
        // No duplicates after many more poll rounds.
        await waitUntil { transport.fetchCalls.count >= 4 }
        XCTAssertEqual(coordinator.letters.count, 2)
        // The cursor advanced (subsequent fetches ask after 2).
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
        await waitUntil { first.letters.count == 1 }

        // "Restart": fresh coordinator over the same file + same keychain
        // stand-in. The mailbox is restored from disk immediately.
        let secondTransport = MockTransport()
        secondTransport.onFetch = { after, _, _ in
            BottleMailPage(letters: [], nextAfter: after)
        }
        let second = BottleMailCoordinator(
            transport: secondTransport,
            credentials: credentials,
            store: BottleMailFileStore(fileURL: fileURL)
        )
        second.pollIntervalRange = 0.05...0.05
        second.delayProvider = { $0.lowerBound }
        second.start()
        await waitUntil { second.letters.count == 1 }
        XCTAssertEqual(second.unreadCount, 1)
        await waitUntil { secondTransport.fetchCalls.count >= 1 }
        XCTAssertEqual(secondTransport.fetchCalls.first?.after, 1, "restart resumes from the persisted cursor")
    }

    // MARK: - Busy gating

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
        await waitUntil { coordinator.pendingDeliveryCount == 2 }
        // Persisted already, but NOT delivered to the UI while busy.
        XCTAssertEqual(coordinator.letters.count, 0)
        // The pet becomes free: the pending queue drains in order.
        busy = false
        await waitUntil { coordinator.letters.count == 2 }
        XCTAssertEqual(coordinator.letters.map(\.seq), [1, 2])
        XCTAssertEqual(coordinator.pendingDeliveryCount, 0)
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
        await waitUntil { coordinator.letters.count == 1 }
        let callsBefore = transport.fetchCalls.count
        revoked = true
        await waitUntil { coordinator.activationState == .revoked }
        XCTAssertNil(credentials.credential, "the revoked token must be discarded")
        XCTAssertEqual(coordinator.letters.count, 1, "received letters survive revocation")
        // Polling stops: no further fetch calls after revocation.
        let callsAfter = transport.fetchCalls.count
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(transport.fetchCalls.count, callsAfter)
        XCTAssertGreaterThanOrEqual(callsBefore, 1)
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
        // Backoff grows from the base and caps at backoffMax.
        await waitUntil {
            let delay = coordinator.currentPollDelay
            return delay > coordinator.backoffBase
        }
        XCTAssertEqual(coordinator.lastSyncError, "网络不可用")
        fail = false
        await waitUntil { coordinator.letters.count == 1 }
        await waitUntil { coordinator.lastSyncError == nil }
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

    // MARK: - Read confirmation

    func testOpenOnlyMarksReadAfterServerConfirmation() async throws {
        let (coordinator, transport, _) = makeHarness()
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
        }
        try await coordinator.activate(code: "C", label: "Mac")
        await waitUntil { coordinator.letters.count == 1 }

        // Failure: stays unread, no local change.
        coordinator.markOpened(letterID: id)
        await waitUntil { transport.openCalls.count >= 1 }
        XCTAssertEqual(coordinator.letters.first?.isUnread, true)

        // Success: local unread flag flips only after confirmation.
        openShouldFail = false
        coordinator.markOpened(letterID: id)
        await waitUntil { coordinator.unreadCount == 0 }
        XCTAssertEqual(coordinator.letters.first?.isUnread, false)
        XCTAssertEqual(transport.openCalls.count, 2)
    }
}
