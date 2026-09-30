import AppKit
import SwiftUI

final class PetWindowController: NSObject {
    static let petSize = CGSize(width: 160, height: 160)
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

        let panel = PetPanel(size: Self.petSize)

        let hostingView = PetHostingView(rootView: PetView(controller: petController))
        hostingView.frame = NSRect(origin: .zero, size: Self.petSize)
        hostingView.interactionController = interaction
        hostingView.contextMenuProvider = { [weak self] in
            self?.makeContextMenu() ?? NSMenu()
        }

        panel.contentView = hostingView
        panel.setFrame(restoredPositionFrame(), display: false)
        panel.orderFrontRegardless()

        self.panel = panel
        self.hostingView = hostingView
        self.controller = petController
        self.motionController = motion
        self.interactionController = interaction
        self.positionStore = store

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let frame = self.panel?.frame else { return }
            self.setWindowFrame(frame, animated: false)
        }

        petController.startIdleSchedule()
    }

    func saveCurrentPosition() {
        guard let positionStore, let panel else { return }
        positionStore.saveOrigin(panel.frame.origin)
    }

    private func restoredPositionFrame() -> CGRect {
        if let saved = positionStore?.loadOrigin(),
           let restored = ScreenGeometry.restoredFrame(
               savedOrigin: saved,
               petSize: Self.petSize,
               visibleFrames: ScreenGeometry.screenVisibleFrames(),
               margin: 32
           ) {
            return restored
        }
        return FrameMath.initialFrame(
            petSize: Self.petSize,
            in: FrameMath.currentScreenVisibleFrame()
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
        return menu
    }
}
