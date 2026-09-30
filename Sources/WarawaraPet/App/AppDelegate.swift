import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petWindowController: PetWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
