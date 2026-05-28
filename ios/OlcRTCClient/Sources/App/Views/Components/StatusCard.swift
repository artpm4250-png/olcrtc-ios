import SwiftUI

struct StatusCard: View {
    let mode: ConnectionMode
    let status: TunnelStatus
    let lastError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 10, height: 10)
                Text(status.displayName)
                    .font(.headline)
                Spacer()
                Text(mode.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }

            if case let .running(endpoint?) = status {
                Text("Endpoint: \(endpoint)")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let error = lastError, !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Text(disclaimer)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var indicatorColor: Color {
        switch status {
        case .running: return .green
        case .starting, .stopping: return .yellow
        case .failed: return .red
        case .disconnected: return .gray
        }
    }

    private var disclaimer: String {
        switch mode {
        case .vpn:
            return "VPN Mode architecture only. Real-device runtime requires Apple signing + provisioning + NetworkExtension entitlement."
        case .localProxy:
            return "Local Proxy Mode is foreground only. iOS may suspend the app in the background."
        }
    }
}

#Preview {
    VStack {
        StatusCard(mode: .vpn, status: .disconnected, lastError: nil)
        StatusCard(mode: .localProxy, status: .running(endpoint: "127.0.0.1:8808"), lastError: nil)
        StatusCard(mode: .vpn, status: .failed(reason: "Not wired"), lastError: "Not wired")
    }
}
