import Foundation

/// Result of merging a poll page into the mailbox.
struct BottleMailMergeResult: Equatable {
    /// Letters that were genuinely new (in seq order).
    let newLetters: [BottleMailLetter]
    /// Letters already present (deduplicated by id AND seq).
    let duplicateCount: Int
}

/// Durable mailbox: JSON file in Application Support. All mutations are
/// failure-atomic: the new state is built on a COPY, persisted first,
/// and only then swapped into memory — a failed write leaves the
/// previous cursor and letters untouched (no skipped letters, no
/// cursor jumps). The cursor advances in the SAME write as the letters.
protocol BottleMailStoring {
    func snapshot() -> BottleMailMailbox
    /// Persist new letters and advance the cursor atomically.
    /// Deduplicates by id and by seq (idempotent on repolling).
    @discardableResult
    func merge(remote: [BottleMailRemoteLetter], advancingCursorTo cursor: Int) throws -> BottleMailMergeResult
    /// Locally marks a letter opened ONLY after the server confirmed it.
    func markOpenedLocally(id: String, openedAt: String) throws
    /// Persists the delivery acknowledgement (exactly-once delivery).
    func markDeliveredLocally(id: String) throws
    /// Persists the revoked flag (set on revocation, cleared on a
    /// successful re-activation).
    func setRevokedFlag(_ revoked: Bool) throws
    /// Persists the pending read-confirmation state (server-pending ids
    /// and the server-confirmed-but-local-write-failed backlog) so a
    /// restart can resume confirmations without losing them.
    func setPendingOpenStates(pendingIds: [String], confirmedBacklog: [String: String]) throws
}

final class BottleMailFileStore: BottleMailStoring {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "warawarapet.bottlemail.store")
    private var cached: BottleMailMailbox
    /// Test seam: replaces the WHOLE physical write+swap. The closure
    /// owns writing the encoded mailbox to `tempURL` and swapping it to
    /// `fileURL` (use `defaultPersist` for the normal behavior) — so
    /// tests can inject failures at any step.
    var persistOverride: ((Data, URL, URL) throws -> Void)?

    /// Default location: ~/Library/Application Support/WarawaraPet/BottleMail/mailbox.json
    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let directory = base
            .appendingPathComponent("WarawaraPet", isDirectory: true)
            .appendingPathComponent("BottleMail", isDirectory: true)
        return directory.appendingPathComponent("mailbox.json")
    }

    init(fileURL: URL = BottleMailFileStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.cached = Self.load(from: fileURL)
    }

    func snapshot() -> BottleMailMailbox {
        queue.sync { cached }
    }

    @discardableResult
    func merge(remote: [BottleMailRemoteLetter], advancingCursorTo cursor: Int) throws -> BottleMailMergeResult {
        try queue.sync {
            // Failure atomicity: mutate a copy, persist the copy, and
            // only then swap it into `cached`.
            var next = cached
            var existingIds = Set(next.letters.map(\.id))
            var existingSeqs = Set(next.letters.map(\.seq))
            var newLetters: [BottleMailLetter] = []
            var duplicateCount = 0
            for remoteLetter in remote.sorted(by: { $0.seq < $1.seq }) {
                if existingIds.contains(remoteLetter.id) || existingSeqs.contains(remoteLetter.seq) {
                    duplicateCount += 1
                    continue
                }
                let letter = BottleMailLetter(
                    seq: remoteLetter.seq,
                    id: remoteLetter.id,
                    body: remoteLetter.body,
                    createdAt: remoteLetter.createdAt,
                    openedAt: remoteLetter.openedAt,
                    receivedAt: Date(),
                    delivered: false
                )
                newLetters.append(letter)
                existingIds.insert(letter.id)
                existingSeqs.insert(letter.seq)
            }
            guard !newLetters.isEmpty || cursor > cached.cursorSeq else {
                return BottleMailMergeResult(newLetters: [], duplicateCount: duplicateCount)
            }
            next.letters.append(contentsOf: newLetters)
            next.letters.sort { $0.seq < $1.seq }
            next.cursorSeq = max(next.cursorSeq, cursor)
            try persist(next)
            cached = next
            return BottleMailMergeResult(newLetters: newLetters, duplicateCount: duplicateCount)
        }
    }

    func markOpenedLocally(id: String, openedAt: String) throws {
        try queue.sync {
            guard let index = cached.letters.firstIndex(where: { $0.id == id }) else { return }
            var next = cached
            next.letters[index].openedAt = openedAt
            try persist(next)
            cached = next
        }
    }

    func markDeliveredLocally(id: String) throws {
        try queue.sync {
            guard let index = cached.letters.firstIndex(where: { $0.id == id }) else { return }
            var next = cached
            next.letters[index].delivered = true
            try persist(next)
            cached = next
        }
    }

    func setRevokedFlag(_ revoked: Bool) throws {
        try queue.sync {
            guard cached.isRevoked != revoked else { return }
            var next = cached
            next.isRevoked = revoked
            try persist(next)
            cached = next
        }
    }

    func setPendingOpenStates(pendingIds: [String], confirmedBacklog: [String: String]) throws {
        try queue.sync {
            guard cached.pendingOpenIds != pendingIds
                    || cached.confirmedOpenBacklog != confirmedBacklog else { return }
            var next = cached
            next.pendingOpenIds = pendingIds
            next.confirmedOpenBacklog = confirmedBacklog
            try persist(next)
            cached = next
        }
    }

    // MARK: - Persistence

    private static func load(from fileURL: URL) -> BottleMailMailbox {
        guard let data = try? Data(contentsOf: fileURL) else { return BottleMailMailbox() }
        if let mailbox = try? JSONDecoder().decode(BottleMailMailbox.self, from: data) {
            return mailbox
        }
        // Corrupt file: never crash the pet — keep a one-shot backup and
        // start fresh (letters can be re-fetched thanks to the server
        // keeping them until actually opened).
        let backupURL = fileURL.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.moveItem(at: fileURL, to: backupURL)
        EventDiagnostics.bottleMail("MAILBOX_FILE_CORRUPT", details: "kept=\(backupURL.lastPathComponent)")
        return BottleMailMailbox()
    }

    private func persist(_ mailbox: BottleMailMailbox) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(mailbox)
        let tempURL = fileURL.appendingPathExtension("tmp")
        if let persistOverride {
            try persistOverride(data, tempURL, fileURL)
        } else {
            try Self.defaultPersist(data: data, tempURL: tempURL, fileURL: fileURL)
        }
    }

    /// The normal write path (also used by tests' success overrides):
    /// atomic temp write + swap.
    static func defaultPersist(data: Data, tempURL: URL, fileURL: URL) throws {
        try data.write(to: tempURL, options: .atomic)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
        }
    }
}
