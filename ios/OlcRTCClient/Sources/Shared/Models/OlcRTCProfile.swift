import Foundation

public enum OlcRTCProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case jitsi
    case telemost
    case wbstream

    public var id: String { rawValue }
    public var displayName: String { rawValue }
}

public enum OlcRTCTransport: String, CaseIterable, Codable, Identifiable, Sendable {
    case datachannel
    case vp8channel

    public var id: String { rawValue }
    public var displayName: String { rawValue }
}

public struct OlcRTCProfile: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var provider: OlcRTCProvider
    public var transport: OlcRTCTransport
    public var roomID: String
    public var clientID: String
    public var keyHex: String
    public var mimo: String?

    public var socksHost: String
    public var socksPort: Int
    public var dnsServer: String
    public var debug: Bool

    public var vp8FPS: Int?
    public var vp8BatchSize: Int?

    // Liveness probe configuration forwarded to
    // `MobileSetLivenessOptions(intervalMillis, timeoutMillis, failures)`.
    // Defaults match the Go core's defaults so that existing UI flows
    // (which don't yet expose these) keep behaving as before.
    public var livenessIntervalMillis: Int
    public var livenessTimeoutMillis: Int
    public var livenessFailures: Int

    public init(
        id: UUID = UUID(),
        name: String,
        provider: OlcRTCProvider,
        transport: OlcRTCTransport,
        roomID: String,
        clientID: String,
        keyHex: String,
        mimo: String? = nil,
        socksHost: String = "127.0.0.1",
        socksPort: Int = 8808,
        dnsServer: String = "8.8.8.8:53",
        debug: Bool = false,
        vp8FPS: Int? = nil,
        vp8BatchSize: Int? = nil,
        livenessIntervalMillis: Int = 30000,
        livenessTimeoutMillis: Int = 10000,
        livenessFailures: Int = 3
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.transport = transport
        self.roomID = roomID
        self.clientID = clientID
        self.keyHex = keyHex
        self.mimo = mimo
        self.socksHost = socksHost
        self.socksPort = socksPort
        self.dnsServer = dnsServer
        self.debug = debug
        self.vp8FPS = vp8FPS
        self.vp8BatchSize = vp8BatchSize
        self.livenessIntervalMillis = livenessIntervalMillis
        self.livenessTimeoutMillis = livenessTimeoutMillis
        self.livenessFailures = livenessFailures
    }

    // Custom decoder so previously-persisted profiles (without the
    // liveness fields) still decode cleanly with default values.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try c.decode(String.self, forKey: .name)
        self.provider = try c.decode(OlcRTCProvider.self, forKey: .provider)
        self.transport = try c.decode(OlcRTCTransport.self, forKey: .transport)
        self.roomID = try c.decode(String.self, forKey: .roomID)
        self.clientID = try c.decode(String.self, forKey: .clientID)
        self.keyHex = try c.decode(String.self, forKey: .keyHex)
        self.mimo = try c.decodeIfPresent(String.self, forKey: .mimo)
        self.socksHost = try c.decodeIfPresent(String.self, forKey: .socksHost) ?? "127.0.0.1"
        self.socksPort = try c.decodeIfPresent(Int.self, forKey: .socksPort) ?? 8808
        self.dnsServer = try c.decodeIfPresent(String.self, forKey: .dnsServer) ?? "8.8.8.8:53"
        self.debug = try c.decodeIfPresent(Bool.self, forKey: .debug) ?? false
        self.vp8FPS = try c.decodeIfPresent(Int.self, forKey: .vp8FPS)
        self.vp8BatchSize = try c.decodeIfPresent(Int.self, forKey: .vp8BatchSize)
        self.livenessIntervalMillis = try c.decodeIfPresent(Int.self, forKey: .livenessIntervalMillis) ?? 30000
        self.livenessTimeoutMillis = try c.decodeIfPresent(Int.self, forKey: .livenessTimeoutMillis) ?? 10000
        self.livenessFailures = try c.decodeIfPresent(Int.self, forKey: .livenessFailures) ?? 3
    }
}
