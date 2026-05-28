import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            ConnectView()
                .tabItem { Label("Connect", systemImage: "power.circle") }

            ProfilesView()
                .tabItem { Label("Profiles", systemImage: "person.crop.rectangle.stack") }

            LogsView()
                .tabItem { Label("Logs", systemImage: "doc.text") }

            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppState())
}
