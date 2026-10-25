import Foundation
import XCTest
@testable import WarawaraPet

/// Mailbox file-store coverage: dedupe, ordering, cursor advance,
/// atomic persistence, restart recovery and corrupt-file resilience.
final class BottleMailStoreTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BottleMailStoreTests-\(UUID().uuidString)", isDirectory: true)
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

    func testMergeStoresNewLettersOrderedAndAdvancesCursor() throws {
        let store = BottleMailFileStore(fileURL: fileURL)
        let result = try store.merge(
            remote: [remote(3), remote(1), remote(2)],
            advancingCursorTo: 3
        )
        XCTAssertEqual(result.newLetters.map(\.seq), [1, 2, 3])
        XCTAssertEqual(result.duplicateCount, 0)
        XCTAssertEqual(store.snapshot().cursorSeq, 3)
        XCTAssertEqual(store.snapshot().letters.map(\.seq), [1, 2, 3])
    }

    func testMergeDeduplicatesByIdAndBySeq() throws {
        let store = BottleMailFileStore(fileURL: fileURL)
        let idA = UUID().uuidString
        let first = try store.merge(remote: [remote(1, id: idA)], advancingCursorTo: 1)
        XCTAssertEqual(first.newLetters.count, 1)
        // Repolling returns the same letter again (id AND seq collide).
        let repoll = try store.merge(remote: [remote(1, id: idA)], advancingCursorTo: 1)
        XCTAssertEqual(repoll.newLetters.count, 0)
        XCTAssertEqual(repoll.duplicateCount, 1)
        // A different id reusing the same seq must also be dropped.
        let seqCollision = try store.merge(remote: [remote(1)], advancingCursorTo: 1)
        XCTAssertEqual(seqCollision.newLetters.count, 0)
        XCTAssertEqual(store.snapshot().letters.count, 1)
    }

    func testPersistenceSurvivesRestart() throws {
        let store = BottleMailFileStore(fileURL: fileURL)
        _ = try store.merge(remote: [remote(1), remote(2)], advancingCursorTo: 2)
        // Simulate a process restart: a NEW store instance over the same
        // file must see everything (letters + cursor + unread state).
        let reopened = BottleMailFileStore(fileURL: fileURL)
        XCTAssertEqual(reopened.snapshot().letters.count, 2)
        XCTAssertEqual(reopened.snapshot().cursorSeq, 2)
        XCTAssertEqual(reopened.snapshot().letters.filter(\.isUnread).count, 2)
    }

    func testUnreadStateOnlyChangesOnExplicitOpen() throws {
        let store = BottleMailFileStore(fileURL: fileURL)
        let id = UUID().uuidString
        _ = try store.merge(remote: [remote(1, id: id)], advancingCursorTo: 1)
        try store.markOpenedLocally(id: id, openedAt: "2026-10-17T01:00:00Z")
        let reopened = BottleMailFileStore(fileURL: fileURL)
        XCTAssertEqual(reopened.snapshot().letters.first?.openedAt, "2026-10-17T01:00:00Z")
        XCTAssertEqual(reopened.snapshot().letters.filter(\.isUnread).count, 0)
    }

    func testCorruptFileFallsBackToFreshMailboxWithoutCrashing() throws {
        try Data("not-json{{{".utf8).write(to: fileURL)
        let store = BottleMailFileStore(fileURL: fileURL)
        XCTAssertEqual(store.snapshot().letters.count, 0)
        XCTAssertEqual(store.snapshot().cursorSeq, 0)
        // The corrupt original is preserved for forensics.
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.appendingPathExtension("corrupt").path))
        // And the store still works.
        _ = try store.merge(remote: [remote(1)], advancingCursorTo: 1)
        XCTAssertEqual(store.snapshot().letters.count, 1)
    }

    func testBackwardCompatibleDecodeWithoutDeliveredAndRevokedKeys() throws {
        // A mailbox written by Phase 8B (before 8B.1): no `delivered`
        // key on letters and no `isRevoked` key on the mailbox.
        let legacyJSON = """
        {"version":1,"cursorSeq":1,"letters":[
          {"seq":1,"id":"a","body":"旧信","createdAt":"2026-10-17T00:00:00Z","openedAt":null,"receivedAt":731000000.0}
        ]}
        """
        try legacyJSON.data(using: .utf8)!.write(to: fileURL)
        let store = BottleMailFileStore(fileURL: fileURL)
        XCTAssertEqual(store.snapshot().letters.count, 1)
        XCTAssertEqual(store.snapshot().letters.first?.delivered, false,
                       "legacy letters are treated as not yet delivered")
        XCTAssertEqual(store.snapshot().isRevoked, false)
        XCTAssertEqual(store.snapshot().pendingOpenIds, [],
                       "legacy mailboxes have no pending open confirmations")
        XCTAssertEqual(store.snapshot().confirmedOpenBacklog, [:])
    }

    func testPendingOpenStatesPersistAndAreFailureAtomic() throws {
        let store = BottleMailFileStore(fileURL: fileURL)
        try store.setPendingOpenStates(pendingIds: ["a", "b"], confirmedBacklog: ["c": "t1"])
        let reopened = BottleMailFileStore(fileURL: fileURL)
        XCTAssertEqual(reopened.snapshot().pendingOpenIds, ["a", "b"])
        XCTAssertEqual(reopened.snapshot().confirmedOpenBacklog, ["c": "t1"])

        // A failed persist leaves the previous state untouched.
        store.persistOverride = { _, _, _ in throw CocoaError(.fileWriteUnknown) }
        XCTAssertThrowsError(try store.setPendingOpenStates(pendingIds: [], confirmedBacklog: [:]))
        XCTAssertEqual(store.snapshot().pendingOpenIds, ["a", "b"])
        XCTAssertEqual(store.snapshot().confirmedOpenBacklog, ["c": "t1"])
    }

    // MARK: - Failure atomicity

    func testMergeFailureLeavesCursorAndLettersUntouched() throws {
        let store = BottleMailFileStore(fileURL: fileURL)
        _ = try store.merge(remote: [remote(1)], advancingCursorTo: 1)
        let before = store.snapshot()

        var shouldFail = true
        store.persistOverride = { data, tempURL, fileURL in
            if shouldFail { throw CocoaError(.fileWriteUnknown) }
            try BottleMailFileStore.defaultPersist(data: data, tempURL: tempURL, fileURL: fileURL)
        }
        XCTAssertThrowsError(try store.merge(remote: [remote(2)], advancingCursorTo: 2)) { error in
            XCTAssertTrue(error is CocoaError)
        }
        XCTAssertEqual(store.snapshot(), before,
                       "a failed merge must not advance the cursor or add letters in memory")
        // On disk nothing changed either.
        let onDisk = BottleMailFileStore(fileURL: fileURL).snapshot()
        XCTAssertEqual(onDisk, before)

        // Once writes succeed again, the same merge completes without
        // duplicates or cursor jumps.
        shouldFail = false
        let result = try store.merge(remote: [remote(2)], advancingCursorTo: 2)
        XCTAssertEqual(result.newLetters.map(\.seq), [2])
        XCTAssertEqual(store.snapshot().cursorSeq, 2)
        XCTAssertEqual(store.snapshot().letters.map(\.seq), [1, 2])
    }

    func testMarkOpenedLocallyFailureKeepsLetterUnread() throws {
        let store = BottleMailFileStore(fileURL: fileURL)
        let id = UUID().uuidString
        _ = try store.merge(remote: [remote(1, id: id)], advancingCursorTo: 1)

        store.persistOverride = { _, _, _ in throw CocoaError(.fileWriteUnknown) }
        XCTAssertThrowsError(try store.markOpenedLocally(id: id, openedAt: "2026-10-17T01:00:00Z"))
        XCTAssertEqual(store.snapshot().letters.first?.isUnread, true,
                       "a failed local open write must not flip the unread state")

        store.persistOverride = nil
        try store.markOpenedLocally(id: id, openedAt: "2026-10-17T01:00:00Z")
        XCTAssertEqual(store.snapshot().letters.first?.openedAt, "2026-10-17T01:00:00Z")
    }

    func testMarkDeliveredAndRevokedFlagPersist() throws {
        let store = BottleMailFileStore(fileURL: fileURL)
        let id = UUID().uuidString
        _ = try store.merge(remote: [remote(1, id: id)], advancingCursorTo: 1)
        try store.markDeliveredLocally(id: id)
        XCTAssertEqual(store.snapshot().letters.first?.delivered, true)
        try store.setRevokedFlag(true)
        XCTAssertEqual(store.snapshot().isRevoked, true)
        let reopened = BottleMailFileStore(fileURL: fileURL)
        XCTAssertEqual(reopened.snapshot().letters.first?.delivered, true)
        XCTAssertEqual(reopened.snapshot().isRevoked, true)
    }
}
