import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petWindowController: PetWindowController?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load sprite assets BEFORE the first pet render so the
        // character view draws the artwork instead of the placeholder.
        // Failures are recorded and logged; the UI marks the fallback.
        WarawaraSpriteLoader.shared.loadDefaultResources()

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
