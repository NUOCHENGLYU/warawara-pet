import AppKit
import Combine
import Foundation
import Network

/// Owns device activation, polling, persistence and the ordered pending
/// delivery queue. Never touches AppKit directly: the UI (Phase 8C) and
/// the 8B status window observe the published state. Letters are
/// persisted BEFORE being delivered to the UI queue, so a crash can
/// never lose mail. Syncing never marks anything read.
final class BottleMailCoordinator: ObservableObject {
    // MARK: - Published state (UI-facing)

    @Published private(set) var activationState: BottleMailActivationState = .notActivated
    @Published private(set) var letters: [BottleMailLetter] = []
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var pendingDeliveryCount: Int = 0
    @Published private(set) var lastSyncError: String?
    @Published private(set) var lastSyncAt: Date?

    /// Convenience for UI state checks.
    var isActivated: Bool {
        if case .activated = activationState { return true }
        return false
    }

    // MARK: - Dependencies (injectable for tests)

    let transport: BottleMailAPITransport
    let credentials: BottleMailCredentialStoring
    let store: BottleMailStoring
    /// Conflict gate: dragging / sleeping / birthday / meteor / letter
    /// window / group sequence. While true, fetched mail waits in the
    /// pending queue instead of interrupting the pet.
    var isPetBusy: () -> Bool = { false }
    /// Poll cadence after a successful sync (20–30 s per spec).
    var pollIntervalRange: ClosedRange<TimeInterval> = 20...30
    var backoffBase: TimeInterval = 5
    var backoffMax: TimeInterval = 300
    /// How often a busy-gated pending queue retries delivery (tests
    /// shrink this; production keeps 2 s).
    var pendingDeliveryRetryInterval: TimeInterval = 2
    /// Injected delay picker so tests are deterministic.
    var delayProvider: (ClosedRange<TimeInterval>) -> TimeInterval = { TimeInterval.random(in: $0) }

    // MARK: - Internals

    private let queue = DispatchQueue(label: "warawarapet.bottlemail.coordinator")
    private var timer: DispatchSourceTimer?
    private var pendingLetters: [BottleMailLetter] = []
    private var pendingDeliveryTimer: DispatchSourceTimer?
    private var isPolling = false
    private var credential: BottleMailCredential?
    private var networkMonitor: NWPathMonitor?
    private var lastNetworkUp = true
    private(set) var currentPollDelay: TimeInterval = 0

    init(
        transport: BottleMailAPITransport,
        credentials: BottleMailCredentialStoring,
        store: BottleMailStoring
    ) {
        self.transport = transport
        self.credentials = credentials
        self.store = store
    }

    // MARK: - Lifecycle

    /// Loads the mailbox + credential, then either starts polling or
    /// exposes the not-activated state. Safe to call multiple times.
    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            let mailbox = self.store.snapshot()
            self.publishLetters(mailbox)
            if let credential = self.credentials.loadCredential() {
                self.credential = credential
                self.updateActivation(.activated(label: credential.label))
                self.scheduleNextPoll(delay: 0.5)
            } else {
                self.updateActivation(.notActivated)
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.cancelTimers()
        }
    }

    // MARK: - Activation

    /// One-time device activation with a code generated on the sender
    /// page. Success stores the token in the Keychain and starts polling.
    func activate(code: String, label: String) async throws {
        updateActivation(.activating)
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let result: BottleMailActivation
        do {
            result = try await transport.activate(code: trimmedCode, label: label)
        } catch let error as BottleMailAPIError {
            let mapped = Self.mapActivationError(error)
            updateActivation(.notActivated)
            EventDiagnostics.bottleMail("ACTIVATE_FAILED", details: "reason=\(mapped)")
            throw mapped
        } catch {
            updateActivation(.notActivated)
            EventDiagnostics.bottleMail("ACTIVATE_FAILED", details: "reason=unknown")
            throw BottleMailActivationError.network(error.localizedDescription)
        }
        let credential = BottleMailCredential(
            deviceId: result.deviceId,
            token: result.deviceToken,
            label: result.label
        )
        do {
            try credentials.saveCredential(credential)
        } catch {
            updateActivation(.notActivated)
            EventDiagnostics.bottleMail("CREDENTIAL_SAVE_FAILED")
            throw BottleMailActivationError.server("credential-save")
        }
        queue.async { [weak self] in
            guard let self else { return }
            self.credential = credential
            self.updateActivation(.activated(label: result.label))
            self.scheduleNextPoll(delay: 0.5)
        }
        EventDiagnostics.bottleMail("ACTIVATED", details: "labelChars=\(result.label.count)")
    }

    private static func mapActivationError(_ error: BottleMailAPIError) -> BottleMailActivationError {
        switch error {
        case .http(let status, let code):
            switch (status, code) {
            case (409, _): return .codeUsed
            case (410, _): return .codeExpired
            case (401, _), (400, _): return .invalidCode
            default: return .server("http-\(status)")
            }
        case .network(let reason): return .network(reason)
        case .decoding, .invalidResponse: return .server("bad-response")
        }
    }

    // MARK: - External triggers (launch / wake / network recovery)

    func handleWake() {
        EventDiagnostics.bottleMail("WAKE_TRIGGER")
        scheduleNextPoll(delay: 0.5)
    }

    func handleNetworkRecovery() {
        EventDiagnostics.bottleMail("NETWORK_RECOVERED")
        scheduleNextPoll(delay: 0.5)
    }

    /// Installs NSWorkspace wake + NWPathMonitor hooks. Called by
    /// AppDelegate once.
    func installLifecycleHooks() {
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.handleWake()
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let isUp = path.status == .satisfied
            if isUp && !self.lastNetworkUp {
                self.lastNetworkUp = true
                self.handleNetworkRecovery()
            } else if !isUp {
                self.lastNetworkUp = false
            }
        }
        monitor.start(queue: queue)
        networkMonitor = monitor
    }

    // MARK: - Polling

    func pollNow() {
        scheduleNextPoll(delay: 0.1)
    }

    private func scheduleNextPoll(delay: TimeInterval) {
        queue.async { [weak self] in
            guard let self else { return }
            self.cancelTimer()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + delay)
            timer.setEventHandler { [weak self] in
                self?.performPoll()
            }
            timer.resume()
            self.timer = timer
        }
    }

    private func performPoll() {
        guard !isPolling else { return }
        guard let credential else {
            updateActivation(.notActivated)
            return
        }
        isPolling = true
        let snapshotBefore = store.snapshot()
        Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await self.transport.fetchLetters(
                    after: snapshotBefore.cursorSeq,
                    limit: 50,
                    token: credential.token
                )
                self.handlePollSuccess(page: page)
            } catch let error as BottleMailAPIError {
                self.handlePollFailure(error)
            } catch {
                self.handlePollFailure(.network(error.localizedDescription))
            }
        }
    }

    private func handlePollSuccess(page: BottleMailPage) {
        queue.async { [weak self] in
            guard let self else { return }
            self.isPolling = false
            do {
                let mergeResult = try self.store.merge(
                    remote: page.letters,
                    advancingCursorTo: page.nextAfter
                )
                self.currentPollDelay = self.delayProvider(self.pollIntervalRange)
                self.lastSyncError = nil
                self.lastSyncAt = Date()
                if mergeResult.newLetters.count > 0 {
                    EventDiagnostics.bottleMail(
                        "SYNCED",
                        details: "new=\(mergeResult.newLetters.count) dup=\(mergeResult.duplicateCount)"
                    )
                    self.pendingLetters.append(contentsOf: mergeResult.newLetters)
                    self.deliverPendingIfFree()
                }
                self.scheduleNextPoll(delay: self.currentPollDelay)
            } catch {
                self.handlePollFailure(.network("store-write"))
            }
        }
    }

    private func handlePollFailure(_ error: BottleMailAPIError) {
        queue.async { [weak self] in
            guard let self else { return }
            self.isPolling = false
            if case .http(let status, _) = error, status == 401 {
                self.handleRevocation()
                return
            }
            self.currentPollDelay = min(self.currentPollDelay * 2, self.backoffMax)
            if self.currentPollDelay <= self.backoffBase {
                self.currentPollDelay = self.backoffBase
            }
            let message = Self.describe(error)
            let delay = self.currentPollDelay
            self.lastSyncError = message
            EventDiagnostics.bottleMail("POLL_FAILED", details: "retry=\(Int(delay))s")
            self.scheduleNextPoll(delay: delay)
        }
    }

    private func handleRevocation() {
        // The sender revoked this device: stop using the old token and
        // stop polling, but KEEP the mailbox — received letters remain
        // readable. The user can re-activate with a new code.
        credential = nil
        credentials.clearCredential()
        cancelTimers()
        updateActivation(.revoked)
        lastSyncError = nil
        EventDiagnostics.bottleMail("DEVICE_REVOKED")
    }

    private static func describe(_ error: BottleMailAPIError) -> String {
        switch error {
        case .network: return "网络不可用"
        case .http(let status, _): return "服务器错误 \(status)"
        case .decoding, .invalidResponse: return "响应异常"
        }
    }

    // MARK: - Pending delivery (busy gate)

    /// Moves fetched mail into the UI queue only while the pet is free.
    private func deliverPendingIfFree() {
        guard !pendingLetters.isEmpty else { return }
        if isPetBusy() {
            publishPendingCount()
            schedulePendingDeliveryRetry()
            return
        }
        pendingLetters.removeAll()
        pendingDeliveryCount = 0
        cancelPendingDeliveryTimer()
        publishLetters(store.snapshot())
        EventDiagnostics.bottleMail("DELIVERED")
    }

    private func schedulePendingDeliveryRetry() {
        guard pendingDeliveryTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + pendingDeliveryRetryInterval,
            repeating: pendingDeliveryRetryInterval
        )
        timer.setEventHandler { [weak self] in
            self?.deliverPendingIfFree()
        }
        timer.resume()
        pendingDeliveryTimer = timer
    }

    private func publishPendingCount() {
        let count = pendingLetters.count
        queue.async { [weak self] in
            self?.pendingDeliveryCount = count
        }
    }

    // MARK: - Opening (read confirmation)

    /// Marks a letter opened: the LOCAL state changes only after the
    /// server confirms. On failure the letter stays unread and is
    /// retried on the next poll cycle.
    func markOpened(letterID: String) {
        guard let credential else { return }
        let token = credential.token
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.transport.markOpened(id: letterID, token: token)
                let openedAt = ISO8601DateFormatter().string(from: Date())
                try self.store.markOpenedLocally(id: letterID, openedAt: openedAt)
                self.queue.async {
                    self.publishLetters(self.store.snapshot())
                }
                EventDiagnostics.bottleMail("OPENED", details: "id=\(letterID)")
            } catch {
                // Keep unread; the poll loop re-fetches and the letter
                // remains visible until a later /open succeeds.
                EventDiagnostics.bottleMail("OPEN_FAILED", details: "id=\(letterID)")
            }
        }
    }

    /// Thread-safe state read for tests and diagnostics (all published
    /// state is written on the coordinator queue).
    func snapshotForTesting() -> (
        letters: [BottleMailLetter],
        unread: Int,
        pending: Int,
        activation: BottleMailActivationState,
        lastSyncError: String?
    ) {
        queue.sync {
            (letters: letters, unread: unreadCount, pending: pendingDeliveryCount,
             activation: activationState, lastSyncError: lastSyncError)
        }
    }

    /// Thread-safe delay read for tests/diagnostics.
    func currentDelayForTesting() -> TimeInterval {
        queue.sync { currentPollDelay }
    }

    // MARK: - UI plumbing

    private func publishLetters(_ mailbox: BottleMailMailbox) {
        let letters = mailbox.letters
        let unread = letters.filter(\.isUnread).count
        queue.async { [weak self] in
            guard let self else { return }
            self.letters = letters
            self.unreadCount = unread
        }
    }

    private func updateActivation(_ state: BottleMailActivationState) {
        queue.async { [weak self] in
            self?.activationState = state
        }
    }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
    }

    private func cancelPendingDeliveryTimer() {
        pendingDeliveryTimer?.cancel()
        pendingDeliveryTimer = nil
    }

    private func cancelTimers() {
        cancelTimer()
        cancelPendingDeliveryTimer()
    }

    /// Debug CLI/status text — never includes tokens or letter bodies.
    func debugDump() -> String {
        let mailbox = store.snapshot()
        let unread = mailbox.letters.filter(\.isUnread).count
        return [
            "BOTTLE_MAIL_DIAGNOSE",
            "activation=\(activationState)",
            "letters=\(mailbox.letters.count)",
            "unread=\(unread)",
            "cursor=\(mailbox.cursorSeq)",
            "pending=\(pendingLetters.count)",
            "pollDelay=\(Int(currentPollDelay))s",
        ].joined(separator: " ")
    }
}
