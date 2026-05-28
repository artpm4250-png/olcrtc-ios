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
        vp8BatchSize: Int? = nil
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
    }
}
