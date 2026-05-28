import Foundation

public enum ConnectionMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case vpn
    case localProxy

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vpn: return "VPN Mode"
        case .localProxy: return "Local Proxy Mode"
        }
    }

    public var shortDescription: String {
        switch self {
        case .vpn:
            return "System VPN via NetworkExtension. Requires a signed build to actually run on a real iPhone."
        case .localProxy:
            return "Foreground local SOCKS endpoint for third-party VPN/proxy apps and testing. Not background-reliable on iOS."
        }
    }
}
