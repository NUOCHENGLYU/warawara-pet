import AppKit
import Foundation

/// Typed loader for the v2 birthday props and the letter text.
/// Resources live under Resources/Birthday and are bundled via
/// `.copy`, so the directory structure survives packaging. Candidates
/// mirror the sprite/rig loader strategy so dev and packaged builds
/// resolve identically. Missing/invalid assets degrade gracefully:
/// the prop is simply skipped (and logged) — never a crash.
final class BirthdayAssetStore {
    static let shared = BirthdayAssetStore()

    /// v2 prop basenames actually used by the app. Deliberately excludes
    /// candle_flame_standalone (the cake has a baked-in flame), the pink
    /// sparkles, sparkles_sheet and shooting star (kept sparse/muted).
    static let requiredFileNames = [
        "cake_lit.png",
        "envelope_closed.png",
        "envelope_open.png",
        "letter_paper_blank.png",
        "sparkle_gold_large.png",
        "sparkle_gold_lower.png",
        "sparkle_gold_star.png",
        "birthday_letter.txt"
    ]

    /// v2 SHA256 values from ASSET_MANIFEST.json (verification only).
    static let expectedSHA256: [String: String] = [
        "cake_lit.png": "53792b4cba7919fea6842a0c1617d21ea04c9a7308b266a2b4726f09a1160b02",
        "envelope_closed.png": "7019698ad9a7266a770ae9f52b7fb987c494c91851df864434fd598c29392470",
        "envelope_open.png": "50cc42a7376cc5786b9b3acfe5eba44543aab667b39320ff3d4a5d2e5e0bcdaa",
        "letter_paper_blank.png": "95cd1ec3b88fe8786ef22e29aa367903902078e6d0acd81f27c49ae26a9ecb97",
        "sparkle_gold_large.png": "2dd7ba88c8f5eb37941ec864e4021bb2a3ff55ccbb49dcb1d584aa6607a933c1",
        "sparkle_gold_lower.png": "b21afc54f285e75f95d1e2d9b83980315894f3e5bbb55aab991c228c0e3c0486",
        "sparkle_gold_star.png": "2709e4170f3f47065161b5dfc53483050c1bf50f21fa4d6ff4641cfb567262e6"
    ]

    private var imageCache: [String: NSImage] = [:]
    private var resolvedBaseURL: URL?

    /// Base URLs probed in order: SPM module bundle, main bundle
    /// Resources, explicit bundle path — each with a /Birthday suffix.
    static func candidateBaseURLs() -> [URL] {
        var roots: [URL] = []
        #if SWIFT_PACKAGE
        if let url = Bundle.module.resourceURL { roots.append(url) }
        #endif
        if let url = Bundle.main.resourceURL { roots.append(url) }
        roots.append(
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")
        )
        var result: [URL] = []
        for root in roots {
            result.append(root.appendingPathComponent("Birthday"))
        }
        return result
    }

    /// First candidate directory that exists (or contains any file).
    func resolveBaseURL() -> URL? {
        if let resolvedBaseURL { return resolvedBaseURL }
        for candidate in Self.candidateBaseURLs() {
            if FileManager.default.fileExists(atPath: candidate.path) {
                resolvedBaseURL = candidate
                return candidate
            }
        }
        return nil
    }

    func image(named fileName: String) -> NSImage? {
        if let cached = imageCache[fileName] { return cached }
        guard let base = resolveBaseURL() else { return nil }
        let url = base.appendingPathComponent(fileName)
        guard let image = NSImage(contentsOf: url) else { return nil }
        imageCache[fileName] = image
        return image
    }

    func data(for fileName: String) -> Data? {
        guard let base = resolveBaseURL() else { return nil }
        return try? Data(contentsOf: base.appendingPathComponent(fileName))
    }

    /// The personal letter as UTF-8 text; nil when absent.
    func letterText() -> String? {
        guard let data = data(for: "birthday_letter.txt") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// True when every required file is present and decodable.
    func verifyAllRequiredAssets() -> (ok: Bool, details: String) {
        var missing: [String] = []
        var undecodable: [String] = []
        for name in Self.requiredFileNames {
            guard let data = data(for: name) else {
                missing.append(name)
                continue
            }
            if name.hasSuffix(".png") {
                if image(named: name) == nil {
                    undecodable.append(name)
                }
            } else if name == "birthday_letter.txt" {
                if String(data: data, encoding: .utf8) == nil {
                    undecodable.append(name)
                }
            }
        }
        if missing.isEmpty && undecodable.isEmpty {
            return (true, "all \(Self.requiredFileNames.count) assets present")
        }
        return (false, "missing: \(missing) undecodable: \(undecodable)")
    }

    /// SHA256 verification against the v2 manifest (diagnostics/tests).
    func verifySHA256() -> (ok: Bool, details: String) {
        var mismatches: [String] = []
        var missing: [String] = []
        for (name, expected) in Self.expectedSHA256 {
            guard let data = data(for: name) else {
                missing.append(name)
                continue
            }
            let actual = BirthdaySHA256.hash(data)
            if actual != expected {
                mismatches.append(name)
            }
        }
        if mismatches.isEmpty && missing.isEmpty {
            return (true, "all \(Self.expectedSHA256.count) hashes match")
        }
        return (false, "mismatched: \(mismatches) missing: \(missing)")
    }

    func reset() {
        imageCache.removeAll()
        resolvedBaseURL = nil
    }
}

/// Minimal SHA256 over Data (CryptoKit-free for older toolchains).
enum BirthdaySHA256 {
    static func hash(_ data: Data) -> String {
        data.withUnsafeBytes { raw -> String in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return "" }
            var state: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32) =
                (0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19)
            var buffer = [UInt8](repeating: 0, count: 64)
            var bitLength: UInt64 = UInt64(data.count) * 8
            var offset = 0
            while data.count - offset >= 64 {
                buffer.withUnsafeMutableBufferPointer { buf in
                    _ = memcpy(buf.baseAddress, base + offset, 64)
                }
                sha256Block(buffer, &state)
                offset += 64
            }
            let remaining = data.count - offset
            var final = [UInt8](repeating: 0, count: 64)
            if remaining > 0 {
                _ = memcpy(&final, base + offset, remaining)
            }
            final[remaining] = 0x80
            if remaining >= 56 {
                sha256Block(final, &state)
                final = [UInt8](repeating: 0, count: 64)
            }
            for i in 0..<8 {
                final[56 + i] = UInt8((bitLength >> UInt64(56 - i * 8)) & 0xff)
            }
            sha256Block(final, &state)
            let words = [state.0, state.1, state.2, state.3, state.4, state.5, state.6, state.7]
            var out = ""
            for word in words {
                out += String(format: "%08x", word)
            }
            return out
        }
    }

    private static func sha256Block(
        _ block: [UInt8],
        _ state: inout (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)
    ) {
        let k: [UInt32] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
            0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
            0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
            0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
            0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
            0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
            0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
            0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
            0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
        ]
        var w = [UInt32](repeating: 0, count: 64)
        for i in 0..<16 {
            w[i] = (UInt32(block[i * 4]) << 24)
                | (UInt32(block[i * 4 + 1]) << 16)
                | (UInt32(block[i * 4 + 2]) << 8)
                | UInt32(block[i * 4 + 3])
        }
        for i in 16..<64 {
            let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
            let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
            w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
        }
        var a = state.0, b = state.1, c = state.2, d = state.3
        var e = state.4, f = state.5, g = state.6, h = state.7
        for i in 0..<64 {
            let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
            let ch = (e & f) ^ ((~e) & g)
            let t1 = h &+ s1 &+ ch &+ k[i] &+ w[i]
            let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
            let maj = (a & b) ^ (a & c) ^ (b & c)
            let t2 = s0 &+ maj
            h = g; g = f; f = e; e = d &+ t1
            d = c; c = b; b = a; a = t1 &+ t2
        }
        state.0 &+= a; state.1 &+= b; state.2 &+= c; state.3 &+= d
        state.4 &+= e; state.5 &+= f; state.6 &+= g; state.7 &+= h
    }

    private static func rotr(_ value: UInt32, _ amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}
