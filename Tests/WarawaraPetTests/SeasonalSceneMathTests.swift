import XCTest
@testable import WarawaraPet

/// Anchor conversion, content-bounds clipping, and choreography tests.
/// These are the regressions for the three user-visible failures:
/// lower-left placement, clipped artwork, and generic entrances.
final class SeasonalSceneMathTests: XCTestCase {
    /// A typical pet frame (resting position, screen coords).
    private let petFrame = CGRect(x: 600, y: 120, width: 180, height: 226)
    private let visible = CGRect(x: 0, y: 0, width: 1280, height: 800)

    // MARK: - Anchors

    func testAnchorsAreLocalToThePetBody() {
        let anchors = EventAnchorSystem(petFrame: petFrame)
        let body = anchors.bodyRect
        // Every anchor sits near the character geometry, never at a
        // screen corner.
        for anchor in [anchors.handFront, anchors.headCenter, anchors.aboveHead,
                       anchors.groundBesidePet, anchors.nearLeftFoot,
                       anchors.nearRightFoot, anchors.umbrellaGrip] {
            XCTAssertTrue(anchor.x > body.minX - 60 && anchor.x < body.maxX + 80,
                          "anchor \(anchor) must stay beside the body")
            XCTAssertTrue(anchor.y >= body.minY - 10 && anchor.y <= body.maxY + 60,
                          "anchor \(anchor) must stay at body height")
        }
        XCTAssertEqual(anchors.handFront.x, body.midX)
        XCTAssertTrue(anchors.aboveHead.y > anchors.headCenter.y)
        XCTAssertTrue(anchors.groundBesidePet.x > body.maxX)
        XCTAssertTrue(anchors.nearLeftFoot.x < body.minX)
    }

    // MARK: - No lower-left regression

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
            let origin = SeasonalSceneMath.origin(anchoredAt: target, kind: kind)
            let size = SeasonalSceneMath.panelSize(for: kind)
            let extents = SeasonalSceneMath.contentExtentRect(for: kind)
            // The CONTACT point lands exactly on the world anchor.
            let contactX = origin.x + size.width / 2 + extents.midX
            let contactY = origin.y + size.height / 2 + extents.midY
            XCTAssertEqual(contactX, target.x, accuracy: 0.01, "\(kind): contact must land on the anchor")
            XCTAssertEqual(contactY, target.y, accuracy: 0.01, "\(kind): contact must land on the anchor")
            // Far from the screen's bottom-left corner.
            XCTAssertGreaterThan(contactX, 200, "\(kind): never in the lower-left corner")
            XCTAssertGreaterThan(contactY, 80, "\(kind): never in the lower-left corner")
        }
    }

    // MARK: - Clipping: painted content must fit its panel

    func testPaintedContentFitsInsidePanelForEveryKind() {
        for kind in SeasonalEventKind.allCases {
            let size = SeasonalSceneMath.panelSize(for: kind)
            let extents = SeasonalSceneMath.contentExtentRect(for: kind)
            // Panel rect in the same coordinates (contact at 0,0).
            let panelMinX = -size.width / 2 - extents.midX
            let panelMaxX = size.width / 2 - extents.midX
            let panelMinY = -size.height / 2 - extents.midY
            let panelMaxY = size.height / 2 - extents.midY
            XCTAssertGreaterThan(extents.minX, panelMinX + 1, "\(kind): content clipped left")
            XCTAssertLessThan(extents.maxX, panelMaxX - 1, "\(kind): content clipped right")
            XCTAssertGreaterThan(extents.minY, panelMinY + 1, "\(kind): content clipped bottom")
            XCTAssertLessThan(extents.maxY, panelMaxY - 1, "\(kind): content clipped top")
        }
    }

    func testHongbaoAndGiftContentIsFullyVisible() {
        // The two reported clipping cases: red envelope + Christmas gift.
        for kind in [SeasonalEventKind.cny, .christmas] {
            let size = SeasonalSceneMath.panelSize(for: kind)
            let extents = SeasonalSceneMath.contentExtentRect(for: kind)
            let panelMinX = -size.width / 2 - extents.midX
            let panelMaxX = size.width / 2 - extents.midX
            let panelMinY = -size.height / 2 - extents.midY
            let panelMaxY = size.height / 2 - extents.midY
            XCTAssertGreaterThan(extents.minX, panelMinX + 1,
                                 "\(kind): envelope/gift must not be clipped left")
            XCTAssertLessThan(extents.maxX, panelMaxX - 1,
                              "\(kind): envelope/gift must not be clipped right")
            XCTAssertGreaterThan(extents.minY, panelMinY + 1,
                                 "\(kind): envelope/gift must not be clipped at the bottom")
            XCTAssertLessThan(extents.maxY, panelMaxY - 1,
                              "\(kind): envelope/gift must not be clipped at the top")
        }
        // The gift CONTACT point must be its bottom edge: the drawn
        // content bottom lands exactly on the contact (0,0).
        let giftRect = SeasonalSceneMath.contentRectInPanel(for: .christmas)
        XCTAssertEqual(giftRect.maxY, 0, accuracy: 0.5,
                       "gift bottom must rest on the anchor")
    }

    func testPanelClampKeepsPanelsVisibleOnMultiMonitorBounds() {
        // Pet near the screen edge: the clamp must keep the panel on
        // screen WITHOUT snapping it to a corner.
        let edgePet = CGRect(x: 30, y: 600, width: 180, height: 226)
        let anchors = EventAnchorSystem(petFrame: edgePet)
        let kind = SeasonalEventKind.hotCocoa
        let size = SeasonalSceneMath.panelSize(for: kind)
        let origin = SeasonalSceneMath.origin(anchoredAt: anchors.nearRightFoot, kind: kind)
        let clamped = SeasonalSceneMath.clampedOrigin(origin, panelSize: size, visibleFrame: visible)
        XCTAssertGreaterThanOrEqual(clamped.x, visible.minX + 4 - 0.01)
        XCTAssertLessThanOrEqual(clamped.x + size.width, visible.maxX - 4 + 0.01)
        XCTAssertGreaterThanOrEqual(clamped.y, visible.minY + 4 - 0.01)
        XCTAssertLessThanOrEqual(clamped.y + size.height, visible.maxY - 4 + 0.01)
    }

    // MARK: - Choreography: entrances + interactions

    func testHongbaoFallsFromAboveAndLandsInThePaws() {
        let anchors = EventAnchorSystem(petFrame: petFrame)
        let timing = SeasonalTiming.forKind(.cny)
        let start = SeasonalChoreography.pose(
            kind: .cny, phase: .approach, elapsedInPhase: 0, totalElapsed: 0,
            anchors: anchors, visibleFrame: visible, timing: timing
        )
        XCTAssertGreaterThan(start.position.y, anchors.handFront.y + 80,
                             "the envelope must start well above the pet")
        XCTAssertGreaterThan(start.position.x, anchors.handFront.x - 30)

        let end = SeasonalChoreography.pose(
            kind: .cny, phase: .approach, elapsedInPhase: timing.approachDuration,
            totalElapsed: timing.approachDuration, anchors: anchors,
            visibleFrame: visible, timing: timing
        )
        XCTAssertEqual(end.position.x, anchors.handFront.x, accuracy: 0.01,
                       "the caught envelope rests in the paws")
        XCTAssertEqual(end.position.y, anchors.handFront.y, accuracy: 0.01)
    }

    func testHongbaoOpensOnlyInCelebrateWithOpenArtwork() {
        let anchors = EventAnchorSystem(petFrame: petFrame)
        let timing = SeasonalTiming.forKind(.cny)
        let held = SeasonalChoreography.pose(
            kind: .cny, phase: .present, elapsedInPhase: 1, totalElapsed: 5,
            anchors: anchors, visibleFrame: visible, timing: timing
        )
        XCTAssertEqual(held.asset, "cny_hongbao.png", "closed while held")
        XCTAssertEqual(held.lidLift, 0)

        let early = SeasonalChoreography.pose(
            kind: .cny, phase: .celebrate, elapsedInPhase: 0.1, totalElapsed: 9,
            anchors: anchors, visibleFrame: visible, timing: timing
        )
        XCTAssertEqual(early.asset, "cny_hongbao.png", "anticipation beat keeps it closed")

        let opened = SeasonalChoreography.pose(
            kind: .cny, phase: .celebrate, elapsedInPhase: 1.6, totalElapsed: 10.5,
            anchors: anchors, visibleFrame: visible, timing: timing
        )
        XCTAssertEqual(opened.asset, "cny_hongbao_open.png", "opened state must use the v3 artwork")
    }

    func testGiftLidLiftsSmoothlyWithBaseAndLidLayers() {
        let anchors = EventAnchorSystem(petFrame: petFrame)
        let timing = SeasonalTiming.forKind(.christmas)
        let before = SeasonalChoreography.pose(
            kind: .christmas, phase: .present, elapsedInPhase: 2, totalElapsed: 6,
            anchors: anchors, visibleFrame: visible, timing: timing
        )
        XCTAssertEqual(before.asset, "xmas_gift.png")
        XCTAssertEqual(before.lidLift, 0)

        var lastLift: CGFloat = 0
        var monotonic = true
        for step in 0...20 {
            let elapsed = 0.1 + 1.2 * CGFloat(step) / 20.0
            let pose = SeasonalChoreography.pose(
                kind: .christmas, phase: .celebrate, elapsedInPhase: elapsed, totalElapsed: 10,
                anchors: anchors, visibleFrame: visible, timing: timing
            )
            XCTAssertEqual(pose.asset, "xmas_gift_open_base.png", "open base during the lift")
            if pose.lidLift < lastLift { monotonic = false }
            lastLift = pose.lidLift
        }
        XCTAssertTrue(monotonic, "lid lift must advance monotonically")
        XCTAssertEqual(lastLift, 1, accuracy: 0.001, "lid fully lifted")
    }

    func testUmbrellaRaisesCanopyAboveHeadAndReturns() {
        let anchors = EventAnchorSystem(petFrame: petFrame)
        let timing = SeasonalTiming.forKind(.umbrella)
        let approachEnd = SeasonalChoreography.pose(
            kind: .umbrella, phase: .approach, elapsedInPhase: timing.approachDuration,
            totalElapsed: timing.approachDuration, anchors: anchors,
            visibleFrame: visible, timing: timing
        )
        // Handle reached the grip anchor during approach.
        XCTAssertEqual(approachEnd.position.x, anchors.umbrellaGrip.x, accuracy: 0.5)
        XCTAssertEqual(approachEnd.position.y, anchors.umbrellaGrip.y, accuracy: 0.5)

        let raised = SeasonalChoreography.pose(
            kind: .umbrella, phase: .present, elapsedInPhase: 1.4,
            totalElapsed: timing.approachDuration + 1.4, anchors: anchors,
            visibleFrame: visible, timing: timing
        )
        // Handle settles at the paws; canopy covers the head.
        XCTAssertEqual(raised.position.x, anchors.handFront.x + 4, accuracy: 0.5)
        XCTAssertEqual(raised.position.y, anchors.handFront.y + 2, accuracy: 0.5)
        XCTAssertGreaterThan(raised.effectAlpha, 0, "imaginary drizzle overlay must run")
        XCTAssertEqual(raised.effectAsset, "rain_drops_overlay.png")

        let retired = SeasonalChoreography.pose(
            kind: .umbrella, phase: .depart, elapsedInPhase: timing.departDuration,
            totalElapsed: 30, anchors: anchors, visibleFrame: visible, timing: timing
        )
        XCTAssertEqual(retired.alpha, 0, accuracy: 0.01, "umbrella retires")
    }

    func testCocoaLiftsTowardTheFaceThenReturnsToThePaw() {
        let anchors = EventAnchorSystem(petFrame: petFrame)
        let timing = SeasonalTiming.forKind(.hotCocoa)
        let rest = SeasonalChoreography.pose(
            kind: .hotCocoa, phase: .approach, elapsedInPhase: timing.approachDuration,
            totalElapsed: timing.approachDuration, anchors: anchors,
            visibleFrame: visible, timing: timing
        )
        XCTAssertEqual(rest.position.x, anchors.nearRightFoot.x, accuracy: 0.01)

        let lifted = SeasonalChoreography.pose(
            kind: .hotCocoa, phase: .present, elapsedInPhase: timing.presentDuration * 0.5,
            totalElapsed: 6, anchors: anchors, visibleFrame: visible, timing: timing
        )
        XCTAssertGreaterThan(lifted.position.y, anchors.nearRightFoot.y,
                             "the mug must rise toward the face mid-present")
        XCTAssertLessThan(lifted.position.x, anchors.nearRightFoot.x,
                          "the mug moves inward toward the face")

        let back = SeasonalChoreography.pose(
            kind: .hotCocoa, phase: .celebrate, elapsedInPhase: 0.5, totalElapsed: 12,
            anchors: anchors, visibleFrame: visible, timing: timing
        )
        XCTAssertEqual(back.position.x, anchors.nearRightFoot.x, accuracy: 0.01,
                       "the mug returns to the paw after the sip")
    }

    func testSproutGrowsAndSwaysAtTheFeet() {
        let anchors = EventAnchorSystem(petFrame: petFrame)
        let timing = SeasonalTiming.forKind(.sprout)
        let start = SeasonalChoreography.pose(
            kind: .sprout, phase: .approach, elapsedInPhase: 0, totalElapsed: 0,
            anchors: anchors, visibleFrame: visible, timing: timing
        )
        XCTAssertLessThan(start.scale, 1, "the sprout emerges, not teleports")

        let full = SeasonalChoreography.pose(
            kind: .sprout, phase: .present, elapsedInPhase: 2.0, totalElapsed: 6,
            anchors: anchors, visibleFrame: visible, timing: timing
        )
        XCTAssertEqual(full.scale, 1, accuracy: 0.01)
        XCTAssertEqual(full.position.x, anchors.nearLeftFoot.x, accuracy: 0.01)
        XCTAssertEqual(full.position.y, anchors.nearLeftFoot.y, accuracy: 0.01)
        XCTAssertNotEqual(full.rotationDegrees, 0, "the leaf sways")
    }

    func testAirplaneFlightIsContinuousAndPassesAboveTheHead() {
        let anchors = EventAnchorSystem(petFrame: petFrame)
        let timing = SeasonalTiming.forKind(.paperAirplane)
        let flightDuration = timing.approachDuration + timing.presentDuration
            + timing.celebrateDuration + timing.departDuration

        var previous: CGPoint?
        var sawNearHead = false
        let headY = anchors.headCenter.y + 26
        for step in 0...120 {
            let t = CGFloat(step) / 120.0
            let total = TimeInterval(t * flightDuration)
            let pose = SeasonalChoreography.pose(
                kind: .paperAirplane, phase: .approach, elapsedInPhase: total,
                totalElapsed: total, anchors: anchors,
                visibleFrame: visible, timing: timing
            )
            if let previous {
                let delta = hypot(pose.position.x - previous.x, pose.position.y - previous.y)
                XCTAssertLessThan(delta, 40, "flight must be continuous between 30 Hz samples")
            }
            if abs(pose.position.x - anchors.headCenter.x) < 260,
               pose.position.y > headY - 40 {
                sawNearHead = true
            }
            XCTAssertTrue(pose.showTrail, "the trail must be shown behind the plane")
            previous = pose.position
        }
        XCTAssertTrue(sawNearHead, "the flight must pass near the head")
        let first = SeasonalChoreography.pose(
            kind: .paperAirplane, phase: .approach, elapsedInPhase: 0, totalElapsed: 0,
            anchors: anchors, visibleFrame: visible, timing: timing
        )
        XCTAssertLessThan(first.position.x, visible.minX, "enters from off-screen left")
        let last = SeasonalChoreography.pose(
            kind: .paperAirplane, phase: .depart, elapsedInPhase: timing.departDuration,
            totalElapsed: flightDuration, anchors: anchors, visibleFrame: visible, timing: timing
        )
        XCTAssertGreaterThan(last.position.x, visible.maxX, "exits beyond the right edge")
        XCTAssertEqual(last.alpha, 0, accuracy: 0.01, "fades out at the exit")
    }

    func testAttentionTargetsFollowTheProps() {
        let anchors = EventAnchorSystem(petFrame: petFrame)
        let timing = SeasonalTiming.forKind(.paperAirplane)
        let flightDuration = timing.approachDuration + timing.presentDuration
            + timing.celebrateDuration + timing.departDuration

        var previous: CGPoint?
        for step in 1..<40 {
            let total = TimeInterval(CGFloat(step) / 40.0 * flightDuration)
            guard let target = SeasonalChoreography.attentionTarget(
                kind: .paperAirplane, phase: .approach, elapsedInPhase: total,
                totalElapsed: total, anchors: anchors,
                visibleFrame: visible, timing: timing
            ) else {
                XCTFail("attention target must exist while flying")
                continue
            }
            if let previous {
                XCTAssertNotEqual(target, previous, "attention must move with the plane")
            }
            previous = target
        }
        // Released on depart.
        XCTAssertNil(SeasonalChoreography.attentionTarget(
            kind: .cny, phase: .depart, elapsedInPhase: 2,
            totalElapsed: 30, anchors: anchors, visibleFrame: visible, timing: timing
        ))
    }

    // MARK: - Optional v3 assets

    func testOptionalAssetsResolveAndMatchManifest() {
        let store = SeasonalAssetStore.shared
        store.reset()
        let verify = store.verifyOptionalAssets()
        XCTAssertTrue(verify.ok, verify.details)
        let present = store.optionalAssetsPresent()
        XCTAssertEqual(present.present, present.total,
                       "all \(present.total) CelFilm v3 optional assets must be packaged")
        for name in SeasonalAssetStore.optionalFileNames {
            XCTAssertNotNil(store.optionalImage(named: name), "\(name) must decode")
        }
        // The v1 originals are untouched.
        XCTAssertEqual(store.image(named: "cny_hongbao.png").map { _ in true } ?? false, true)
    }
}
