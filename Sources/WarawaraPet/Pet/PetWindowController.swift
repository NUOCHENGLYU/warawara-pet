import AppKit
import SwiftUI

final class PetWindowController: NSObject {
    static let petSize = PetMetrics.size
    static let windowMargin: CGFloat = 8

    private var panel: PetPanel?
    private var hostingView: PetHostingView?
    private var controller: PetController?
    private var motionController: PetMotionController?
    private var interactionController: PetInteractionController?
    private var positionStore: PetPositionStore?
    private var screenObserver: NSObjectProtocol?

    var currentFrame: CGRect {
        panel?.frame ?? .zero
    }

    func setWindowFrame(_ frame: CGRect, animated: Bool) {
        guard let panel else { return }
        let clamped = ScreenGeometry.clampFrame(
            frame,
            to: ScreenGeometry.visibleFrame(for: frame),
            margin: Self.windowMargin
        )
        panel.setFrame(clamped, display: true, animate: animated)
    }

    func showPet() {
        let store = PetPositionStore()
        let motion = PetMotionController(windowController: self)
        let petController = PetController(
            windowController: self,
            motionController: motion,
            positionStore: store
        )
        let interaction = PetInteractionController(windowController: self, controller: petController)

        // Assign the store and controllers BEFORE any restoration logic
        // reads them; otherwise the saved position is silently ignored.
        self.positionStore = store
        self.controller = petController
        self.motionController = motion
        self.interactionController = interaction

        let panel = PetPanel(size: Self.petSize)

        let hostingView = PetHostingView(rootView: PetView(controller: petController))
        hostingView.frame = NSRect(origin: .zero, size: Self.petSize)
        hostingView.interactionController = interaction
        hostingView.contextMenuProvider = { [weak self] in
            self?.makeContextMenu() ?? NSMenu()
        }

        panel.contentView = hostingView
        panel.setFrame(restoredPositionFrame(using: store), display: false)
        panel.orderFrontRegardless()

        self.panel = panel
        self.hostingView = hostingView

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let frame = self.panel?.frame else { return }
            self.setWindowFrame(frame, animated: false)
        }

        petController.startAutonomousBehavior()
    }

    func saveCurrentPosition() {
        guard let positionStore, let panel else { return }
        // Never persist transient mid-hop/mid-float/mid-drag frames; a quit
        // during motion restores the last grounded position instead.
        if controller?.isInTransientMotion == true { return }
        positionStore.saveOrigin(panel.frame.origin)
    }

    private func restoredPositionFrame(using store: PetPositionStore) -> CGRect {
        ScreenGeometry.restoredPositionFrame(
            savedOrigin: store.loadOrigin(),
            petSize: Self.petSize,
            visibleFrames: ScreenGeometry.screenVisibleFrames(),
            restoreMargin: 32,
            defaultVisibleFrame: FrameMath.currentScreenVisibleFrame()
        )
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: "Quit WarawaraPet",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)

        if DebugControls.isEnabled {
            let debugItem = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
            let debugMenu = NSMenu()
            let forceActions: [(String, Selector)] = [
                ("Force Hop", #selector(PetController.forceHop)),
                ("Force Float", #selector(PetController.forceFloat)),
                ("Force Curious", #selector(PetController.forceCurious)),
                ("Force Sleepy", #selector(PetController.forceSleepy)),
                ("Force Sleeping", #selector(PetController.forceSleeping))
            ]
            for (title, selector) in forceActions {
                let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
                item.target = controller
                debugMenu.addItem(item)
            }
            debugItem.submenu = debugMenu
            menu.addItem(debugItem)
        }

        return menu
    }
}
