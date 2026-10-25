import Foundation

/// Transport errors. HTTP status + server error code; the body itself is
/// never logged.
enum BottleMailAPIError: Error, Equatable {
    case network(String)
    case http(status: Int, code: String)
    case decoding(String)
    case invalidResponse
}

/// Remote letter shape (server JSON). `opened_at` is null until the
/// recipient opens the letter.
struct BottleMailRemoteLetter: Decodable, Equatable {
    let id: String
    let seq: Int
    let body: String
    let createdAt: String
    let openedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, seq, body
        case createdAt = "created_at"
        case openedAt = "opened_at"
    }
}

struct BottleMailPage: Equatable {
    let letters: [BottleMailRemoteLetter]
    let nextAfter: Int
}

/// The network contract. Production is `BottleMailAPI` (URLSession);
/// tests inject a mock — automated tests never depend on the Cloudflare
/// service being online.
protocol BottleMailAPITransport {
    func activate(code: String, label: String) async throws -> BottleMailActivation
    func fetchLetters(after: Int, limit: Int, token: String) async throws -> BottleMailPage
    func markOpened(id: String, token: String) async throws
}

/// URLSession + async/await implementation. Short per-request timeout;
/// all background work happens off the main thread.
final class BottleMailAPI: BottleMailAPITransport {
    let baseURL: URL
    private let session: URLSession

    /// Public, non-secret service address (Phase 8A deployment).
    static let defaultBaseURL = URL(string: "https://bottlemail.giftfor17.workers.dev")!

    init(baseURL: URL = BottleMailAPI.defaultBaseURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = 15
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func activate(code: String, label: String) async throws -> BottleMailActivation {
        let data = try await request(
            path: "/api/devices/activate",
            method: "POST",
            body: ["code": code, "label": label]
        )
        struct Response: Decodable {
            let deviceId: String
            let deviceToken: String
            let label: String
            enum CodingKeys: String, CodingKey {
                case deviceId = "device_id"
                case deviceToken = "device_token"
                case label
            }
        }
        let decoded: Response = try decode(data)
        return BottleMailActivation(
            deviceId: decoded.deviceId,
            deviceToken: decoded.deviceToken,
            label: decoded.label
        )
    }

    func fetchLetters(after: Int, limit: Int, token: String) async throws -> BottleMailPage {
        let data = try await request(
            path: "/api/letters?after=\(after)&limit=\(limit)",
            method: "GET",
            bearerToken: token
        )
        struct Response: Decodable {
            let letters: [BottleMailRemoteLetter]
            let nextAfter: Int
            enum CodingKeys: String, CodingKey {
                case letters
                case nextAfter = "next_after"
            }
        }
        let decoded: Response = try decode(data)
        return BottleMailPage(letters: decoded.letters, nextAfter: decoded.nextAfter)
    }

    func markOpened(id: String, token: String) async throws {
        _ = try await request(
            path: "/api/letters/\(id)/open",
            method: "POST",
            bearerToken: token
        )
    }

    // MARK: - Plumbing

    private func request(
        path: String,
        method: String,
        bearerToken: String? = nil
    ) async throws -> Data {
        try await request(path: path, method: method, body: Optional<Data>.none, bearerToken: bearerToken)
    }

    private func request<Body: Encodable>(
        path: String,
        method: String,
        body: Body?,
        bearerToken: String?
    ) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BottleMailAPIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw BottleMailAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode(ServerError.self, from: data))?.error ?? "unknown"
            throw BottleMailAPIError.http(status: http.statusCode, code: code)
        }
        return data
    }

    private struct ServerError: Decodable {
        let error: String?
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw BottleMailAPIError.decoding(error.localizedDescription)
        }
    }
}
