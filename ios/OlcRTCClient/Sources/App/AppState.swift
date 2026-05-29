import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var mode: ConnectionMode = .localProxy
    @Published var status: TunnelStatus = .disconnected

    @Published var provider: OlcRTCProvider = .jitsi
    @Published var transport: OlcRTCTransport = .datachannel
    @Published var roomID: String = ""
    @Published var clientID: String = ""
    @Published var keyHex: String = ""

    @Published var socksHost: String = "127.0.0.1"
    @Published var socksPort: String = "8808"
    @Published var dnsServer: String = "8.8.8.8:53"
    @Published var debug: Bool = false

    @Published var profiles: [OlcRTCProfile] = []
    @Published var logLines: [String] = LogsView.placeholderLogs()
    @Published var lastError: String?

    // Most recently selected profile id (for UI selection state).
    @Published var selectedProfileID: UUID?

    // Live validation issues for the Connect form. Recomputed every time
    // a relevant field changes via `refreshValidation()`. Views read
    // this directly to render inline errors and disable the Start
    // button.
    @Published private(set) var validationIssues: [ProfileValidator.Issue] = []

    private let store = ProfileStore.shared
    private let sanitizer = LogSanitizer()
    private let validator = ProfileValidator()
    private let subscriptionImporter = SubscriptionImporter()
    private let sharedLogStore = SharedLogStore()
    /// Content-keyed set of extension log lines already mirrored into
    /// `logLines`. Cleared alongside `logLines` in `clearLogs()` so
    /// "Clear" actually re-pulls extension history on the next mirror.
    private var mirroredExtensionLines: Set<String> = []

    #if !canImport(OlcRTCMobile)
    private let mock = MockOlcRTCService()
    #endif

    private(set) lazy var vpnManager = VPNManager()
    #if canImport(OlcRTCMobile)
    private(set) lazy var localProxy = LocalProxyManager(logSink: { [weak self] line in
        self?.appendLog(line)
    })
    #else
    private(set) lazy var localProxy = LocalProxyManager(service: mock)
    #endif

    init() {
        profiles = store.load()
        refreshValidation()
    }

    func currentProfile() -> OlcRTCProfile {
        OlcRTCProfile(
            name: "ad-hoc",
            provider: provider,
            transport: transport,
            roomID: roomID.trimmingCharacters(in: .whitespacesAndNewlines),
            clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
            keyHex: keyHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            socksHost: socksHost.trimmingCharacters(in: .whitespacesAndNewlines),
            socksPort: Int(socksPort.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 8808,
            dnsServer: dnsServer,
            debug: debug
        )
    }

    /// Re-run profile validation against the current form fields and
    /// publish the result. Cheap (~O(field count)); fine to call on
    /// every change.
    func refreshValidation() {
        validationIssues = validator.validate(
            provider: provider.rawValue,
            transport: transport.rawValue,
            roomID: roomID,
            clientID: clientID,
            keyHex: keyHex,
            socksHost: socksHost,
            socksPortString: socksPort,
            dnsServer: dnsServer
        )
    }

    /// True when the form is in a state where `Start` should be enabled.
    /// We only require validation to be green; `status.isActive` is
    /// handled separately at the call site.
    var canStart: Bool { validationIssues.isEmpty }

    /// Convenience: the first validation message for a given field, or
    /// nil if that field is currently valid. Used to render inline
    /// errors next to each Form row.
    func validationMessage(for field: ProfileValidator.Field) -> String? {
        validationIssues.first { $0.field == field }?.message
    }

    func start() async {
        lastError = nil
        refreshValidation()
        guard canStart else {
            let first = validationIssues.first?.message ?? "Profile is invalid."
            status = .failed(reason: first)
            lastError = first
            appendLog("Start refused: \(first)")
            return
        }
        status = .starting
        appendLog("Starting in \(mode.displayName)…")
        do {
            switch mode {
            case .vpn:
                try await vpnManager.start(profile: currentProfile())
                status = .running(endpoint: nil)
                appendLog("VPN Mode requested. Note: real device runtime requires signing + provisioning + NetworkExtension entitlement.")
            case .localProxy:
                let endpoint = try await localProxy.start(profile: currentProfile())
                status = .running(endpoint: endpoint)
                appendLog("Local Proxy started at \(endpoint). Foreground only; iOS may suspend in background.")
            }
        } catch VPNManager.VPNManagerError.notWiredYet {
            // Expected gated state under the unsigned CI / pre-Milestone-4
            // build path. VPNManager.start has already persisted the
            // selected profile into the App Group SharedConfigStore;
            // the only thing missing is the signed extension that would
            // bring the tunnel up. Surface this calmly rather than as a
            // red `.failed` error — that surface is for actionable
            // failures (invalid profile, network refusal, etc.).
            status = .disconnected
            appendLog("VPN Mode is gated on Apple signing + NetworkExtension entitlement. Selected profile saved to the shared container; the tunnel comes online once signing lands. See About → VPN Mode.")
        } catch {
            status = .failed(reason: error.localizedDescription)
            lastError = error.localizedDescription
            appendLog("Start failed: \(error.localizedDescription)")
        }
    }

    func stop() async {
        status = .stopping
        appendLog("Stopping…")
        switch mode {
        case .vpn:
            await vpnManager.stop()
        case .localProxy:
            await localProxy.stop()
        }
        status = .disconnected
        appendLog("Stopped.")
    }

    func check() {
        refreshValidation()
        if let first = validationIssues.first {
            lastError = first.message
            appendLog("Check failed: \(first)")
        } else {
            lastError = nil
            appendLog("Check OK — profile fields are well-formed (does not verify reachability).")
        }
    }

    func ping() async {
        #if canImport(OlcRTCMobile)
        // Real Ping is wired in `RealOlcRTCService.ping(...)` via
        // `LocalProxyManager.ping(...)`. The UI does not yet drive that
        // call directly; surface a deliberate stub message instead of a
        // fake mock latency when the real framework is linked.
        appendLog("Ping: real gomobile Ping is wired in RealOlcRTCService; UI hookup is intentionally pending.")
        #else
        appendLog("Ping: not yet wired to gomobile. Stub returns mock latency.")
        let ms = await mock.mockPingMillis()
        appendLog("Ping (mock): \(ms) ms")
        #endif
    }

    // MARK: - Profile management

    /// Save the current Connect-form state as a named profile.
    /// Re-uses an existing entry when the connection key fields match
    /// (provider+transport+roomID+keyHex+clientID), so a user editing a
    /// profile in-place does not produce a stack of near-duplicates.
    @discardableResult
    func saveCurrentProfile(name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastError = "Profile name is required."
            return false
        }
        refreshValidation()
        guard canStart else {
            lastError = validationIssues.first?.message ?? "Profile is invalid."
            return false
        }
        var candidate = currentProfile()
        candidate.name = trimmedName

        if let idx = profiles.firstIndex(where: { ProfileStore.isDuplicate($0, candidate) }) {
            // Preserve the original id so SwiftUI doesn't lose selection.
            candidate.id = profiles[idx].id
            profiles[idx] = candidate
        } else {
            profiles.append(candidate)
        }
        persistProfiles()
        selectedProfileID = candidate.id
        appendLog("Saved profile '\(trimmedName)'.")
        return true
    }

    /// Replace the Connect-form fields with a saved profile.
    func selectProfile(_ profile: OlcRTCProfile) {
        provider = profile.provider
        transport = profile.transport
        roomID = profile.roomID
        clientID = profile.clientID
        keyHex = profile.keyHex
        socksHost = profile.socksHost
        socksPort = String(profile.socksPort)
        dnsServer = profile.dnsServer
        debug = profile.debug
        selectedProfileID = profile.id
        refreshValidation()
        appendLog("Selected profile '\(profile.name)'.")
    }

    func deleteProfile(_ profile: OlcRTCProfile) {
        profiles.removeAll { $0.id == profile.id }
        if selectedProfileID == profile.id { selectedProfileID = nil }
        persistProfiles()
        appendLog("Deleted profile '\(profile.name)'.")
    }

    func deleteProfiles(at offsets: IndexSet) {
        let removed = offsets.compactMap { profiles.indices.contains($0) ? profiles[$0] : nil }
        profiles.remove(atOffsets: offsets)
        for p in removed where selectedProfileID == p.id { selectedProfileID = nil }
        persistProfiles()
        if !removed.isEmpty {
            appendLog("Deleted \(removed.count) profile(s).")
        }
    }

    // MARK: - Import

    /// Handle `olcrtc://` URIs delivered via `onOpenURL`.
    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "olcrtc" else { return }
        let importedCount = importURI(url.absoluteString)
        if importedCount == 0 {
            // Concrete error already logged + surfaced by importURI.
            return
        }
        appendLog("Imported \(importedCount) profile(s) from olcrtc:// URI.")
    }

    /// Import a single `olcrtc://` URI string. Returns the number of
    /// profiles added (0 or 1). Sets `lastError` on failure. Never logs
    /// the raw URI or the key.
    @discardableResult
    func importURI(_ raw: String) -> Int {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "URI is empty."
            return 0
        }
        do {
            let parsed = try OlcRTCURIParser().parse(trimmed)
            let candidate = parsed.toProfile(name: "Imported")
            let (merged, added, dup) = ProfileStore.mergingWithoutDuplicates(
                existing: profiles,
                adding: [candidate]
            )
            profiles = merged
            persistProfiles()
            if added > 0 {
                lastError = nil
                appendLog("URI import: 1 profile added (key masked).")
                return 1
            } else if dup > 0 {
                lastError = "URI already imported."
                appendLog("URI import: 0 added, 1 duplicate.")
                return 0
            }
            return 0
        } catch let parseError as OlcRTCURIParser.ParseError {
            lastError = parseError.description
            appendLog("URI import failed: \(parseError.description)")
            return 0
        } catch {
            lastError = error.localizedDescription
            appendLog("URI import failed: \(error.localizedDescription)")
            return 0
        }
    }

    /// Fetch a subscription URL and merge any well-formed lines as
    /// profiles. Async because the fetch goes over the network.
    @discardableResult
    func importSubscription(urlString: String) async -> SubscriptionImporter.Outcome? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "Subscription URL is empty."
            return nil
        }
        appendLog("Subscription import: fetching \(trimmed)…")
        do {
            let outcome = try await subscriptionImporter.fetch(urlString: trimmed)
            let (merged, added, dup) = ProfileStore.mergingWithoutDuplicates(
                existing: profiles,
                adding: outcome.imported
            )
            profiles = merged
            persistProfiles()
            lastError = nil
            appendLog(
                "Subscription import done: \(added) added, \(dup) duplicate, \(outcome.skippedCount) skipped."
            )
            for reason in outcome.skippedReasons.prefix(10) {
                appendLog("  · \(reason)")
            }
            return outcome
        } catch {
            lastError = error.localizedDescription
            appendLog("Subscription import failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Logs

    func appendLog(_ raw: String) {
        let line = sanitizer.sanitize(raw)
        let ts = ISO8601DateFormatter().string(from: Date())
        logLines.append("[\(ts)] \(line)")
        if logLines.count > 500 { logLines.removeFirst(logLines.count - 500) }
    }

    func clearLogs() {
        logLines.removeAll()
        mirroredExtensionLines.removeAll()
    }

    /// Pulls sanitized log lines emitted by the `PacketTunnelProvider`
    /// extension via the App Group `SharedLogStore` and appends any
    /// previously-unseen lines to `logLines` (each one timestamped by
    /// `appendLog`). Safe to call any number of times; a content-keyed
    /// set dedupes lines already mirrored in this session, so
    /// `LogsView.onAppear` and `.refreshable` can both invoke this
    /// without producing duplicates. Edge case: if the extension
    /// legitimately emits two identical sanitized lines in succession,
    /// only the first survives the merge — acceptable trade-off given
    /// the dominant case is unique lines.
    ///
    /// In the unsigned CI build path `SharedLogStore.readAll()` returns
    /// `[]` because the App Group container is unavailable; this method
    /// becomes a no-op without surfacing user-visible noise.
    func mirrorExtensionLogs() {
        let lines = sharedLogStore.readAll()
        var added = 0
        for line in lines where mirroredExtensionLines.insert(line).inserted {
            appendLog(line)
            added += 1
        }
        if added > 0 {
            appendLog("[mirror] pulled \(added) new extension log line(s) from App Group")
        }
    }

    // MARK: - Helpers

    private func persistProfiles() {
        do {
            try store.save(profiles)
        } catch {
            // Persist failure is not fatal to the UI session — surface
            // it but keep the in-memory copy.
            lastError = "Persist failed: \(error.localizedDescription)"
            appendLog("Persist failed: \(error.localizedDescription)")
        }
    }
}
