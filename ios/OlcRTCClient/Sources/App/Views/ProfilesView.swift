import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            Group {
                if state.profiles.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(state.profiles) { profile in
                            row(for: profile)
                        }
                    }
                }
            }
            .navigationTitle("Profiles")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No profiles yet")
                .font(.headline)
            Text("Import an olcrtc:// URI or paste a subscription URL to add a profile.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(for profile: OlcRTCProfile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(profile.name)
                .font(.headline)
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
        .padding(.vertical, 2)
    }
}

#Preview {
    ProfilesView().environmentObject(AppState())
}
