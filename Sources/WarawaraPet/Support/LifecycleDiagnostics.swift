import Foundation

/// Lightweight, bounded, persistent lifecycle diagnostics for
/// reliability triage on the recipient's machine.
///
/// - Plain-text append to ~/Library/Logs/WarawaraPet/lifecycle.log.
/// - Single rotating file: when it exceeds `maxFileSize` it is renamed
///   to `lifecycle.log.old` (overwritten), so disk usage is bounded to
///   ~2x the limit.
/// - Per-event frequency throttling: the same event is written at most
///   once per `minimumInterval`, and identical consecutive lines are
///   deduplicated.
/// - No user data: only OS version, bundle id, process id, screen
///   counts and window-visibility booleans are ever recorded.
///
/// All calls are main-thread only by construction (AppKit events).
enum LifecycleDiagnostics {
    /// Test override: redirects the log directory (never nil in tests).
    static var logDirectoryOverride: URL?
    /// Rotate when the log exceeds this size.
    static var maxFileSize: Int = 256 * 1024
    /// Minimum interval between two writes of the SAME event key.
    static var minimumInterval: TimeInterval = 5

    private static var lastWriteTimes: [String: Date] = [:]
    private static var lastLine: String?
    private static var directoryURL: URL?

    static func resetForTesting() {
        lastWriteTimes.removeAll()
        lastLine = nil
        directoryURL = nil
    }

    static func log(_ event: String, details: String = "") {
        let key = event
        let now = Date()
        if let last = lastWriteTimes[key], now.timeIntervalSince(last) < minimumInterval {
            return
        }
        lastWriteTimes[key] = now
        // Cap the dedup map size (bounded by the number of event kinds).
        if lastWriteTimes.count > 64 {
            lastWriteTimes.removeAll(keepingCapacity: true)
        }

        let line = "[\(Self.timestamp(now))] \(event)\(details.isEmpty ? "" : " \(details)")\n"
        if line == lastLine { return }
        lastLine = line

        guard let url = logFileURL() else { return }
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return
        }
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
           size > maxFileSize {
            rotateLog(url: url)
        }
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private static func rotateLog(url: URL) {
        let oldURL = url.deletingLastPathComponent().appendingPathComponent("lifecycle.log.old")
        try? FileManager.default.removeItem(at: oldURL)
        try? FileManager.default.moveItem(at: url, to: oldURL)
    }

    private static func logFileURL() -> URL? {
        if let override = logDirectoryOverride {
            return override.appendingPathComponent("lifecycle.log")
        }
        if let directoryURL { return directoryURL.appendingPathComponent("lifecycle.log") }
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = library.appendingPathComponent("Logs/WarawaraPet", isDirectory: true)
        directoryURL = directory
        return directory.appendingPathComponent("lifecycle.log")
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    // MARK: - Structured events (only non-private fields)

    static func launch() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        log("LIFECYCLE_LAUNCH",
            details: "os=\(ProcessInfo.processInfo.operatingSystemVersionString) version=\(version) pid=\(ProcessInfo.processInfo.processIdentifier) bundle=\(Bundle.main.bundleIdentifier ?? "-")")
    }

    static func quit() {
        log("LIFECYCLE_QUIT")
    }

    static func sleep() {
        log("LIFECYCLE_SLEEP")
    }

    static func wake() {
        log("LIFECYCLE_WAKE")
    }

    static func screenChange(screenCount: Int) {
        log("LIFECYCLE_SCREEN_CHANGE", details: "screens=\(screenCount)")
    }
}
