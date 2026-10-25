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

    private func remote(_ seq: Int, id: String = UUID().uuidString, body: String = "信 \(seq)") -> BottleMailRemoteLetter {
        BottleMailRemoteLetter(id: id, seq: seq, body: body, createdAt: "2026-10-17T00:00:00Z", openedAt: nil)
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
}
