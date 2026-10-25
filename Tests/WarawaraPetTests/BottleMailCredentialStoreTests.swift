import Foundation
import XCTest
@testable import WarawaraPet

/// Credential storage: the in-memory stand-in plus a best-effort real
/// Keychain round-trip (skipped when the CI keychain refuses writes —
/// the production path is identical code, only the storage differs).
final class BottleMailCredentialStoreTests: XCTestCase {
    func testInMemoryStoreRoundTrip() throws {
        let store = InMemoryBottleMailCredentialStore()
        XCTAssertNil(store.loadCredential())
        try store.saveCredential(BottleMailCredential(deviceId: "d", token: "tok", label: "Mac"))
        XCTAssertEqual(store.loadCredential()?.token, "tok")
        store.clearCredential()
        XCTAssertNil(store.loadCredential())
    }

    func testKeychainRoundTripWhenAvailable() throws {
        let store = KeychainBottleMailCredentialStore(
            service: "warawarapet.tests.bottlemail.\(UUID().uuidString)",
            account: "device-credential"
        )
        store.clearCredential()
        let credential = BottleMailCredential(deviceId: "d", token: "tok", label: "Mac")
        do {
            try store.saveCredential(credential)
        } catch {
            throw XCTSkip("keychain unavailable in this environment: \(error)")
        }
        defer { store.clearCredential() }
        XCTAssertEqual(store.loadCredential(), credential)
        store.clearCredential()
        XCTAssertNil(store.loadCredential())
    }
}
