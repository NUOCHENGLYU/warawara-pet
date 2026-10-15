import AppKit
import XCTest
@testable import WarawaraPet

/// Asset, letter, and packaging verification for the v2 birthday props.
final class BirthdayAssetTests: XCTestCase {
    override func setUp() {
        super.setUp()
        BirthdayAssetStore.shared.reset()
    }

    override func tearDown() {
        BirthdayAssetStore.shared.reset()
        super.tearDown()
    }

    func testAllRequiredAssetsResolveAndDecode() {
        let result = BirthdayAssetStore.shared.verifyAllRequiredAssets()
        XCTAssertTrue(result.ok, "required v2 assets must be bundled: \(result.details)")
    }

    func testSHA256MatchesV2Manifest() {
        let result = BirthdayAssetStore.shared.verifySHA256()
        XCTAssertTrue(result.ok, "v2 hashes must match ASSET_MANIFEST.json: \(result.details)")
    }

    func testNoStandaloneFlameOverlay() {
        // The cake has a baked-in flame; the standalone flame must never
        // be part of the app asset set.
        XCTAssertFalse(
            BirthdayAssetStore.requiredFileNames.contains("candle_flame_standalone.png"),
            "do not overlay a second flame"
        )
        XCTAssertNil(BirthdayAssetStore.shared.image(named: "candle_flame_standalone.png"))
    }

    func testMainPropsAreTransparentPNGs() {
        for name in ["cake_lit.png", "envelope_closed.png", "envelope_open.png", "letter_paper_blank.png"] {
            guard let image = BirthdayAssetStore.shared.image(named: name) else {
                XCTFail("\(name) missing")
                continue
            }
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else {
                XCTFail("\(name) not decodable")
                continue
            }
            let corner = rep.colorAt(x: 0, y: 0)?.alphaComponent ?? 0
            XCTAssertEqual(corner, 0, accuracy: 0.01, "\(name) must be transparent at the corner")
            XCTAssertGreaterThan(rep.pixelsWide, 500, "\(name) must be full-size artwork")
        }
    }

    func testLetterTextLoadsAsUTF8WithChineseAndEnglish() {
        guard let text = BirthdayAssetStore.shared.letterText() else {
            XCTFail("birthday_letter.txt missing")
            return
        }
        XCTAssertGreaterThan(text.count, 20)
        XCTAssertTrue(text.contains("生日快乐"), "letter must support Chinese")
        XCTAssertTrue(text.contains("placeholder") || text.contains("占位"), "placeholder marker must be present until the user supplies the final text")
    }

    func testLetterSurvivesLongUnicodeRoundTrip() {
        let sample = String(repeating: "亲爱的朋友，生日快乐！🎂\n", count: 40)
        let data = sample.data(using: .utf8)!
        let decoded = String(data: data, encoding: .utf8)
        XCTAssertEqual(decoded, sample, "long UTF-8 paragraphs must round-trip")
    }

    func testSHA256ImplementationMatchesKnownVector() {
        // "abc" -> ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
        let data = "abc".data(using: .utf8)!
        XCTAssertEqual(
            BirthdaySHA256.hash(data),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }
}
