import Foundation
import XCTest
@testable import WarawaraPet

/// URLSession layer coverage through a URLProtocol mock: the REAL
/// BottleMailAPI code path (encoding, headers, decoding, status
/// mapping) without any network dependency.
final class BottleMailAPITests: XCTestCase {
    final class MockURLProtocol: URLProtocol {
        static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = MockURLProtocol.handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            do {
                let (status, headers, data) = try handler(request)
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: headers
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private func makeAPI() -> BottleMailAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return BottleMailAPI(
            baseURL: URL(string: "https://bottlemail.test")!,
            session: session
        )
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testActivateDecodesTheCredential() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/devices/activate")
            XCTAssertEqual(request.httpMethod, "POST")
            // URLSession may hand the protocol the body as a stream —
            // read whichever form is present.
            let bodyData: Data?
            if let body = request.httpBody {
                bodyData = body
            } else if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var data = Data()
                let bufferSize = 1024
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let read = stream.read(buffer, maxLength: bufferSize)
                    if read <= 0 { break }
                    data.append(buffer, count: read)
                }
                bodyData = data
            } else {
                bodyData = nil
            }
            let body = bodyData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            XCTAssertTrue(body.contains("\"code\":\"CODE12345\""), "unexpected body: \(body)")
            let data = Data("""
            {"device_id":"dev-1","device_token":"tok-1","label":"Mac"}
            """.utf8)
            return (201, ["Content-Type": "application/json"], data)
        }
        let result = try await makeAPI().activate(code: "CODE12345", label: "Mac")
        XCTAssertEqual(result.deviceId, "dev-1")
        XCTAssertEqual(result.deviceToken, "tok-1")
        XCTAssertEqual(result.label, "Mac")
    }

    func testActivateMapsConflictStatus() async {
        MockURLProtocol.handler = { _ in
            (409, ["Content-Type": "application/json"], Data(#"{"error":"code_used"}"#.utf8))
        }
        do {
            _ = try await makeAPI().activate(code: "CODE", label: "Mac")
            XCTFail("expected error")
        } catch let error as BottleMailAPIError {
            XCTAssertEqual(error, .http(status: 409, code: "code_used"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testFetchLettersSendsCursorLimitAndBearerAndDecodes() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/letters")
            XCTAssertEqual(request.url?.query, "after=7&limit=50")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
            let data = Data("""
            {"letters":[{"id":"a","seq":8,"body":"你好","created_at":"2026-10-17T00:00:00Z","opened_at":null}],
             "next_after":8}
            """.utf8)
            return (200, ["Content-Type": "application/json"], data)
        }
        let page = try await makeAPI().fetchLetters(after: 7, limit: 50, token: "tok")
        XCTAssertEqual(page.nextAfter, 8)
        XCTAssertEqual(page.letters.count, 1)
        XCTAssertEqual(page.letters[0].body, "你好")
        XCTAssertNil(page.letters[0].openedAt)
    }

    func testMarkOpenedPostsAndDecodesOpenedAt() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/letters/l-1/open")
            XCTAssertEqual(request.httpMethod, "POST")
            return (200, ["Content-Type": "application/json"], Data(#"{"id":"l-1","opened_at":"2026-10-17T01:00:00Z","already_opened":false}"#.utf8))
        }
        let openedAt = try await makeAPI().markOpened(id: "l-1", token: "tok")
        XCTAssertEqual(openedAt, "2026-10-17T01:00:00Z")
    }

    func testServerErrorMapsToHTTPStatus() async {
        MockURLProtocol.handler = { _ in
            (500, ["Content-Type": "application/json"], Data(#"{"error":"internal_error"}"#.utf8))
        }
        do {
            _ = try await makeAPI().fetchLetters(after: 0, limit: 50, token: "tok")
            XCTFail("expected error")
        } catch let error as BottleMailAPIError {
            XCTAssertEqual(error, .http(status: 500, code: "internal_error"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testNetworkFailureMapsToNetworkError() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await makeAPI().fetchLetters(after: 0, limit: 50, token: "tok")
            XCTFail("expected error")
        } catch let error as BottleMailAPIError {
            guard case .network = error else {
                return XCTFail("expected network error, got \(error)")
            }
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
