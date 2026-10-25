import Foundation

/// A letter as the macOS app stores it locally. `openedAt` is nil until
/// the server CONFIRMS the open (the `/open` call succeeds) — receiving a
/// letter is never treated as reading it. `delivered` records that the
/// delivery event was ACKNOWLEDGED by the UI (Phase 8C) — it is what
/// guarantees exactly-once delivery across restarts.
struct BottleMailLetter: Codable, Equatable, Hashable, Identifiable {
    let seq: Int
    let id: String
    let body: String
    let createdAt: String
    var openedAt: String?
    let receivedAt: Date
    var delivered: Bool

    var isUnread: Bool { openedAt == nil }

    enum CodingKeys: String, CodingKey {
        case seq, id, body, createdAt, openedAt, receivedAt, delivered
    }

    /// Backward compatible: mailboxes written by Phase 8B have no
    /// `delivered` key — such letters are treated as not yet delivered,
    /// so they are re-enqueued exactly once after the upgrade.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seq = try container.decode(Int.self, forKey: .seq)
        id = try container.decode(String.self, forKey: .id)
        body = try container.decode(String.self, forKey: .body)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        openedAt = try container.decodeIfPresent(String.self, forKey: .openedAt)
        receivedAt = try container.decode(Date.self, forKey: .receivedAt)
        delivered = try container.decodeIfPresent(Bool.self, forKey: .delivered) ?? false
    }
}

/// One consumable delivery event (Phase 8C consumes these). A letter is
/// removed from the delivery queue ONLY when the UI acknowledges it,
/// which persists `delivered` so a restart never re-delivers.
struct PendingBottleDelivery: Equatable, Identifiable {
    let id: String
    let letter: BottleMailLetter
}

/// Persisted mailbox snapshot (the JSON file layout).
struct BottleMailMailbox: Codable, Equatable {
    var version: Int = 1
    var cursorSeq: Int = 0
    var letters: [BottleMailLetter] = []
    /// True while the device was revoked by the sender. Lets a restart
    /// distinguish "revoked (letters stay readable, no syncing)" from
    /// "never activated (show the activation form)".
    var isRevoked: Bool = false

    enum CodingKeys: String, CodingKey {
        case version, cursorSeq, letters, isRevoked
    }

    /// Backward compatible: Phase 8B mailboxes have no `isRevoked` key.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        cursorSeq = try container.decode(Int.self, forKey: .cursorSeq)
        letters = try container.decode([BottleMailLetter].self, forKey: .letters)
        isRevoked = try container.decodeIfPresent(Bool.self, forKey: .isRevoked) ?? false
    }

    init(version: Int = 1, cursorSeq: Int = 0, letters: [BottleMailLetter] = [], isRevoked: Bool = false) {
        self.version = version
        self.cursorSeq = cursorSeq
        self.letters = letters
        self.isRevoked = isRevoked
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(cursorSeq, forKey: .cursorSeq)
        try container.encode(letters, forKey: .letters)
        try container.encode(isRevoked, forKey: .isRevoked)
    }
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
