import SwiftUI

struct AboutView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section("What this is") {
                    Text("Standalone iOS client for olcRTC. Dual-mode by design: a foreground Local Proxy Mode that exposes a local SOCKS endpoint and a system VPN Mode built on a NetworkExtension PacketTunnelProvider.")
                }

                Section("Local Proxy Mode (wired)") {
                    Text("Local Proxy Mode is wired to the real gomobile-backed olcRTC runtime via OlcRTCMobile.xcframework. Start exposes a SOCKS endpoint (default 127.0.0.1:8808) for third-party VPN/proxy apps and manual proxy configuration.")
                    Text("iOS may suspend the foreground app's process in the background, including when another VPN app is active. Local Proxy Mode is therefore not background-reliable.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("VPN Mode (scaffold / stub)") {
                    Text("VPN Mode is architected but not wired. The PacketTunnelProvider extension exists, embeds, and fails fast with notWiredYet — it does not link the Go runtime and does not pretend to tunnel anything in this build.")
                    Text("Wiring it into NEPacketTunnelNetworkSettings + the Go runtime is a later step, gated on signing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Unsigned IPA") {
                    Text("CI produces an unsigned IPA artifact (OlcRTCClient-unsigned-ipa). Treat it as a CI / later-signing artifact for inspection — not as a runnable VPN on a stock iPhone.")
                }

                Section("Real-device VPN requirements") {
                    bullet("A paid Apple Developer account.")
                    bullet("A provisioning profile scoped to the PacketTunnelProvider extension.")
                    bullet("The com.apple.developer.networking.networkextension entitlement.")
                    bullet("A signed build of both the app and the extension.")
                    Text("None of the above are configured in this build.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Privacy") {
                    bullet("keyHex is masked before reaching the log view.")
                    bullet("olcrtc:// URIs are masked because they carry the key.")
                    bullet("Passwords are masked in any key=value form.")
                    bullet("Subscription import never logs the raw line or the URI.")
                }
            }
            .navigationTitle("About")
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•")
            Text(text)
        }
    }
}

#Preview {
    AboutView()
}
