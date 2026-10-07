import Foundation

/// TEMPORARY DIAGNOSTIC logger for the NSMenu/panel disappearance
/// investigation. Appends synchronously to /tmp/WarawaraPet-menu-debug.log
/// and synchronizes after every line so the data survives even if the
/// process crashes. REMOVE THIS FILE BEFORE THE FINAL GIFT BUILD.
enum MenuLifecycleLogger {
    static let isEnabled = true

    private static let logURL = URL(fileURLWithPath: "/tmp/WarawaraPet-menu-debug.log")
    private static var handle: FileHandle?

    static func log(_ event: String) {
        guard isEnabled else { return }
        do {
            if handle == nil {
                let manager = FileManager.default
                if !manager.fileExists(atPath: logURL.path) {
                    manager.createFile(atPath: logURL.path, contents: nil)
                }
                let fileHandle = try FileHandle(forWritingTo: logURL)
                try fileHandle.seekToEnd()
                handle = fileHandle
            }
            let line = "[\(Date())] \(event)\n"
            if let data = line.data(using: .utf8) {
                handle?.write(data)
                handle?.synchronizeFile()
            }
        } catch {
            // Diagnostic logging must never affect pet behavior.
        }
    }
}
