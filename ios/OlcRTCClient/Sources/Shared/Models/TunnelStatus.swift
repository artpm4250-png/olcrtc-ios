import Foundation

public enum TunnelStatus: Equatable, Sendable {
    case disconnected
    case starting
    case running(endpoint: String?)
    case stopping
    case failed(reason: String)

    public var isActive: Bool {
        switch self {
        case .running:
            return true
        case .disconnected, .starting, .stopping, .failed:
            return false
        }
    }

    public var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .starting: return "Starting…"
        case .running: return "Running"
        case .stopping: return "Stopping…"
        case .failed: return "Failed"
        }
    }
}
