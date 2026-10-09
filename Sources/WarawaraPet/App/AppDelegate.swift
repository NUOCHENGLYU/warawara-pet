import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petWindowController: PetWindowController?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The status item is created once and held strongly for the
        // lifetime of the app.
        statusItemController = StatusItemController()

        let controller = PetWindowController()
        controller.showPet()
        petWindowController = controller
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        petWindowController?.saveCurrentPosition()
    }
}
