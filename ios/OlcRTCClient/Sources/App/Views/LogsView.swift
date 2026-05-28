import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(state.logLines.enumerated()), id: \.offset) { item in
                            Text(item.element)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(item.offset)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: state.logLines.count) { newValue in
                    if newValue > 0 {
                        proxy.scrollTo(newValue - 1, anchor: .bottom)
                    }
                }
            }
            .navigationTitle("Logs")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button("Copy") {
                        UIPasteboard.general.string = state.logLines.joined(separator: "\n")
                    }
                    Button("Clear", role: .destructive) {
                        state.clearLogs()
                    }
                }
            }
        }
    }

    static func placeholderLogs() -> [String] {
        [
            "[boot] olcRTC iOS client scaffold loaded",
            "[boot] log sanitization is active: keyHex=<masked> by LogSanitizer",
            "[boot] gomobile bridge is not linked yet — service calls are stubs",
        ]
    }
}

#Preview {
    LogsView().environmentObject(AppState())
}
