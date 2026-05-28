import SwiftUI

struct ConnectView: View {
    @EnvironmentObject private var state: AppState
    @State private var keyVisible = false
    @State private var advancedExpanded = false
    @State private var showSaveSheet = false
    @State private var newProfileName = ""

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

                    if state.mode == .vpn {
                        // VPN Mode is still a stub. Tell the user before
                        // they try to Start.
                        Label(
                            "VPN Mode is scaffold only until signing + provisioning + NetworkExtension entitlement are in place.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }
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
                        .disabled(state.status.isActive || !state.canStart)

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

                    if !state.validationIssues.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(state.validationIssues, id: \.description) { issue in
                                Label(issue.message, systemImage: "exclamationmark.circle")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }

                Section("Profile") {
                    Picker("Provider", selection: $state.provider) {
                        ForEach(OlcRTCProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .onChange(of: state.provider) { _ in state.refreshValidation() }

                    Picker("Transport", selection: $state.transport) {
                        ForEach(OlcRTCTransport.allCases) { transport in
                            Text(transport.displayName).tag(transport)
                        }
                    }
                    .onChange(of: state.transport) { _ in state.refreshValidation() }

                    fieldRow(field: .roomID, label: "Room ID") {
                        TextField("Room ID", text: $state.roomID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: state.roomID) { _ in state.refreshValidation() }
                    }

                    fieldRow(field: .clientID, label: "Client ID") {
                        TextField("Client ID", text: $state.clientID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: state.clientID) { _ in state.refreshValidation() }
                    }

                    fieldRow(field: .keyHex, label: "Encryption key") {
                        keyField
                    }

                    Button {
                        newProfileName = state.profiles.isEmpty
                            ? "Profile"
                            : "Profile \(state.profiles.count + 1)"
                        showSaveSheet = true
                    } label: {
                        Label("Save as profile…", systemImage: "square.and.arrow.down")
                    }
                    .disabled(!state.canStart)
                }

                Section {
                    DisclosureGroup("Advanced", isExpanded: $advancedExpanded) {
                        fieldRow(field: .socksHost, label: "SOCKS host") {
                            TextField("SOCKS host", text: $state.socksHost)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onChange(of: state.socksHost) { _ in state.refreshValidation() }
                        }

                        fieldRow(field: .socksPort, label: "SOCKS port") {
                            TextField("SOCKS port", text: $state.socksPort)
                                .keyboardType(.numberPad)
                                .onChange(of: state.socksPort) { _ in state.refreshValidation() }
                        }

                        TextField("DNS server", text: $state.dnsServer)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Toggle("Debug logging", isOn: $state.debug)
                    }
                }
            }
            .navigationTitle("olcRTC")
            .sheet(isPresented: $showSaveSheet) {
                saveProfileSheet
            }
        }
    }

    @ViewBuilder
    private func fieldRow<Content: View>(
        field: ProfileValidator.Field,
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
            if let message = state.validationMessage(for: field) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityLabel("\(label) error: \(message)")
            }
        }
    }

    private var keyField: some View {
        HStack {
            Group {
                if keyVisible {
                    TextField("Encryption key (64 hex chars)", text: $state.keyHex)
                } else {
                    SecureField("Encryption key (64 hex chars)", text: $state.keyHex)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(.body, design: .monospaced))
            .onChange(of: state.keyHex) { _ in state.refreshValidation() }

            Button {
                keyVisible.toggle()
            } label: {
                Image(systemName: keyVisible ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(keyVisible ? "Hide encryption key" : "Show encryption key")
        }
    }

    private var saveProfileSheet: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Profile name", text: $newProfileName)
                        .textInputAutocapitalization(.words)
                }
                Section {
                    Text("The profile stores provider, transport, room, client ID, encryption key, and local proxy settings. Profiles are kept in the app's Application Support directory (not in the App Group container — that requires signing).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Save profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showSaveSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if state.saveCurrentProfile(name: newProfileName) {
                            showSaveSheet = false
                        }
                    }
                    .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    ConnectView().environmentObject(AppState())
}
