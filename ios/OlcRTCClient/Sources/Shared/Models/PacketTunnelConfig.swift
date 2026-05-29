import Foundation

/// Wire format for the configuration the container app hands to the
/// `PacketTunnelProvider` extension via
/// `NETunnelProviderProtocol.providerConfiguration` (a `[String: Any]`).
///
/// Today this struct is unused at runtime because the extension is a
/// stub. It exists so the container app and the extension share the
/// **same schema** the moment the Go runtime is wired in — the
/// container app will encode a `PacketTunnelConfig`, the extension
/// will decode it.
///
/// Notes:
/// - `keyHex` is included here because the extension needs it to drive
///   the Go runtime. It must **never** be logged. The shared
///   `LogSanitizer` masks 64-char hex runs defensively.
/// - Field names map onto the gomobile API surface (see
///   `mobile/mobile.go`): `Start`/`StartWithTransport` parameters and
///   the `Set*` configuration helpers.
public struct PacketTunnelConfig: Codable, Equatable, Sendable {
    public var provider: String      // OlcRTCProvider.rawValue
    public var transport: String     // OlcRTCTransport.rawValue
    public var roomID: String
    public var clientID: String
    public var keyHex: String

    public var socksHost: String
    public var socksPort: Int
    public var dnsServer: String
    public var debug: Bool

    public var vp8FPS: Int?
    public var vp8BatchSize: Int?

    public init(
        provider: String,
        transport: String,
        roomID: String,
        clientID: String,
        keyHex: String,
        socksHost: String,
        socksPort: Int,
        dnsServer: String,
        debug: Bool,
        vp8FPS: Int? = nil,
        vp8BatchSize: Int? = nil
    ) {
        self.provider = provider
        self.transport = transport
        self.roomID = roomID
        self.clientID = clientID
        self.keyHex = keyHex
        self.socksHost = socksHost
        self.socksPort = socksPort
        self.dnsServer = dnsServer
        self.debug = debug
        self.vp8FPS = vp8FPS
        self.vp8BatchSize = vp8BatchSize
    }
}

public extension PacketTunnelConfig {
    init(profile: OlcRTCProfile) {
        self.init(
            provider: profile.provider.rawValue,
            transport: profile.transport.rawValue,
            roomID: profile.roomID,
            clientID: profile.clientID,
            keyHex: profile.keyHex,
            socksHost: profile.socksHost,
            socksPort: profile.socksPort,
            dnsServer: profile.dnsServer,
            debug: profile.debug,
            vp8FPS: profile.vp8FPS,
            vp8BatchSize: profile.vp8BatchSize
        )
    }
}
