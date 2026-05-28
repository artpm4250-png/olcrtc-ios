import Foundation

/// Loads / saves the profile list.
///
/// Today this is a JSON file in the **app sandbox**
/// `Application Support` directory. Once the App Group entitlement is
/// active (see ADR-0008), this will move to the shared container so
/// the `PacketTunnelProvider` extension can read the same data. Until
/// then, the extension cannot reach this store, which is fine — the
/// extension is a compile-time stub at this stage.
///
/// At-rest format for secrets has **not** been decided yet; a follow-up
/// ADR will cover whether `keyHex` lives in the JSON file or moves to
/// the Keychain.
public final class ProfileStore {
    public static let shared = ProfileStore()

    private let queue = DispatchQueue(label: "org.openlibrecommunity.olcrtc.profileStore")
    private let fileName = "profiles.json"

    private init() {}

    public func load() -> [OlcRTCProfile] {
        queue.sync {
            guard let url = storageURL() else { return [] }
            guard let data = try? Data(contentsOf: url) else { return [] }
            return (try? JSONDecoder().decode([OlcRTCProfile].self, from: data)) ?? []
        }
    }

    public func save(_ profiles: [OlcRTCProfile]) throws {
        try queue.sync {
            guard let url = storageURL() else {
                throw NSError(
                    domain: "ProfileStore",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Application Support directory unavailable"]
                )
            }
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: url, options: .atomic)
        }
    }

    /// Treat two profiles as "the same connection" when the tuple of
    /// (provider, transport, roomID, keyHex, clientID) matches. Used by
    /// import flows to avoid stacking duplicates when the user imports
    /// the same `olcrtc://` URI or subscription twice. We deliberately
    /// do NOT match on `name`, `socksPort`, `dnsServer`, etc. — those
    /// are local-display / local-runtime knobs the user is allowed to
    /// customize.
    public static func isDuplicate(_ a: OlcRTCProfile, _ b: OlcRTCProfile) -> Bool {
        a.provider == b.provider
            && a.transport == b.transport
            && a.roomID == b.roomID
            && a.keyHex == b.keyHex
            && a.clientID == b.clientID
    }

    /// Returns a list with `candidates` appended, skipping any candidate
    /// that is already present per `isDuplicate`. Order preserved.
    public static func mergingWithoutDuplicates(
        existing: [OlcRTCProfile],
        adding candidates: [OlcRTCProfile]
    ) -> (merged: [OlcRTCProfile], addedCount: Int, duplicateCount: Int) {
        var merged = existing
        var added = 0
        var dup = 0
        for candidate in candidates {
            if merged.contains(where: { isDuplicate($0, candidate) }) {
                dup += 1
            } else {
                merged.append(candidate)
                added += 1
            }
        }
        return (merged, added, dup)
    }

    private func storageURL() -> URL? {
        let fm = FileManager.default
        guard let dir = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return dir.appendingPathComponent(fileName, isDirectory: false)
    }
}
