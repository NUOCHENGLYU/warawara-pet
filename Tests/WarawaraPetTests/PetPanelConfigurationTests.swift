import AppKit
import XCTest
@testable import WarawaraPet

/// Runtime window configuration: the pet and companion panels must stay
/// shadowless, transparent, and non-key-capable so the floating
/// character never gains a window halo or steals focus.
final class PetPanelConfigurationTests: XCTestCase {
    func testMainPetPanelDisablesShadowAndIsTransparent() {
        let panel = PetPanel(size: PetMetrics.size)
        XCTAssertFalse(panel.hasShadow, "main pet panel must never cast a window shadow")
        XCTAssertFalse(panel.isOpaque)
        XCTAssertTrue(panel.backgroundColor == NSColor.clear)
        XCTAssertFalse(panel.canBecomeKey, "pet must never take keyboard focus")
        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
    }

    func testCompanionPanelDisablesShadowAndIsTransparent() {
        let panel = CompanionPetPanel(size: CompanionMetrics.size)
        XCTAssertFalse(panel.hasShadow, "companion panels must never cast a window shadow")
        XCTAssertFalse(panel.isOpaque)
        XCTAssertTrue(panel.backgroundColor == NSColor.clear)
    }
}
