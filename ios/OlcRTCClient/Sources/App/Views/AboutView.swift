import SwiftUI

struct AboutView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section("What this is") {
                    Text("This is the iOS VPN client architecture for olcRTC. It is shaped like a real Apple VPN client: a SwiftUI container app plus a NetworkExtension PacketTunnelProvider target managed via NETunnelProviderManager.")
                }

                Section("Unsigned IPA") {
                    Text("Today CI produces an unsigned IPA. Treat it as a build / later-signing artifact for inspection — not as a runnable VPN on a stock iPhone.")
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

                Section("Local Proxy Mode") {
                    Text("Local Proxy Mode runs olcRTC inside the foreground app and exposes a local SOCKS endpoint (e.g. 127.0.0.1:8808) for third-party VPN/proxy apps and manual proxy configuration.")
                    Text("iOS may suspend a foreground app's process in the background, including when another VPN app is active. Running another VPN does not guarantee iOS keeps this app alive. Local Proxy Mode is therefore not background-reliable.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Background-safe runtime") {
                    Text("The only background-safe proxy/VPN runtime on iOS is inside a NetworkExtension provider. That is what VPN Mode is for. Until signing is in place, VPN Mode exists as architecture only.")
                }

                Section("Privacy") {
                    bullet("keyHex is masked before reaching the log view.")
                    bullet("olcrtc:// URIs are masked because they carry the key.")
                    bullet("Passwords are masked in any key=value form.")
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
