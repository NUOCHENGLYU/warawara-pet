import AppKit
import Combine
import Foundation
import Network

/// Owns device activation, polling, persistence, read-confirmation
/// retries and the consumable delivery queue (Phase 8C consumes the
/// queue; this phase only provides the data/event interface).
///
/// THREADING CONTRACT:
/// - Every `@Published` mutation happens on the MAIN thread (SwiftUI).
/// - File I/O and network run off the main thread (store queue /
///   URLSession).
/// - The internal serial `queue` owns orchestration state (credential,
///   epochs, pending queues) and submits main-thread updates in a
///   deterministic order; an epoch counter discards stale async results
///   (e.g. an in-flight poll finishing after a revocation).
/// - `isPetBusy` is evaluated on the main thread.
final class BottleMailCoordinator: ObservableObject {
    // MARK: - Published state (main thread only)

    @Published private(set) var activationState: BottleMailActivationState = .notActivated
    @Published private(set) var letters: [BottleMailLetter] = []
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var pendingDeliveryCount: Int = 0
    @Published private(set) var lastSyncError: String?
    @Published private(set) var lastSyncAt: Date?
    /// The consumable per-letter delivery queue (FIFO by seq). A letter
    /// is removed ONLY via `acknowledgeDelivery(id:)`.
    @Published private(set) var deliveryQueue: [PendingBottleDelivery] = []

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
    /// window / group sequence. Evaluated on the MAIN thread.
    var isPetBusy: () -> Bool = { false }
    /// Poll cadence after a successful sync (20–30 s per spec).
    var pollIntervalRange: ClosedRange<TimeInterval> = 20...30
    var backoffBase: TimeInterval = 5
    var backoffMax: TimeInterval = 300
    /// How often failed /open confirmations are retried.
    var openRetryInterval: TimeInterval = 60
    /// How often a busy-gated pending queue retries delivery.
    var pendingDeliveryRetryInterval: TimeInterval = 2
    /// Injected delay picker so tests are deterministic.
    var delayProvider: (ClosedRange<TimeInterval>) -> TimeInterval = { TimeInterval.random(in: $0) }

    // MARK: - Internals (orchestration queue only)

    private let queue = DispatchQueue(label: "warawarapet.bottlemail.coordinator")
    private var timer: DispatchSourceTimer?
    private var pendingDeliveryTimer: DispatchSourceTimer?
    private var openRetryTimer: DispatchSourceTimer?
    private var isPolling = false
    private var epoch = 0
    private var credential: BottleMailCredential?
    private var pendingLetters: [BottleMailLetter] = []
    /// Server-confirmed opens whose LOCAL persist failed (id -> openedAt).
    private var localConfirmBacklog: [String: String] = [:]
    /// /open calls that failed server-side; retried on the next
    /// suitable moment (idempotent server-side).
    private var serverOpenRetries: Set<String> = []
    private var networkMonitor: NWPathMonitor?
    private var lastNetworkUp = true
    /// Queue-local mirror of the last published activation state (avoids
    /// any main-thread sync from the orchestration queue).
    private var localActivation: BottleMailActivationState = .notActivated
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

    /// Loads the mailbox + credential, restores the undelivered-queue,
    /// then either starts polling or exposes the not-activated state.
    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.epoch += 1
            let mailbox = self.store.snapshot()
            self.publishLetters(mailbox)
            // Restart rule: letters that were persisted but never
            // acknowledged are re-enqueued exactly once (delivered
            // letters stay out).
            let undelivered = mailbox.letters
                .filter { $0.isUnread && !$0.delivered }
                .sorted { $0.seq < $1.seq }
            self.pendingLetters = undelivered
            if let credential = self.credentials.loadCredential() {
                self.credential = credential
                self.publishActivation(.activated(label: credential.label))
                self.scheduleNextPoll(delay: 0.5)
            } else if mailbox.isRevoked {
                // Revoked before the restart: keep the letters readable,
                // never sync, keep the revoked state (wake/network
                // events must not erase it).
                self.credential = nil
                self.publishActivation(.revoked)
            } else {
                self.credential = nil
                self.publishActivation(.notActivated)
            }
            self.deliverPendingIfFree()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.epoch += 1
            self.cancelTimers()
        }
    }

    // MARK: - Activation

    /// One-time device activation with a code generated on the sender
    /// page. Success stores the token in the Keychain and starts polling.
    func activate(code: String, label: String) async throws {
        publishActivation(.activating)
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let result: BottleMailActivation
        do {
            result = try await transport.activate(code: trimmedCode, label: label)
        } catch let error as BottleMailAPIError {
            let mapped = Self.mapActivationError(error)
            publishActivation(.notActivated)
            EventDiagnostics.bottleMail("ACTIVATE_FAILED", details: "reason=\(mapped)")
            throw mapped
        } catch {
            publishActivation(.notActivated)
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
            publishActivation(.notActivated)
            EventDiagnostics.bottleMail("CREDENTIAL_SAVE_FAILED")
            throw BottleMailActivationError.server("credential-save")
        }
        queue.async { [weak self] in
            guard let self else { return }
            self.epoch += 1
            self.credential = credential
            self.serverOpenRetries.removeAll()
            self.localConfirmBacklog.removeAll()
            try? self.store.setRevokedFlag(false)
            self.publishActivation(.activated(label: result.label))
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
        retryPendingOpens()
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
            // No token: never sync. If the user is revoked, keep that
            // state — wake/network events must not erase it.
            if case .revoked = localActivation { return }
            publishActivation(.notActivated)
            return
        }
        isPolling = true
        let pollEpoch = epoch
        let snapshotBefore = store.snapshot()
        let token = credential.token
        Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await self.transport.fetchLetters(
                    after: snapshotBefore.cursorSeq,
                    limit: 50,
                    token: token
                )
                self.handlePollSuccess(page: page, pollEpoch: pollEpoch)
            } catch let error as BottleMailAPIError {
                self.handlePollFailure(error, pollEpoch: pollEpoch)
            } catch {
                self.handlePollFailure(.network(error.localizedDescription), pollEpoch: pollEpoch)
            }
        }
    }

    private func handlePollSuccess(page: BottleMailPage, pollEpoch: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            self.isPolling = false
            guard pollEpoch == self.epoch, self.credential != nil else {
                // Stale result (revoked/re-activated in between):
                // discard — it must not touch the current state.
                return
            }
            do {
                let mergeResult = try self.store.merge(
                    remote: page.letters,
                    advancingCursorTo: page.nextAfter
                )
                self.currentPollDelay = self.delayProvider(self.pollIntervalRange)
                self.publishSyncError(nil)
                self.publishSyncTime(Date())
                if mergeResult.newLetters.count > 0 {
                    EventDiagnostics.bottleMail(
                        "SYNCED",
                        details: "new=\(mergeResult.newLetters.count) dup=\(mergeResult.duplicateCount)"
                    )
                    self.pendingLetters.append(contentsOf: mergeResult.newLetters)
                    self.deliverPendingIfFree()
                }
                self.retryPendingOpens()
                self.scheduleNextPoll(delay: self.currentPollDelay)
            } catch {
                self.handlePollFailure(.network("store-write"), pollEpoch: pollEpoch)
            }
        }
    }

    private func handlePollFailure(_ error: BottleMailAPIError, pollEpoch: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            self.isPolling = false
            guard pollEpoch == self.epoch else { return }
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
            self.publishSyncError(message)
            EventDiagnostics.bottleMail("POLL_FAILED", details: "retry=\(Int(delay))s")
            self.scheduleNextPoll(delay: delay)
        }
    }

    private func handleRevocation() {
        // The sender revoked this device: stop using the old token and
        // stop polling, but KEEP the mailbox — received letters remain
        // readable offline. Re-activation binds a new device.
        credential = nil
        credentials.clearCredential()
        serverOpenRetries.removeAll()
        localConfirmBacklog.removeAll()
        try? store.setRevokedFlag(true)
        cancelTimers()
        publishActivation(.revoked)
        publishSyncError(nil)
        EventDiagnostics.bottleMail("DEVICE_REVOKED")
    }

    private static func describe(_ error: BottleMailAPIError) -> String {
        switch error {
        case .network: return "网络不可用"
        case .http(let status, _): return "服务器错误 \(status)"
        case .decoding, .invalidResponse: return "响应异常"
        }
    }

    // MARK: - Pending delivery (busy gate + consumable queue)

    /// Moves fetched mail into the published delivery queue only while
    /// the pet is free. `isPetBusy` is evaluated on the MAIN thread.
    private func deliverPendingIfFree() {
        guard !pendingLetters.isEmpty else { return }
        let captured = pendingLetters
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let busy = self.isPetBusy()
            self.queue.async {
                guard captured == self.pendingLetters else { return }
                if busy {
                    self.publishPendingCount(self.pendingLetters.count)
                    self.schedulePendingDeliveryRetry()
                } else {
                    self.pendingLetters.removeAll()
                    self.cancelPendingDeliveryTimer()
                    self.publishDeliveryQueue(
                        self.deliveryQueue
                            + captured.map { PendingBottleDelivery(id: $0.id, letter: $0) }
                    )
                    self.publishPendingCount(0)
                    self.publishLetters(self.store.snapshot())
                    EventDiagnostics.bottleMail("DELIVERED", details: "count=\(captured.count)")
                }
            }
        }
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

    /// The 8C consumption hook: removes one letter from the delivery
    /// queue AND persists the acknowledgement (exactly-once across
    /// restarts). Never throws to the UI; persistence failure keeps the
    /// letter queued so it is retried on the next start.
    func acknowledgeDelivery(_ deliveryID: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let index = self.deliveryQueue.firstIndex(where: { $0.id == deliveryID }) else { return }
            let delivery = self.deliveryQueue[index]
            do {
                try self.store.markDeliveredLocally(id: delivery.letter.id)
                var queue = self.deliveryQueue
                queue.remove(at: index)
                self.publishDeliveryQueue(queue)
                EventDiagnostics.bottleMail("DELIVERY_ACK", details: "id=\(delivery.letter.id)")
            } catch {
                // Persist failed: keep it queued; it will be re-delivered
                // on restart (delivered stays false).
                EventDiagnostics.bottleMail("DELIVERY_ACK_FAILED", details: "id=\(delivery.letter.id)")
            }
        }
    }

    // MARK: - Opening (read confirmation with automatic retry)

    /// Marks a letter opened: the LOCAL state changes only after the
    /// server confirms. Server failures are retried automatically on the
    /// next suitable moment (network recovery, successful poll, retry
    /// timer); a server-confirmed open whose local persist failed is
    /// also retried locally (server /open is idempotent).
    func markOpened(letterID: String) {
        queue.async { [weak self] in
            guard let self, self.credential != nil else { return }
            self.serverOpenRetries.insert(letterID)
            self.retryPendingOpens()
        }
    }

    private func retryPendingOpens() {
        guard !serverOpenRetries.isEmpty || !localConfirmBacklog.isEmpty else { return }
        let localBacklog = localConfirmBacklog
        localConfirmBacklog.removeAll()
        for (id, openedAt) in localBacklog {
            do {
                try store.markOpenedLocally(id: id, openedAt: openedAt)
                publishLetters(store.snapshot())
                EventDiagnostics.bottleMail("OPEN_PERSISTED", details: "id=\(id)")
            } catch {
                localConfirmBacklog[id] = openedAt
            }
        }
        guard !serverOpenRetries.isEmpty else {
            scheduleOpenRetryTimerIfNeeded()
            return
        }
        let retries = serverOpenRetries
        guard let credential else { return }
        let token = credential.token
        Task { [weak self] in
            guard let self else { return }
            for id in retries {
                do {
                    let openedAt = try await self.transport.markOpened(id: id, token: token)
                        ?? ISO8601DateFormatter().string(from: Date())
                    self.queue.async {
                        self.serverOpenRetries.remove(id)
                        do {
                            try self.store.markOpenedLocally(id: id, openedAt: openedAt)
                            self.publishLetters(self.store.snapshot())
                            EventDiagnostics.bottleMail("OPENED", details: "id=\(id)")
                        } catch {
                            // Server confirmed but the local write failed:
                            // keep it in the backlog and retry later.
                            self.localConfirmBacklog[id] = openedAt
                            EventDiagnostics.bottleMail("OPEN_PERSIST_FAILED", details: "id=\(id)")
                        }
                        self.scheduleOpenRetryTimerIfNeeded()
                    }
                } catch {
                    // Keep in serverOpenRetries; retried on the next
                    // suitable moment.
                    EventDiagnostics.bottleMail("OPEN_FAILED", details: "id=\(id)")
                }
            }
            self.scheduleOpenRetryTimerIfNeeded()
        }
    }

    private func scheduleOpenRetryTimerIfNeeded() {
        queue.async { [weak self] in
            guard let self else { return }
            self.openRetryTimer?.cancel()
            self.openRetryTimer = nil
            guard !self.serverOpenRetries.isEmpty || !self.localConfirmBacklog.isEmpty else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(
                deadline: .now() + self.openRetryInterval,
                repeating: self.openRetryInterval
            )
            timer.setEventHandler { [weak self] in
                self?.retryPendingOpens()
            }
            timer.resume()
            self.openRetryTimer = timer
        }
    }

    // MARK: - Main-thread publishing (deterministic ordering)

    private func publishActivation(_ state: BottleMailActivationState) {
        queue.async { [weak self] in
            self?.localActivation = state
        }
        DispatchQueue.main.async { [weak self] in
            self?.activationState = state
        }
    }

    private func publishLetters(_ mailbox: BottleMailMailbox) {
        let letters = mailbox.letters
        let unread = letters.filter(\.isUnread).count
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.letters = letters
            self.unreadCount = unread
        }
    }

    private func publishSyncError(_ error: String?) {
        DispatchQueue.main.async { [weak self] in
            self?.lastSyncError = error
        }
    }

    private func publishSyncTime(_ date: Date) {
        DispatchQueue.main.async { [weak self] in
            self?.lastSyncAt = date
        }
    }

    private func publishPendingCount(_ count: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.pendingDeliveryCount = count
        }
    }

    private func publishDeliveryQueue(_ queueContents: [PendingBottleDelivery]) {
        DispatchQueue.main.async { [weak self] in
            self?.deliveryQueue = queueContents
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
        openRetryTimer?.cancel()
        openRetryTimer = nil
    }

    /// Thread-safe state read for tests and diagnostics.
    func snapshotForTesting() -> (
        letters: [BottleMailLetter],
        unread: Int,
        pending: Int,
        deliveryQueue: [PendingBottleDelivery],
        activation: BottleMailActivationState,
        lastSyncError: String?
    ) {
        func read() -> (letters: [BottleMailLetter], unread: Int, pending: Int, deliveryQueue: [PendingBottleDelivery], activation: BottleMailActivationState, lastSyncError: String?) {
            (letters: letters, unread: unreadCount, pending: pendingDeliveryCount,
             deliveryQueue: deliveryQueue, activation: activationState, lastSyncError: lastSyncError)
        }
        if Thread.isMainThread { return read() }
        return DispatchQueue.main.sync(execute: read)
    }

    /// Thread-safe delay read for tests/diagnostics.
    func currentDelayForTesting() -> TimeInterval {
        queue.sync { currentPollDelay }
    }

    /// Debug CLI/status text — never includes tokens or letter bodies.
    func debugDump() -> String {
        let mailbox = store.snapshot()
        let unread = mailbox.letters.filter(\.isUnread).count
        let snapshot = snapshotForTesting()
        return [
            "BOTTLE_MAIL_DIAGNOSE",
            "activation=\(snapshot.activation)",
            "letters=\(mailbox.letters.count)",
            "unread=\(unread)",
            "cursor=\(mailbox.cursorSeq)",
            "pending=\(snapshot.pending)",
            "deliveryQueue=\(snapshot.deliveryQueue.count)",
            "pollDelay=\(Int(currentDelayForTesting()))s",
        ].joined(separator: " ")
    }
}
