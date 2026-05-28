import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject private var state: AppState

    @State private var showURISheet = false
    @State private var showSubscriptionSheet = false
    @State private var uriDraft = ""
    @State private var subscriptionDraft = ""
    @State private var isImportingSubscription = false
    @State private var lastSubscriptionSummary: String?

    var body: some View {
        NavigationStack {
            Group {
                if state.profiles.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Profiles")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            uriDraft = ""
                            showURISheet = true
                        } label: {
                            Label("Import olcrtc:// URI", systemImage: "link")
                        }
                        Button {
                            subscriptionDraft = ""
                            lastSubscriptionSummary = nil
                            showSubscriptionSheet = true
                        } label: {
                            Label("Import subscription URL", systemImage: "tray.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Add profile")
                    }
                }
            }
            .sheet(isPresented: $showURISheet) {
                uriImportSheet
            }
            .sheet(isPresented: $showSubscriptionSheet) {
                subscriptionImportSheet
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No profiles yet")
                .font(.headline)
            Text("Import an olcrtc:// URI, paste a subscription URL, or use Save as profile… on the Connect tab.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            HStack {
                Button {
                    uriDraft = ""
                    showURISheet = true
                } label: {
                    Label("Paste URI", systemImage: "link")
                }
                .buttonStyle(.bordered)
                Button {
                    subscriptionDraft = ""
                    lastSubscriptionSummary = nil
                    showSubscriptionSheet = true
                } label: {
                    Label("Subscription", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(state.profiles) { profile in
                row(for: profile)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        state.selectProfile(profile)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            state.deleteProfile(profile)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            .onDelete { offsets in
                state.deleteProfiles(at: offsets)
            }
        }
    }

    private func row(for profile: OlcRTCProfile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(profile.name)
                        .font(.headline)
                    if state.selectedProfileID == profile.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                            .imageScale(.small)
                            .accessibilityLabel("Currently selected")
                    }
                }
                HStack(spacing: 8) {
                    Text(profile.provider.displayName)
                    Text("·")
                    Text(profile.transport.displayName)
                    Text("·")
                    Text(profile.roomID)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Sheets

    private var uriImportSheet: some View {
        NavigationStack {
            Form {
                Section("olcrtc:// URI") {
                    TextField("olcrtc://provider?transport@room#key$name", text: $uriDraft, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(3...6)
                    Text("The URI carries the encryption key. It is parsed locally; the full URI is never written to logs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Import URI")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showURISheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        let added = state.importURI(uriDraft)
                        if added > 0 { showURISheet = false }
                    }
                    .disabled(uriDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var subscriptionImportSheet: some View {
        NavigationStack {
            Form {
                Section("Subscription URL") {
                    TextField("https://example.com/sub.txt", text: $subscriptionDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(.footnote, design: .monospaced))
                    Text("Each non-empty line of the response body is parsed as a separate olcrtc:// URI. Comment lines starting with # are ignored. Invalid lines are skipped, not fatal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let summary = lastSubscriptionSummary {
                    Section("Last import") {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Import subscription")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showSubscriptionSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isImportingSubscription ? "Importing…" : "Import") {
                        guard !isImportingSubscription else { return }
                        isImportingSubscription = true
                        let url = subscriptionDraft
                        Task {
                            let outcome = await state.importSubscription(urlString: url)
                            isImportingSubscription = false
                            if let outcome {
                                lastSubscriptionSummary =
                                    "\(outcome.imported.count) imported, \(outcome.skippedCount) skipped from \(outcome.sourceURL.absoluteString)."
                                if outcome.imported.count > 0 {
                                    showSubscriptionSheet = false
                                }
                            }
                        }
                    }
                    .disabled(
                        isImportingSubscription
                        || subscriptionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
    }
}

#Preview {
    ProfilesView().environmentObject(AppState())
}
