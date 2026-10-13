import XCTest
@testable import WarawaraPet

final class WarawaraSpriteManifestTests: XCTestCase {
    private var validJSON: Data {
        let manifest = WarawaraSpriteManifest(
            version: 1,
            layout: .init(
                canvas: CGSize(width: 200, height: 226),
                anchor: CGPoint(x: 0.5, y: 0.5),
                bodyBounds: CGRect(x: 0.26, y: 0.24, width: 0.48, height: 0.52)
            ),
            animations: [
                "idle": .init(frames: ["idle_00.png", "idle_01.png"], frameDuration: 0.5, loop: true),
                "hop": .init(frames: ["hop_00.png"], frameDuration: 0.1, loop: false)
            ]
        )
        return try! JSONEncoder().encode(manifest)
    }

    func testValidManifestDecodesAndValidates() {
        let decoded = try? JSONDecoder().decode(WarawaraSpriteManifest.self, from: validJSON)
        XCTAssertNotNil(decoded)
        XCTAssertNotNil(decoded.flatMap { WarawaraSpriteManifest.validated($0) })
    }

    func testCommittedManifestShapeDecodesFromInlineJSON() throws {
        // Mirrors the exact shape of the committed sprites.json so a
        // decode failure here proves the problem is struct-side, not
        // file-side.
        let json = """
        {"version":1,"layout":{"canvas":{"width":200,"height":226},\
        "anchor":{"x":0.5,"y":0.5},\
        "bodyBounds":{"x":0.26,"y":0.239,"width":0.48,"height":0.522}},\
        "animations":{"idle":{"frames":["idle/idle_00.png","idle/idle_01.png"],\
        "frameDuration":0.6,"loop":true},"hop":{"frames":["hop/hop_00.png",\
        "hop/hop_01.png","hop/hop_02.png"],"frameDuration":0.08,"loop":false},\
        "float":{"frames":["float/float_00.png","float/float_01.png",\
        "float/float_02.png"],"frameDuration":0.15,"loop":true},\
        "curious":{"frames":["curious/curious_00.png"],"frameDuration":0.1,\
        "loop":false},"clicked":{"frames":["clicked/clicked_00.png"],\
        "frameDuration":0.1,"loop":false},"dragged":{"frames":["dragged/dragged_00.png"],\
        "frameDuration":0.1,"loop":false},"settling":{"frames":["settling/settling_00.png"],\
        "frameDuration":0.1,"loop":false},"sleepy":{"frames":["sleepy/sleepy_00.png"],\
        "frameDuration":0.1,"loop":false},"sleeping":{"frames":["sleeping/sleeping_00.png"],\
        "frameDuration":0.1,"loop":false},"wake":{"frames":["wake/wake_00.png"],\
        "frameDuration":0.1,"loop":false}}}
        """
        let decoded = try JSONDecoder().decode(WarawaraSpriteManifest.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.animations.count, 10)
        XCTAssertNotNil(WarawaraSpriteManifest.validated(decoded))
    }

    func testWrongVersionIsRejected() {
        let manifest = WarawaraSpriteManifest(
            version: 2,
            layout: .init(canvas: CGSize(width: 100, height: 100), anchor: CGPoint(x: 0.5, y: 0.5), bodyBounds: CGRect(x: 0, y: 0, width: 1, height: 1)),
            animations: ["idle": .init(frames: ["a.png"], frameDuration: 0.1, loop: true)]
        )
        XCTAssertNil(WarawaraSpriteManifest.validated(manifest))
    }

    func testZeroCanvasIsRejected() {
        let manifest = WarawaraSpriteManifest(
            version: 1,
            layout: .init(canvas: .zero, anchor: CGPoint(x: 0.5, y: 0.5), bodyBounds: CGRect(x: 0, y: 0, width: 1, height: 1)),
            animations: ["idle": .init(frames: ["a.png"], frameDuration: 0.1, loop: true)]
        )
        XCTAssertNil(WarawaraSpriteManifest.validated(manifest))
    }

    func testOutOfRangeAnchorIsRejected() {
        let manifest = WarawaraSpriteManifest(
            version: 1,
            layout: .init(canvas: CGSize(width: 100, height: 100), anchor: CGPoint(x: 1.5, y: 0.5), bodyBounds: CGRect(x: 0, y: 0, width: 1, height: 1)),
            animations: ["idle": .init(frames: ["a.png"], frameDuration: 0.1, loop: true)]
        )
        XCTAssertNil(WarawaraSpriteManifest.validated(manifest))
    }

    func testOutOfRangeBodyBoundsAreRejected() {
        let manifest = WarawaraSpriteManifest(
            version: 1,
            layout: .init(canvas: CGSize(width: 100, height: 100), anchor: CGPoint(x: 0.5, y: 0.5), bodyBounds: CGRect(x: 0.5, y: 0.5, width: 0.9, height: 0.9)),
            animations: ["idle": .init(frames: ["a.png"], frameDuration: 0.1, loop: true)]
        )
        XCTAssertNil(WarawaraSpriteManifest.validated(manifest))
    }

    func testEmptyAnimationsAreRejected() {
        let manifest = WarawaraSpriteManifest(
            version: 1,
            layout: .init(canvas: CGSize(width: 100, height: 100), anchor: CGPoint(x: 0.5, y: 0.5), bodyBounds: CGRect(x: 0, y: 0, width: 1, height: 1)),
            animations: [:]
        )
        XCTAssertNil(WarawaraSpriteManifest.validated(manifest))
    }

    func testEmptyFramesOrZeroDurationAreRejected() {
        let manifest = WarawaraSpriteManifest(
            version: 1,
            layout: .init(canvas: CGSize(width: 100, height: 100), anchor: CGPoint(x: 0.5, y: 0.5), bodyBounds: CGRect(x: 0, y: 0, width: 1, height: 1)),
            animations: [
                "bad1": .init(frames: [], frameDuration: 0.1, loop: true),
                "bad2": .init(frames: ["a.png"], frameDuration: 0, loop: true)
            ]
        )
        XCTAssertNil(WarawaraSpriteManifest.validated(manifest))
    }
}

final class WarawaraAnimationMapperTests: XCTestCase {
    private let loop = WarawaraSpriteManifest.Animation(
        frames: ["a.png", "b.png", "c.png"], frameDuration: 0.5, loop: true
    )
    private let hold = WarawaraSpriteManifest.Animation(
        frames: ["a.png", "b.png"], frameDuration: 0.25, loop: false
    )

    func testEveryPetStateMapsToAVisualState() {
        for petState in [PetState.idle, .hop, .float, .curious, .clicked, .dragged, .settling, .sleepy, .sleeping] {
            let visual = WarawaraVisualState.state(for: petState)
            XCTAssertEqual(WarawaraAnimationMapper.animationKey(for: visual), visual.rawValue)
        }
    }

    func testLoopingFrameIndexCycles() {
        XCTAssertEqual(WarawaraAnimationMapper.frameIndex(at: 0.0, animation: loop), 0)
        XCTAssertEqual(WarawaraAnimationMapper.frameIndex(at: 0.5, animation: loop), 1)
        XCTAssertEqual(WarawaraAnimationMapper.frameIndex(at: 1.0, animation: loop), 2)
        XCTAssertEqual(WarawaraAnimationMapper.frameIndex(at: 1.5, animation: loop), 0)
        XCTAssertEqual(WarawaraAnimationMapper.frameIndex(at: 100.0, animation: loop), 2)
    }

    func testNonLoopingFrameIndexHoldsFinalFrame() {
        XCTAssertEqual(WarawaraAnimationMapper.frameIndex(at: 0.0, animation: hold), 0)
        XCTAssertEqual(WarawaraAnimationMapper.frameIndex(at: 0.3, animation: hold), 1)
        XCTAssertEqual(WarawaraAnimationMapper.frameIndex(at: 10.0, animation: hold), 1)
    }

    func testSingleFrameAnimationIsStable() {
        let single = WarawaraSpriteManifest.Animation(frames: ["only.png"], frameDuration: 0.1, loop: true)
        for time in stride(from: 0.0, through: 5.0, by: 0.37) {
            XCTAssertEqual(WarawaraAnimationMapper.frameIndex(at: time, animation: single), 0)
        }
    }

    func testAnimationInterruptionProducesValidIndices() {
        // Switching animations at any moment must always yield a valid
        // frame index (interruption safety).
        for time in stride(from: 0.0, through: 4.0, by: 0.13) {
            let index = WarawaraAnimationMapper.frameIndex(at: time, animation: loop)
            XCTAssertTrue((0..<loop.frames.count).contains(index))
        }
    }

    func testRenderSizeScalesCanvasByBodyHeight() {
        let canvas = CGSize(width: 200, height: 226)
        let size = WarawaraAnimationMapper.renderSize(
            canvas: canvas, bodyHeightInCanvas: 118, targetBodyHeight: 59
        )
        XCTAssertEqual(size.height, 113, accuracy: 0.01)
        XCTAssertEqual(size.width, 100, accuracy: 0.01)
    }

    func testSpriteRenderSizesForMainAndCompanionBodyHeights() {
        // The character view scales the manifest canvas so the artwork's
        // body height matches each character class: main 118 pt,
        // companion 74 pt.
        let canvas = CGSize(width: 200, height: 226)
        let mainSize = WarawaraAnimationMapper.renderSize(
            canvas: canvas, bodyHeightInCanvas: 118, targetBodyHeight: PetMetrics.blobHeight
        )
        XCTAssertEqual(mainSize.height, 226, accuracy: 0.01)
        XCTAssertEqual(mainSize.width, 200, accuracy: 0.01)

        let companionSize = WarawaraAnimationMapper.renderSize(
            canvas: canvas, bodyHeightInCanvas: 118, targetBodyHeight: CompanionMetrics.blobHeight
        )
        XCTAssertEqual(companionSize.height, 226 * 74 / 118, accuracy: 0.01)
    }
}
