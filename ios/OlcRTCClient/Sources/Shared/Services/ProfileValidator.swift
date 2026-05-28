import Foundation

/// Pure profile validator. No I/O, no logging, no UI dependencies — safe
/// to call from anywhere (the URI importer, the subscription importer,
/// the ad-hoc Connect form, and the unit tests all share it).
///
/// Rules (see also `docs/uri.md` and ADR-0009):
///
/// - `provider` must be one of `OlcRTCProvider.allCases` (`jitsi`,
///   `telemost`, `wbstream`).
/// - `transport` must be one of `OlcRTCTransport.allCases`
///   (`datachannel`, `vp8channel`).
/// - `roomID` must not be empty (after trimming).
/// - `clientID` must not be empty (after trimming).
/// - `keyHex` must be exactly 64 lowercase or uppercase hex chars.
/// - `socksHost` must not be empty (after trimming).
/// - `socksPort` must parse to an Int in `1...65535`.
/// - `dnsServer` is optional — accepted as a free-form string for now.
///
/// All rules return a list of `Issue` values rather than throwing on the
/// first miss, so the UI can show every problem at once instead of
/// playing whack-a-mole.
public struct ProfileValidator: Sendable {
    public enum Field: String, Sendable {
        case provider
        case transport
        case roomID
        case clientID
        case keyHex
        case socksHost
        case socksPort
        case dnsServer
    }

    public struct Issue: Equatable, Sendable, CustomStringConvertible {
        public let field: Field
        public let message: String
        public init(field: Field, message: String) {
            self.field = field
            self.message = message
        }
        public var description: String { "\(field.rawValue): \(message)" }
    }

    public init() {}

    /// Validate a fully-typed profile. Convenience wrapper around the
    /// raw-string validator.
    public func validate(_ profile: OlcRTCProfile) -> [Issue] {
        validate(
            provider: profile.provider.rawValue,
            transport: profile.transport.rawValue,
            roomID: profile.roomID,
            clientID: profile.clientID,
            keyHex: profile.keyHex,
            socksHost: profile.socksHost,
            socksPortString: String(profile.socksPort),
            dnsServer: profile.dnsServer
        )
    }

    /// Validate raw form input. `socksPortString` is the raw text from
    /// the SOCKS port field; we parse it here so the validator can
    /// surface "not a number" as a field-level issue rather than
    /// silently falling back to a default at the call site.
    public func validate(
        provider: String,
        transport: String,
        roomID: String,
        clientID: String,
        keyHex: String,
        socksHost: String,
        socksPortString: String,
        dnsServer: String
    ) -> [Issue] {
        var issues: [Issue] = []

        if OlcRTCProvider(rawValue: provider) == nil {
            issues.append(Issue(
                field: .provider,
                message: "Provider must be one of: \(Self.allowedProviders)."
            ))
        }
        if OlcRTCTransport(rawValue: transport) == nil {
            issues.append(Issue(
                field: .transport,
                message: "Transport must be one of: \(Self.allowedTransports)."
            ))
        }
        if roomID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(Issue(field: .roomID, message: "Room ID is required."))
        }
        if clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(Issue(field: .clientID, message: "Client ID is required."))
        }
        if !Self.isValidKeyHex(keyHex) {
            issues.append(Issue(
                field: .keyHex,
                message: "Encryption key must be exactly 64 hex characters (0-9, a-f)."
            ))
        }
        if socksHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(Issue(field: .socksHost, message: "SOCKS host is required."))
        }
        if !Self.isValidPort(socksPortString) {
            issues.append(Issue(
                field: .socksPort,
                message: "SOCKS port must be a number in 1…65535."
            ))
        }
        // DNS server: optional free-form string for now. We deliberately
        // do not enforce `host:port` until the Go core surfaces a
        // canonical format.
        _ = dnsServer

        return issues
    }

    public static func isValidKeyHex(_ key: String) -> Bool {
        guard key.count == 64 else { return false }
        return key.allSatisfy { c in
            (c >= "0" && c <= "9") || (c >= "a" && c <= "f") || (c >= "A" && c <= "F")
        }
    }

    public static func isValidPort(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let n = Int(trimmed) else { return false }
        return (1...65535).contains(n)
    }

    private static let allowedProviders: String = OlcRTCProvider.allCases
        .map { $0.rawValue }
        .joined(separator: ", ")
    private static let allowedTransports: String = OlcRTCTransport.allCases
        .map { $0.rawValue }
        .joined(separator: ", ")
}
