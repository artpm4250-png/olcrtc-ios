import Foundation

/// Scrubs known-sensitive substrings before a log line reaches the UI
/// or any persistent log sink. See ADR-0010.
///
/// Sanitization is defensive: we do not trust upstream code (Go core,
/// SDK helpers) to mask secrets. Anything that reaches this type is
/// assumed potentially sensitive.
///
/// Rules applied (in order):
///
/// 1. Replace any 64-char hex run with `<keyHex:masked>`. olcRTC keys
///    are 32-byte hex, but we accept 32+ char hex defensively.
/// 2. Replace any full `olcrtc://...` URI with `<olcrtc-uri:masked>`
///    because the URI carries the encryption key.
/// 3. Mask query/body fragments that look like `password=...` or
///    `keyHex=...` (case-insensitive).
public struct LogSanitizer {
    public init() {}

    public func sanitize(_ line: String) -> String {
        var result = line
        result = Self.maskHexRuns(result)
        result = Self.maskOlcRTCURIs(result)
        result = Self.maskKeyValueSecrets(result)
        return result
    }

    private static let hexRunRegex: NSRegularExpression = {
        // 32+ hex chars in a row — defensive (real keys are 64).
        try! NSRegularExpression(pattern: "[0-9a-fA-F]{32,}", options: [])
    }()

    private static func maskHexRuns(_ input: String) -> String {
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return hexRunRegex.stringByReplacingMatches(
            in: input,
            options: [],
            range: range,
            withTemplate: "<keyHex:masked>"
        )
    }

    private static let olcrtcURIRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: "olcrtc://[^\\s]+", options: [])
    }()

    private static func maskOlcRTCURIs(_ input: String) -> String {
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return olcrtcURIRegex.stringByReplacingMatches(
            in: input,
            options: [],
            range: range,
            withTemplate: "<olcrtc-uri:masked>"
        )
    }

    private static let kvRegex: NSRegularExpression = {
        // Match keyHex=... / password=... / pass=... up to whitespace or quote.
        try! NSRegularExpression(
            pattern: "(?i)(keyHex|password|passwd|pass|secret)\\s*=\\s*([^\\s\"']+)",
            options: []
        )
    }()

    private static func maskKeyValueSecrets(_ input: String) -> String {
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return kvRegex.stringByReplacingMatches(
            in: input,
            options: [],
            range: range,
            withTemplate: "$1=<masked>"
        )
    }
}
