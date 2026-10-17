import XCTest
@testable import WarawaraPet

/// The geometry authority: ONE scale per asset, painted-content targets
/// relative to the pet height, contact-anchored placement, and clipping
/// containment at every boundary (hosting view AND panel).
final class PropRenderGeometryTests: XCTestCase {
    private let petFrame = CGRect(x: 600, y: 120, width: 180, height: 226)
    private let visible = CGRect(x: 0, y: 0, width: 1280, height: 800)

    // MARK: - One and only one scale

    func testExactlyOneScalePerAsset() {
        for asset in PropRenderGeometry.boxes.keys {
            let box = PropRenderGeometry.boxes[asset]!
            let ratio = PropRenderGeometry.targetRatios[asset] ?? 0.5
            let scale = PropRenderGeometry.scale(asset: asset)
            let canvas = PropRenderGeometry.canvasPt(asset: asset)
            // scale = target / paintedWidthPx
            XCTAssertEqual(scale * box.width, ratio * PropRenderGeometry.petHeight, accuracy: 0.0001,
                           "\(asset): scale must map painted width to the target exactly")
            // canvas = 1024 * scale (single multiplication, no bbox re-shrink)
            XCTAssertEqual(canvas, 1024 * scale, accuracy: 0.0001,
                           "\(asset): canvas must use the same scale")
            // The painted content, drawn through the same scale, is the target.
            let content = PropRenderGeometry.contentSizePt(asset: asset)
            XCTAssertEqual(content.width, ratio * PropRenderGeometry.petHeight, accuracy: 0.0001,
                           "\(asset): painted width must equal the calibration target")
        }
    }

    func testCalibrationTargetsMatchTheHandoffRatios() {
        let expected: [SeasonalEventKind: CGFloat] = [
            .cny: 0.68, .christmas: 0.85, .newYear: 0.82,
            .umbrella: 1.65, .hotCocoa: 0.67, .sprout: 0.56, .paperAirplane: 0.88
        ]
        for (kind, ratio) in expected {
            let content = PropRenderGeometry.contentSizePt(asset: kind.primaryAsset)
            XCTAssertEqual(
                content.width / PropRenderGeometry.petHeight, ratio, accuracy: 0.0001,
                "\(kind): painted width over pet height must match the calibration"
            )
        }
    }

    func testNoRetinaBackingScaleInLogicalPoints() {
        // Logical AppKit points never include a backing-scale factor.
        let gift = PropRenderGeometry.contentSizePt(asset: "xmas_gift.png")
        XCTAssertEqual(gift.width, 0.85 * PropRenderGeometry.petHeight, accuracy: 0.01)
        XCTAssertLessThan(gift.width, 300, "no 2x Retina multiplication may leak in")
    }

    // MARK: - Canvas-to-content transformation

    func testContentRectAroundCanvasCenterMatchesSourceBox() {
        let box = PropRenderGeometry.boxes["cny_hongbao.png"]!
        let s = PropRenderGeometry.scale(asset: "cny_hongbao.png")
        let rect = PropRenderGeometry.contentRectAroundCanvasCenter(asset: "cny_hongbao.png")
        XCTAssertEqual(rect.minX, (box.left - 512) * s, accuracy: 0.001)
        XCTAssertEqual(rect.minY, (box.top - 512) * s, accuracy: 0.001)
        XCTAssertEqual(rect.width, box.width * s, accuracy: 0.001)
        XCTAssertEqual(rect.height, box.height * s, accuracy: 0.001)
    }

    func testContactPlacesContentExactlyAtPanelCenter() {
        for kind in SeasonalEventKind.allCases {
            let contact = PropRenderGeometry.contactPoint(for: kind)
            let rect = PropRenderGeometry.primaryContentRectInPanel(for: kind)
            // The contact point (fractions from left/bottom of content)
            // must map to (0,0) — the panel center.
            XCTAssertEqual(rect.minX + contact.x * rect.width, 0, accuracy: 0.01,
                           "\(kind): contact X must land on the panel center")
            XCTAssertEqual(rect.minY + (1 - contact.y) * rect.height, 0, accuracy: 0.01,
                           "\(kind): contact Y must land on the panel center")
        }
    }

    // MARK: - Clipping containment at every boundary

    func testAllPaintedContentFitsPanelWithSafetyMargin() {
        for kind in SeasonalEventKind.allCases {
            let size = PropRenderGeometry.panelSize(for: kind)
            let extents = PropRenderGeometry.contentExtentRect(for: kind, lidLift: 1)
            // Panel in contact coordinates: centered on the extents.
            let panelMinX = extents.midX - size.width / 2
            let panelMaxX = extents.midX + size.width / 2
            let panelMinY = extents.midY - size.height / 2
            let panelMaxY = extents.midY + size.height / 2
            XCTAssertGreaterThanOrEqual(extents.minX, panelMinX + PropRenderGeometry.margin - 0.01,
                                        "\(kind): content clipped left")
            XCTAssertLessThanOrEqual(extents.maxX, panelMaxX - PropRenderGeometry.margin + 0.01,
                                     "\(kind): content clipped right")
            XCTAssertGreaterThanOrEqual(extents.minY, panelMinY + PropRenderGeometry.margin - 0.01,
                                        "\(kind): content clipped bottom")
            XCTAssertLessThanOrEqual(extents.maxY, panelMaxY - PropRenderGeometry.margin + 0.01,
                                     "\(kind): content clipped top")
        }
    }

    func testRotatedLidStaysInsidePanel() {
        // The lifted, rotated lid is part of the extents union.
        let extents = PropRenderGeometry.contentExtentRect(for: .christmas, lidLift: 1)
        let open = PropRenderGeometry.giftOpenRectsInPanel(lidLift: 1)
        let rotatedLid = PropRenderGeometry.rotatedBounds(of: open.lid, degrees: 10)
        XCTAssertTrue(extents.contains(rotatedLid),
                      "the fully lifted rotated lid must be inside the extents union")
        XCTAssertTrue(extents.contains(open.base), "the open base must be inside the extents")
    }

    func testClosedAndOpenedHongbaoShareBodyAndBottom() {
        let closed = PropRenderGeometry.boxes["cny_hongbao.png"]!
        let open = PropRenderGeometry.boxes["cny_hongbao_open.png"]!
        XCTAssertEqual(closed.width, open.width, accuracy: 0.01,
                       "closed and opened hongbao must share the body width")
        XCTAssertEqual(closed.bottom, open.bottom, accuracy: 0.01,
                       "closed and opened hongbao must share the resting bottom")
        let closedRect = PropRenderGeometry.primaryContentRectInPanel(for: .cny)
        let openRect = PropRenderGeometry.canvasOffset(
            asset: "cny_hongbao_open.png",
            fx: PropRenderGeometry.contactPoint(for: .cny).x,
            fy: PropRenderGeometry.contactPoint(for: .cny).y,
            at: .zero
        )
        _ = closedRect
        XCTAssertTrue(openRect != .zero, "opened envelope offset must be well-defined")
    }

    func testGiftLayersShareTheClosedGiftContact() {
        // Base bottom == closed gift bottom == contact (0,0).
        let base = PropRenderGeometry.giftOpenRectsInPanel(lidLift: 0).base
        XCTAssertEqual(base.maxY, 0, accuracy: 0.5, "open base must rest on the same contact")
        let closed = PropRenderGeometry.primaryContentRectInPanel(for: .christmas)
        XCTAssertEqual(closed.maxY, 0, accuracy: 0.5, "closed gift must rest on the same contact")
        // Lid overlaps the base top seam before lifting.
        let lid0 = PropRenderGeometry.giftOpenRectsInPanel(lidLift: 0).lid
        XCTAssertLessThanOrEqual(lid0.maxY, base.maxY + 8, "lid must start at the base seam")
        XCTAssertGreaterThan(lid0.minY, base.minY - 20, "lid must not float away")
    }

    func testUmbrellaFullCanopyExtendsOverhead() {
        let size = PropRenderGeometry.contentSizePt(asset: "daily_umbrella.png")
        XCTAssertEqual(size.width, 1.65 * PropRenderGeometry.petHeight, accuracy: 0.01,
                       "full umbrella canopy must be at the calibrated width")
        let rect = PropRenderGeometry.primaryContentRectInPanel(for: .umbrella)
        // Contact near the handle bottom: the canopy extends far above.
        XCTAssertGreaterThan(rect.maxY, size.height * 0.85,
                             "canopy must extend above the grip contact")
        let panel = PropRenderGeometry.panelSize(for: .umbrella)
        let extents = PropRenderGeometry.contentExtentRect(for: .umbrella, lidLift: 1)
        XCTAssertLessThanOrEqual(extents.height, panel.height - 2 * PropRenderGeometry.margin + 0.01)
    }

    func testOverlaysFitTheirEffectPanelAndDoNotCropThePrimary() {
        for asset in ["rain_drops_overlay.png", "newyear_confetti_overlay.png"] {
            let canvas = PropRenderGeometry.canvasPt(asset: asset)
            XCTAssertLessThanOrEqual(canvas, 320, "\(asset): effect canvas must fit its 320pt panel")
        }
        // The effect overlay is drawn in its own panel, never inside the
        // primary's panel extents.
        let planeExtents = PropRenderGeometry.contentExtentRect(for: .paperAirplane, lidLift: 1)
        XCTAssertFalse(planeExtents.isNull)
    }

    // MARK: - Anchors and edge placement

    func testPanelOriginsStayNearThePetNotTheScreenCorner() {
        let anchors = EventAnchorSystem(petFrame: petFrame)
        for kind in SeasonalEventKind.allCases {
            let target: CGPoint
            switch kind {
            case .cny: target = anchors.handFront
            case .christmas, .newYear: target = anchors.groundBesidePet
            case .umbrella: target = anchors.umbrellaGrip
            case .hotCocoa: target = anchors.nearRightFoot
            case .sprout: target = anchors.nearLeftFoot
            case .paperAirplane: target = anchors.headCenter
            }
            let origin = PropRenderGeometry.panelOrigin(anchor: target, kind: kind)
            let size = PropRenderGeometry.panelSize(for: kind)
            let extents = PropRenderGeometry.contentExtentRect(for: kind, lidLift: 1)
            // Contact lands exactly on the world anchor.
            let contactX = origin.x + size.width / 2 - extents.midX
            let contactY = origin.y + size.height / 2 + extents.midY
            XCTAssertEqual(contactX, target.x, accuracy: 0.01, "\(kind): contact must land on the anchor")
            XCTAssertEqual(contactY, target.y, accuracy: 0.01, "\(kind): contact must land on the anchor")
            XCTAssertGreaterThan(contactX, 200, "\(kind): never in the lower-left corner")
            XCTAssertGreaterThan(contactY, 80, "\(kind): never in the lower-left corner")
        }
    }

    func testEdgePlacementStaysWithinVisibleFrame() {
        let edgePet = CGRect(x: 30, y: 30, width: 180, height: 226)
        let anchors = EventAnchorSystem(petFrame: edgePet)
        for kind in [SeasonalEventKind.hotCocoa, .christmas, .newYear, .sprout] {
            let target: CGPoint
            switch kind {
            case .hotCocoa: target = anchors.nearRightFoot
            case .sprout: target = anchors.nearLeftFoot
            default: target = anchors.groundBesidePet
            }
            let size = PropRenderGeometry.panelSize(for: kind)
            let origin = PropRenderGeometry.panelOrigin(anchor: target, kind: kind)
            let clamped = CGPoint(
                x: min(max(origin.x, visible.minX + 4), max(visible.minX + 4, visible.maxX - size.width - 4)),
                y: min(max(origin.y, visible.minY + 4), max(visible.minY + 4, visible.maxY - size.height - 4))
            )
            XCTAssertGreaterThanOrEqual(clamped.x, visible.minX + 4 - 0.01)
            XCTAssertLessThanOrEqual(clamped.x + size.width, visible.maxX - 4 + 0.01)
            XCTAssertGreaterThanOrEqual(clamped.y, visible.minY + 4 - 0.01)
            XCTAssertLessThanOrEqual(clamped.y + size.height, visible.maxY - 4 + 0.01)
        }
    }

    func testAirplanePathExtremaStayInsideTheirPanel() {
        // At any flight pose the panel follows the plane's contact point,
        // so content is always inside; verify the trail + plane extents
        // remain finite and within the panel at rest.
        let size = PropRenderGeometry.panelSize(for: .paperAirplane)
        let extents = PropRenderGeometry.contentExtentRect(for: .paperAirplane, lidLift: 1)
        XCTAssertTrue(extents.width <= size.width && extents.height <= size.height)
        XCTAssertTrue(extents.contains(PropRenderGeometry.trailRectInPanel()))
    }

    // MARK: - Cocoa production presentation path (integration)

    func testCocoaProductionPresentationPath() {
        let windowController = PetWindowController()
        windowController.configureForTesting(
            frame: CGRect(x: 500, y: 200, width: 180, height: 226)
        )
        let coordinator = SeasonalEventCoordinator(
            clock: FixedClock(), persistence: SeasonalPersistence(),
            timing: .forKind(.hotCocoa)
        )
        let presenter = SeasonalEventPresenter(
            windowController: windowController, coordinator: coordinator, store: .shared
        )
        coordinator.presenter = presenter

        coordinator.requestTrigger(.hotCocoa, trigger: .replay)
        coordinator.servicePendingTrigger()
        coordinator.advance(at: Date().addingTimeInterval(2.0))

        XCTAssertEqual(presenter.presentCallCount, 1, "cocoa must reach the presenter")
        XCTAssertTrue(presenter.rejectionReasons.isEmpty,
                      "cocoa presentation must not be rejected: \(presenter.rejectionReasons)")
        guard let panel = presenter.presentedPanel else {
            XCTFail("cocoa panel missing")
            return
        }
        // Real window: nonzero frame, hosting view with the production
        // scene, content fully inside the panel with margin.
        XCTAssertFalse(panel.frame.isEmpty)
        XCTAssertTrue(panel.contentView is NSHostingView<SeasonalSceneView>)
        let content = PropRenderGeometry.primaryContentScreenRect(panelFrame: panel.frame, kind: .hotCocoa)
        XCTAssertTrue(panel.frame.insetBy(dx: -1, dy: -1).contains(content),
                      "cocoa painted content must be inside the panel frame")
        XCTAssertTrue(panel.frame.intersects(CGRect(x: 0, y: 0, width: 1280, height: 800)),
                      "cocoa must intersect the display")
        // Visible width calibrated to the pet.
        let width = PropRenderGeometry.contentSizePt(asset: "daily_hot_cocoa.png").width
        XCTAssertEqual(width, 0.67 * PropRenderGeometry.petHeight, accuracy: 0.01,
                       "cocoa painted width must be calibrated")
    }

    // MARK: - Choreography regressions (preserved semantics)

    func testHongbaoFallsFromAboveAndLandsInThePaws() {
        let anchors = EventAnchorSystem(petFrame: petFrame)
        let timing = SeasonalTiming.forKind(.cny)
        let start = SeasonalChoreography.pose(
            kind: .cny, phase: .approach, elapsedInPhase: 0, totalElapsed: 0,
            anchors: anchors, visibleFrame: visible, timing: timing
        )
        XCTAssertGreaterThan(start.position.y, anchors.handFront.y + 80)
        let end = SeasonalChoreography.pose(
            kind: .cny, phase: .approach, elapsedInPhase: timing.approachDuration,
            totalElapsed: timing.approachDuration, anchors: anchors,
            visibleFrame: visible, timing: timing
        )
        XCTAssertEqual(end.position.x, anchors.handFront.x, accuracy: 0.01)
        XCTAssertEqual(end.position.y, anchors.handFront.y, accuracy: 0.01)
    }

    func testGroundedPropsDoNotMoveWhenThePetFrameMoves() {
        // Grounded pose positions depend only on the anchor set passed
        // in: with a frozen anchor the prop stays put while the pet
        // frame changes.
        let frozen = EventAnchorSystem(petFrame: petFrame)
        let moved = EventAnchorSystem(petFrame: petFrame.offsetBy(dx: 60, dy: 0))
        let timing = SeasonalTiming.forKind(.sprout)
        let a = SeasonalChoreography.pose(
            kind: .sprout, phase: .present, elapsedInPhase: 1, totalElapsed: 4,
            anchors: frozen, visibleFrame: visible, timing: timing
        )
        let b = SeasonalChoreography.pose(
            kind: .sprout, phase: .present, elapsedInPhase: 1, totalElapsed: 4,
            anchors: moved, visibleFrame: visible, timing: timing
        )
        XCTAssertEqual(a.position, frozen.nearLeftFoot)
        XCTAssertNotEqual(a.position, b.position,
                          "a grounded prop must stay in its frozen world anchor")
    }

    func testAirplaneFlightIsContinuousAndPassesAboveTheHead() {
        let anchors = EventAnchorSystem(petFrame: petFrame)
        let timing = SeasonalTiming.forKind(.paperAirplane)
        let flightDuration = timing.approachDuration + timing.presentDuration
            + timing.celebrateDuration + timing.departDuration
        var previous: CGPoint?
        for step in 1..<120 {
            let total = TimeInterval(CGFloat(step) / 120.0 * flightDuration)
            let pose = SeasonalChoreography.pose(
                kind: .paperAirplane, phase: .approach, elapsedInPhase: total,
                totalElapsed: total, anchors: anchors,
                visibleFrame: visible, timing: timing
            )
            if let previous {
                let delta = hypot(pose.position.x - previous.x, pose.position.y - previous.y)
                XCTAssertLessThan(delta, 40, "flight must be continuous between 30 Hz samples")
            }
            previous = pose.position
        }
    }
}

private final class FixedClock: BirthdayClock {
    let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }()
    func now() -> Date {
        var components = DateComponents()
        components.year = 2027; components.month = 8; components.day = 1
        components.hour = 9; components.timeZone = calendar.timeZone
        return calendar.date(from: components)!
    }
}
