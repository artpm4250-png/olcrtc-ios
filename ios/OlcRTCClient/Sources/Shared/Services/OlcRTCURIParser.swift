import Foundation

/// Parses `olcrtc://` URIs per `docs/uri.md`.
///
/// Grammar (from the spec):
///
///     olcrtc://<Auth>?<Transport>[<key=value&...>]@<RoomID>#<EncryptionKey>[$<MIMO>]
///
/// - `<Auth>` — provider name (`jitsi`, `telemost`, `wbstream`, ...).
/// - `<Transport>` — transport name (`datachannel`, `vp8channel`, ...).
/// - Optional `<...>` block after the transport name carries
///   transport-specific parameters as `key=value&key=value`.
/// - `<RoomID>` — room identifier; for `jitsi` this can be a full
///   `https://host/room` URL containing `:` and `/`, so the parser
///   reads RoomID as everything between `@` and the **last** `#`.
/// - `<EncryptionKey>` — hex key, typically 64 chars.
/// - Optional `$<MIMO>` — free-form client-side comment.
///
/// This parser is intentionally pure (no I/O, no logging) so it is safe
/// to call from anywhere. It never logs `keyHex`. Sanitization for
/// log output is the responsibility of `LogSanitizer`.
public struct OlcRTCURIParser {
    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case wrongScheme
        case missingTransportSeparator
        case missingRoomSeparator
        case missingKeySeparator
        case unknownProvider(String)
        case unknownTransport(String)
        case malformedTransportPayload(String)
        case emptyField(String)

        public var description: String {
            switch self {
            case .wrongScheme:
                return "URI must start with olcrtc://"
            case .missingTransportSeparator:
                return "Missing '?' between provider and transport"
            case .missingRoomSeparator:
                return "Missing '@' before room ID"
            case .missingKeySeparator:
                return "Missing '#' before encryption key"
            case .unknownProvider(let name):
                return "Unknown provider: \(name)"
            case .unknownTransport(let name):
                return "Unknown transport: \(name)"
            case .malformedTransportPayload(let value):
                return "Malformed transport payload: \(value)"
            case .emptyField(let field):
                return "Empty field: \(field)"
            }
        }
    }

    public struct Parsed: Equatable {
        public var provider: OlcRTCProvider
        public var transport: OlcRTCTransport
        public var transportPayload: [String: String]
        public var roomID: String
        public var keyHex: String
        public var mimo: String?
    }

    public init() {}

    public func parse(_ uri: String) throws -> Parsed {
        let scheme = "olcrtc://"
        guard uri.hasPrefix(scheme) else {
            throw ParseError.wrongScheme
        }
        let body = String(uri.dropFirst(scheme.count))

        guard let questionIdx = body.firstIndex(of: "?") else {
            throw ParseError.missingTransportSeparator
        }
        let authPart = String(body[body.startIndex..<questionIdx])
        let afterAuth = String(body[body.index(after: questionIdx)...])

        guard let atIdx = afterAuth.firstIndex(of: "@") else {
            throw ParseError.missingRoomSeparator
        }
        let transportPart = String(afterAuth[afterAuth.startIndex..<atIdx])
        let afterTransport = String(afterAuth[afterAuth.index(after: atIdx)...])

        // RoomID may contain ":" and "/" (jitsi URLs), so split on the LAST "#".
        guard let hashIdx = afterTransport.lastIndex(of: "#") else {
            throw ParseError.missingKeySeparator
        }
        let roomPart = String(afterTransport[afterTransport.startIndex..<hashIdx])
        let afterRoom = String(afterTransport[afterTransport.index(after: hashIdx)...])

        let keyPart: String
        let mimoPart: String?
        if let dollarIdx = afterRoom.firstIndex(of: "$") {
            keyPart = String(afterRoom[afterRoom.startIndex..<dollarIdx])
            mimoPart = String(afterRoom[afterRoom.index(after: dollarIdx)...])
        } else {
            keyPart = afterRoom
            mimoPart = nil
        }

        let provider = try parseProvider(authPart)
        let (transport, payload) = try parseTransport(transportPart)

        if roomPart.isEmpty { throw ParseError.emptyField("RoomID") }
        if keyPart.isEmpty { throw ParseError.emptyField("EncryptionKey") }

        return Parsed(
            provider: provider,
            transport: transport,
            transportPayload: payload,
            roomID: roomPart,
            keyHex: keyPart,
            mimo: mimoPart
        )
    }

    private func parseProvider(_ raw: String) throws -> OlcRTCProvider {
        if raw.isEmpty { throw ParseError.emptyField("Auth") }
        guard let value = OlcRTCProvider(rawValue: raw) else {
            throw ParseError.unknownProvider(raw)
        }
        return value
    }

    private func parseTransport(_ raw: String) throws -> (OlcRTCTransport, [String: String]) {
        if raw.isEmpty { throw ParseError.emptyField("Transport") }

        // Optional payload in angle brackets right after the transport name.
        if let openIdx = raw.firstIndex(of: "<") {
            guard let closeIdx = raw.lastIndex(of: ">"), closeIdx > openIdx else {
                throw ParseError.malformedTransportPayload(raw)
            }
            let name = String(raw[raw.startIndex..<openIdx])
            let payloadRaw = String(raw[raw.index(after: openIdx)..<closeIdx])
            guard let transport = OlcRTCTransport(rawValue: name) else {
                throw ParseError.unknownTransport(name)
            }
            return (transport, try parsePayload(payloadRaw))
        }

        guard let transport = OlcRTCTransport(rawValue: raw) else {
            throw ParseError.unknownTransport(raw)
        }
        return (transport, [:])
    }

    private func parsePayload(_ raw: String) throws -> [String: String] {
        if raw.isEmpty { return [:] }
        var out: [String: String] = [:]
        for pair in raw.split(separator: "&", omittingEmptySubsequences: false) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty else {
                throw ParseError.malformedTransportPayload(String(pair))
            }
            out[String(parts[0])] = String(parts[1])
        }
        return out
    }
}

public extension OlcRTCURIParser.Parsed {
    /// Materialize a profile from a parsed URI. The caller supplies a
    /// display name (the URI format itself does not carry one).
    func toProfile(name: String) -> OlcRTCProfile {
        var profile = OlcRTCProfile(
            name: name,
            provider: provider,
            transport: transport,
            roomID: roomID,
            clientID: "",
            keyHex: keyHex,
            mimo: mimo
        )
        if transport == .vp8channel {
            if let fps = transportPayload["vp8-fps"].flatMap(Int.init) {
                profile.vp8FPS = fps
            }
            if let batch = transportPayload["vp8-batch"].flatMap(Int.init) {
                profile.vp8BatchSize = batch
            }
        }
        return profile
    }
}
