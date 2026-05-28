import SwiftUI

struct ConnectView: View {
    @EnvironmentObject private var state: AppState
    @State private var keyVisible = false
    @State private var advancedExpanded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    StatusCard(
                        mode: state.mode,
                        status: state.status,
                        lastError: state.lastError
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section("Mode") {
                    Picker("Mode", selection: $state.mode) {
                        ForEach(ConnectionMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(state.mode.shortDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack(spacing: 12) {
                        Button {
                            Task { await state.start() }
                        } label: {
                            Label("Start", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.status.isActive)

                        Button(role: .destructive) {
                            Task { await state.stop() }
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!state.status.isActive)
                    }
                    HStack(spacing: 12) {
                        Button {
                            state.check()
                        } label: {
                            Label("Check", systemImage: "checkmark.seal")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            Task { await state.ping() }
                        } label: {
                            Label("Ping", systemImage: "antenna.radiowaves.left.and.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Section("Profile") {
                    Picker("Provider", selection: $state.provider) {
                        ForEach(OlcRTCProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }

                    Picker("Transport", selection: $state.transport) {
                        ForEach(OlcRTCTransport.allCases) { transport in
                            Text(transport.displayName).tag(transport)
                        }
                    }

                    TextField("Room ID", text: $state.roomID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Client ID", text: $state.clientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    keyField
                }

                Section {
                    DisclosureGroup("Advanced", isExpanded: $advancedExpanded) {
                        TextField("SOCKS host", text: $state.socksHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        TextField("SOCKS port", text: $state.socksPort)
                            .keyboardType(.numberPad)

                        TextField("DNS server", text: $state.dnsServer)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Toggle("Debug logging", isOn: $state.debug)
                    }
                }
            }
            .navigationTitle("olcRTC")
        }
    }

    private var keyField: some View {
        HStack {
            Group {
                if keyVisible {
                    TextField("Encryption key (hex)", text: $state.keyHex)
                } else {
                    SecureField("Encryption key (hex)", text: $state.keyHex)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(.body, design: .monospaced))

            Button {
                keyVisible.toggle()
            } label: {
                Image(systemName: keyVisible ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(keyVisible ? "Hide encryption key" : "Show encryption key")
        }
    }
}

#Preview {
    ConnectView().environmentObject(AppState())
}
