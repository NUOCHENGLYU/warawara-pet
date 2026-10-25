import Foundation

/// Result of merging a poll page into the mailbox.
struct BottleMailMergeResult: Equatable {
    /// Letters that were genuinely new (in seq order).
    let newLetters: [BottleMailLetter]
    /// Letters already present (deduplicated by id AND seq).
    let duplicateCount: Int
}

/// Durable mailbox: JSON file in Application Support. All mutations are
/// atomic (write temp + replace) and the cursor advances in the SAME
/// write as the letters — a crash can never lose a persisted letter or
/// re-deliver a duplicate.
protocol BottleMailStoring {
    func snapshot() -> BottleMailMailbox
    /// Persist new letters and advance the cursor atomically.
    /// Deduplicates by id and by seq (idempotent on repolling).
    @discardableResult
    func merge(remote: [BottleMailRemoteLetter], advancingCursorTo cursor: Int) throws -> BottleMailMergeResult
    /// Locally marks a letter opened ONLY after the server confirmed it.
    func markOpenedLocally(id: String, openedAt: String) throws
}

final class BottleMailFileStore: BottleMailStoring {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "warawarapet.bottlemail.store")
    private var cached: BottleMailMailbox

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
            let existingIds = Set(cached.letters.map(\.id))
            let existingSeqs = Set(cached.letters.map(\.seq))
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
                    receivedAt: Date()
                )
                newLetters.append(letter)
                existingIds.insert(letter.id)
                existingSeqs.insert(letter.seq)
            }
            if !newLetters.isEmpty || cursor > cached.cursorSeq {
                cached.letters.append(contentsOf: newLetters)
                cached.letters.sort { $0.seq < $1.seq }
                cached.cursorSeq = max(cached.cursorSeq, cursor)
                try persist(cached)
            }
            return BottleMailMergeResult(newLetters: newLetters, duplicateCount: duplicateCount)
        }
    }

    func markOpenedLocally(id: String, openedAt: String) throws {
        try queue.sync {
            guard let index = cached.letters.firstIndex(where: { $0.id == id }) else { return }
            cached.letters[index].openedAt = openedAt
            try persist(cached)
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
        try data.write(to: tempURL, options: .atomic)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
        }
    }
}
