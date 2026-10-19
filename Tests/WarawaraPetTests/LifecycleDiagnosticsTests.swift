import XCTest
@testable import WarawaraPet

/// The persistent lifecycle log must stay bounded on disk, throttle
/// repeated events, and never record privacy-sensitive data.
final class LifecycleDiagnosticsTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LifecycleDiagnosticsTests.\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        LifecycleDiagnostics.logDirectoryOverride = tempDirectory
        LifecycleDiagnostics.resetForTesting()
        LifecycleDiagnostics.maxFileSize = 4096
        LifecycleDiagnostics.minimumInterval = 0
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        LifecycleDiagnostics.logDirectoryOverride = nil
        LifecycleDiagnostics.resetForTesting()
        LifecycleDiagnostics.maxFileSize = 256 * 1024
        LifecycleDiagnostics.minimumInterval = 5
        super.tearDown()
    }

    private var logURL: URL {
        tempDirectory.appendingPathComponent("lifecycle.log")
    }

    private func readLog() -> String {
        (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
    }

    func testLaunchEventIsWritten() {
        LifecycleDiagnostics.launch()
        let content = readLog()
        XCTAssertTrue(content.contains("LIFECYCLE_LAUNCH"))
        XCTAssertTrue(content.contains("os="))
        XCTAssertFalse(content.contains(NSUserName()), "no user names may be logged")
        XCTAssertFalse(content.contains(NSTemporaryDirectory()), "no home paths may be logged")
    }

    func testRotationKeepsDiskBounded() {
        for index in 0..<600 {
            LifecycleDiagnostics.log("TEST_EVENT", details: "index=\(index)")
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int) ?? 0
        XCTAssertLessThan(size, 8192, "the log must rotate and stay far below the bound")
        let oldExists = FileManager.default.fileExists(
            atPath: tempDirectory.appendingPathComponent("lifecycle.log.old").path
        )
        XCTAssertTrue(oldExists, "rotation must preserve the previous segment")
    }

    func testFrequencyThrottlingDeduplicatesRepeatedEvents() {
        LifecycleDiagnostics.minimumInterval = 3600
        LifecycleDiagnostics.launch()
        LifecycleDiagnostics.launch()
        LifecycleDiagnostics.launch()
        let occurrences = readLog().components(separatedBy: "LIFECYCLE_LAUNCH").count - 1
        XCTAssertEqual(occurrences, 1, "the same event writes at most once per interval")
    }

    func testEventKindsAreRecorded() {
        LifecycleDiagnostics.screenChange(screenCount: 2)
        LifecycleDiagnostics.sleep()
        LifecycleDiagnostics.wake()
        LifecycleDiagnostics.quit()
        let content = readLog()
        XCTAssertTrue(content.contains("LIFECYCLE_SCREEN_CHANGE screens=2"))
        XCTAssertTrue(content.contains("LIFECYCLE_SLEEP"))
        XCTAssertTrue(content.contains("LIFECYCLE_WAKE"))
        XCTAssertTrue(content.contains("LIFECYCLE_QUIT"))
    }
}
