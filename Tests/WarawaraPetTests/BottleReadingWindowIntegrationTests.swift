import AppKit
import Combine
import XCTest
@testable import WarawaraPet

/// REAL-window integration for the reading completion path: the actual
/// BottleReadingWindowController (NSWindow + NSHostingView) opens and
/// closes, the close event drives the visual coordinator, and the whole
/// flow completes WITHOUT any app termination, recursion or duplicate
/// read marking. macOS 15+ only (older runners may stall in AppKit's
/// window machinery — the same gate as the render test).
@MainActor
final class BottleReadingWindowIntegrationTests: XCTestCase {
    private struct StubTransport: BottleMailAPITransport {
        func activate(code: String, label: String) async throws -> BottleMailActivation {
            throw BottleMailAPIError.network("stub")
        }

        func fetchLetters(after: Int, limit: Int, token: String) async throws -> BottleMailPage {
            BottleMailPage(letters: [], nextAfter: after)
        }

        func markOpened(id: String, token: String) async throws -> String? { nil }
    }

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

    func testCloseCompletesReadReversesAndKeepsTheAppAlive() async throws {
        guard #available(macOS 15.0, *) else {
            throw XCTSkip("real-window integration verified on macOS 15+")
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadingIntegration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = tempDir.appendingPathComponent("mailbox.json")

        let id = UUID().uuidString
        let store = BottleMailFileStore(fileURL: fileURL)
        try store.merge(
            remote: [
                BottleMailRemoteLetter(
                    id: id, seq: 1, body: "集成测试信件内容。", createdAt: "2026-10-17 00:00",
                    openedAt: nil
                )
            ],
            advancingCursorTo: 1
        )
        let coordinator = BottleMailCoordinator(
            transport: StubTransport(),
            credentials: InMemoryBottleMailCredentialStore(),
            store: BottleMailFileStore(fileURL: fileURL)
        )
        coordinator.openRetryInterval = 600

        var currentDate = Date(timeIntervalSinceReferenceDate: 0)
        let visual = BottleVisualCoordinator(mailbox: coordinator)
        visual.morphDuration = 0.4
        visual.openingDuration = 0.2
        visual.nowProvider = { currentDate }
        visual.isPetBusy = { false }

        // The pet window lives through the whole flow.
        let petWindow = PetWindowController()
        petWindow.configureForTesting(frame: CGRect(x: 100, y: 100, width: 200, height: 226))

        var stateLog: [BottleVisualState] = []
        var cancellable: AnyCancellable?
        cancellable = visual.$visualState.sink { stateLog.append($0) }
        var poofCount = 0
        visual.onPoofMoment = { poofCount += 1 }

        let readingWindow = BottleReadingWindowController(coordinator: coordinator, visual: visual)
        visual.onOpenReadingRequested = { [weak readingWindow] _ in
            readingWindow?.show()
        }

        coordinator.start()
        visual.start(usingTimer: false)
        await waitUntil { coordinator.letters.count == 1 }
        await waitUntil { visual.snapshotForTesting().state == .transformingToBottle }
        currentDate = currentDate.addingTimeInterval(0.5)
        visual.advance(now: currentDate)
        XCTAssertEqual(visual.snapshotForTesting().state, .bottleIdle)

        // Tap opens the paper (a REAL NSWindow via show()).
        XCTAssertTrue(visual.handleBottleTap())
        currentDate = currentDate.addingTimeInterval(0.3)
        visual.advance(now: currentDate)
        XCTAssertEqual(visual.snapshotForTesting().state, .reading)
        await waitUntil { BottleReadingWindowController.isOpen }

        // User closes the paper: the ONLY completion entry.
        readingWindow.window?.close()
        await waitUntil { coordinator.unreadCount == 0 }
        await waitUntil { visual.snapshotForTesting().state == .transformingBack }
        currentDate = currentDate.addingTimeInterval(0.5)
        visual.advance(now: currentDate)
        await waitUntil { visual.snapshotForTesting().state == .normal }

        // Ordering: reading -> bottleIdle -> transformingBack -> normal.
        let readingIndex = stateLog.lastIndex(of: .reading) ?? -1
        let idleIndex = stateLog.lastIndex(of: .bottleIdle) ?? -1
        let backIndex = stateLog.lastIndex(of: .transformingBack) ?? -1
        let normalIndex = stateLog.lastIndex(of: .normal) ?? -1
        XCTAssertGreaterThan(readingIndex, 0)
        XCTAssertGreaterThan(idleIndex, readingIndex, "leaves .reading before anything else")
        XCTAssertGreaterThan(backIndex, idleIndex, "the reverse starts after the close")
        XCTAssertGreaterThan(normalIndex, backIndex, "ends back at normal")

        XCTAssertEqual(poofCount, 2, "one poof each way")
        XCTAssertFalse(BottleReadingWindowController.isOpen)
        XCTAssertNotNil(petWindow.petPanel, "the pet window must still exist")
        XCTAssertNotNil(coordinator.letters.first,
                        "the letter is never deleted from the collection")
        _ = cancellable
    }

    func testTwentyShowCloseCyclesNeverCrashOrRecurse() async throws {
        guard #available(macOS 15.0, *) else {
            throw XCTSkip("real-window integration verified on macOS 15+")
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadingLoop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = tempDir.appendingPathComponent("mailbox.json")

        let store = BottleMailFileStore(fileURL: fileURL)
        try store.merge(
            remote: [
                BottleMailRemoteLetter(
                    id: "loop", seq: 1, body: "循环测试。", createdAt: "2026-10-17 00:00",
                    openedAt: nil
                )
            ],
            advancingCursorTo: 1
        )
        let coordinator = BottleMailCoordinator(
            transport: StubTransport(),
            credentials: InMemoryBottleMailCredentialStore(),
            store: BottleMailFileStore(fileURL: fileURL)
        )
        coordinator.openRetryInterval = 600
        let visual = BottleVisualCoordinator(mailbox: coordinator)
        visual.morphDuration = 0.4
        visual.openingDuration = 0.2
        visual.isPetBusy = { false }
        coordinator.start()
        visual.start(usingTimer: false)
        await waitUntil { coordinator.letters.count == 1 }

        let readingWindow = BottleReadingWindowController(coordinator: coordinator, visual: visual)
        for iteration in 0..<20 {
            readingWindow.show()
            XCTAssertTrue(BottleReadingWindowController.isOpen, "iteration \(iteration)")
            // Close twice per cycle: a duplicated windowWillClose must
            // remain a no-op (idempotent, reentrancy-free).
            readingWindow.window?.close()
            readingWindow.window?.close()
            await waitUntil { !BottleReadingWindowController.isOpen }
        }
        // The app survived: the visual coordinator is still coherent and
        // the window can still be shown.
        readingWindow.show()
        XCTAssertTrue(BottleReadingWindowController.isOpen)
        readingWindow.window?.close()
        await waitUntil { !BottleReadingWindowController.isOpen }
    }
}
