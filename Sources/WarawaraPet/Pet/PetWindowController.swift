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
    private var menuDebugObserverTokens: [NSObjectProtocol] = []

    // TEMPORARY DIAGNOSTIC (menu investigation).
    deinit {
        MenuLifecycleLogger.log("PetWindowController deinit")
    }

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
        hostingView.contextMenuPopover = { [weak self] in
            self?.popUpDetachedMenu() ?? false
        }

        panel.contentView = hostingView
        panel.setFrame(restoredPositionFrame(using: store), display: false)
        panel.orderFrontRegardless()

        self.panel = panel
        self.hostingView = hostingView

        installMenuDebugPanelObservers(for: panel)
        logMenuDebugSnapshot("panel shown")

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
        // TEMPORARY DIAGNOSTIC delegate (menu investigation).
        menu.delegate = self
        let quitItem = NSMenuItem(
            title: "Quit WarawaraPet",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)
        return menu
    }

    /// Shows the pet's context menu as a detached popup at the current
    /// global mouse location, intentionally NOT anchored to the hosting
    /// view or the panel (`in: nil` = screen coordinates). Menu tracking
    /// therefore never interacts with the nonactivating panel, so opening
    /// or dismissing the menu cannot demote or hide the pet.
    private func popUpDetachedMenu() -> Bool {
        let menu = makeContextMenu()
        logMenuDebugSnapshot("menu popup before")
        let result = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        logMenuDebugSnapshot("menu popup after result=\(result)")
        // TEMPORARY DIAGNOSTIC post-close snapshots (menu investigation).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.logMenuDebugSnapshot("menu close +nextTick")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.logMenuDebugSnapshot("menu close +100ms")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.logMenuDebugSnapshot("menu close +500ms")
            }
        }
        return result
    }

    // MARK: - TEMPORARY DIAGNOSTIC (menu investigation)
    // Remove this section before the final gift build.

    private func installMenuDebugPanelObservers(for panel: PetPanel) {
        let names: [NSNotification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didResignMainNotification
        ]
        for name in names {
            let token = NotificationCenter.default.addObserver(
                forName: name,
                object: panel,
                queue: .main
            ) { note in
                MenuLifecycleLogger.log("panel \(note.name.rawValue)")
            }
            menuDebugObserverTokens.append(token)
        }
    }

    private func logMenuDebugSnapshot(_ stage: String) {
        let panel = self.panel
        let app = NSApplication.shared
        let frame = panel.map { NSStringFromRect($0.frame) } ?? "nil"
        let windowNumber = panel?.windowNumber ?? -1
        let level = panel.map { $0.level.rawValue } ?? -1
        let canHide = panel?.canHide ?? false
        let hidesOnDeactivate = panel?.hidesOnDeactivate ?? false
        let occlusion = panel?.occlusionState.rawValue ?? 0
        let visible = panel?.isVisible ?? false
        let isKey = panel?.isKeyWindow ?? false
        let isMain = panel?.isMainWindow ?? false
        let stateText = controller.map { String(describing: $0.state) } ?? "nil"

        var parts: [String] = []
        parts.append(stage)
        parts.append("isActive=\(app.isActive)")
        parts.append("isHidden=\(app.isHidden)")
        parts.append("visible=\(visible)")
        parts.append("isKey=\(isKey)")
        parts.append("isMain=\(isMain)")
        parts.append("frame=\(frame)")
        parts.append("windowNumber=\(windowNumber)")
        parts.append("level=\(level)")
        parts.append("canHide=\(canHide)")
        parts.append("hidesOnDeactivate=\(hidesOnDeactivate)")
        parts.append("occlusion=\(occlusion)")
        parts.append("state=\(stateText)")
        MenuLifecycleLogger.log(parts.joined(separator: " "))
    }
}

// TEMPORARY DIAGNOSTIC (menu investigation). Remove before the final build.
extension PetWindowController: NSMenuDelegate {
    func menuDidClose(_ menu: NSMenu) {
        logMenuDebugSnapshot("menuDidClose")
    }
}
