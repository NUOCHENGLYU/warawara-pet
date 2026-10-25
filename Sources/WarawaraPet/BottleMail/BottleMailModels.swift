import Foundation

/// A letter as the macOS app stores it locally. `openedAt` is nil until
/// the server CONFIRMS the open (the `/open` call succeeds) — receiving a
/// letter is never treated as reading it.
struct BottleMailLetter: Codable, Equatable, Hashable, Identifiable {
    let seq: Int
    let id: String
    let body: String
    let createdAt: String
    var openedAt: String?
    let receivedAt: Date

    var isUnread: Bool { openedAt == nil }
}

/// Persisted mailbox snapshot (the JSON file layout).
struct BottleMailMailbox: Codable, Equatable {
    var version: Int = 1
    var cursorSeq: Int = 0
    var letters: [BottleMailLetter] = []
}

/// Activation result from the server.
struct BottleMailActivation: Equatable {
    let deviceId: String
    let deviceToken: String
    let label: String
}

/// The device credential stored in the Keychain (token only — never
/// logged, never persisted to the mailbox file).
struct BottleMailCredential: Codable, Equatable {
    let deviceId: String
    let token: String
    let label: String
}

enum BottleMailActivationState: Equatable {
    case notActivated
    case activating
    case activated(label: String)
    /// The sender revoked this device: polling stops, the old token is
    /// discarded, but previously received letters stay readable.
    case revoked
}

/// User-facing activation failure.
enum BottleMailActivationError: Error, Equatable {
    case invalidCode
    case codeUsed
    case codeExpired
    case network(String)
    case server(String)

    var message: String {
        switch self {
        case .invalidCode: return "激活码无效，请检查后重试。"
        case .codeUsed: return "这个激活码已经被使用过了。"
        case .codeExpired: return "这个激活码已过期，请在发信网页生成新的。"
        case .network: return "网络错误，请稍后重试。"
        case .server: return "服务器暂时不可用，请稍后重试。"
        }
    }
}
