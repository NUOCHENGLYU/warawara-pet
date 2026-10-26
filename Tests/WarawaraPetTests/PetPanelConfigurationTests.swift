import AppKit
import XCTest
@testable import WarawaraPet

/// Runtime window configuration: the pet and companion panels must stay
/// shadowless, transparent, and non-key-capable so the floating
/// character never gains a window halo or steals focus.
final class PetPanelConfigurationTests: XCTestCase {
    func testMainPetPanelDisablesShadowAndIsTransparent() {
        let panel = PetPanel(size: PetMetrics.windowSize)
        XCTAssertFalse(panel.hasShadow, "main pet panel must never cast a window shadow")
        XCTAssertFalse(panel.isOpaque)
        XCTAssertTrue(panel.backgroundColor == NSColor.clear)
        XCTAssertFalse(panel.canBecomeKey, "pet must never take keyboard focus")
        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
    }

    func testPetBodyCenterIsUnaffectedByTopDrawingMargin() {
        let controller = PetWindowController()
        let origin = CGPoint(x: 400, y: 300)
        controller.configureForTesting(
            frame: CGRect(origin: origin, size: PetMetrics.size)
        )
        let canvasCenter = controller.petBodyCenter
        controller.configureForTesting(
            frame: CGRect(origin: origin, size: PetMetrics.windowSize)
        )
        XCTAssertEqual(controller.petBodyCenter, canvasCenter)
        XCTAssertEqual(canvasCenter.y, origin.y + PetMetrics.visualCenter.y)
    }

    func testCompanionPanelDisablesShadowAndIsTransparent() {
        let panel = CompanionPetPanel(size: CompanionMetrics.size)
        XCTAssertFalse(panel.hasShadow, "companion panels must never cast a window shadow")
        XCTAssertFalse(panel.isOpaque)
        XCTAssertTrue(panel.backgroundColor == NSColor.clear)
    }
}
