import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petWindowController: PetWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuLifecycleLogger.log("applicationDidFinishLaunching isHidden=\(NSApp.isHidden)")
        installMenuLifecycleObservers()
        let controller = PetWindowController()
        controller.showPet()
        petWindowController = controller
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        MenuLifecycleLogger.log("applicationWillTerminate")
        petWindowController?.saveCurrentPosition()
    }

    // MARK: - TEMPORARY DIAGNOSTIC (menu investigation)
    // Remove this section before the final gift build.

    func applicationDidBecomeActive(_ notification: Notification) {
        MenuLifecycleLogger.log("applicationDidBecomeActive isHidden=\(NSApp.isHidden)")
    }

    func applicationDidResignActive(_ notification: Notification) {
        MenuLifecycleLogger.log("applicationDidResignActive isHidden=\(NSApp.isHidden)")
    }

    private func installMenuLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didHideNotification,
            object: NSApp,
            queue: .main
        ) { _ in
            MenuLifecycleLogger.log("didHideNotification isHidden=\(NSApp.isHidden)")
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didUnhideNotification,
            object: NSApp,
            queue: .main
        ) { _ in
            MenuLifecycleLogger.log("didUnhideNotification isHidden=\(NSApp.isHidden)")
        }
    }
}
