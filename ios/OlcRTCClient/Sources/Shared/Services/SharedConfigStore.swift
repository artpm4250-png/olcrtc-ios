import Foundation
import os.log

/// Reads and writes the active `PacketTunnelConfig` through the App
/// Group shared container so the host app and the
/// `PacketTunnelProvider` extension agree on what to tunnel.
///
/// **Primary use site (host app).** When the user picks a profile and
/// hits Start in VPN Mode, the host app calls `save(_:)` to put the
/// resolved `PacketTunnelConfig` into the shared container. The
/// canonical path through `NETunnelProviderManager.saveToPreferences`
/// (which stamps the config into
/// `NETunnelProviderProtocol.providerConfiguration`) still happens —
/// the shared container is the fallback / out-of-band channel for
/// future flows (re-launch, config sync, debugging).
///
/// **Primary use site (extension).** `PacketTunnelProvider.startTunnel`
/// reads from `providerConfiguration` first; if that surface is empty
/// (e.g. the host app saved to the shared container but never opened
/// a tunnel session, or the extension is invoked by an on-demand
/// rule we haven't wired yet), it falls back to `load()` here.
///
/// **Unsigned-safe degradation.** Without code signing (today's CI
/// path per ADR-0008) the App Group container is not granted to
/// either process, so `AppGroup.containerURL()` returns `nil`. The
/// store handles this by:
///   - `save(_:)` throws `Error.containerUnavailable` and logs a
///     sanitized warning. The host app surfaces the throw as a
///     non-fatal log line; it does not block the user.
///   - `load()` returns `nil` and logs the same warning at most once
///     per process per call site.
/// Both behaviors are correct for unsigned CI (where the extension
/// is never invoked anyway) and become correct for the signed path
/// without source changes.
///
/// Storage format: a single JSON file at
/// `<container>/packet-tunnel-config.json`. Writes are atomic via
/// `Data.write(to:options:.atomic)`; reads are best-effort. The
/// schema is `PacketTunnelConfig` directly — no envelope, no
/// versioning yet. When a v2 schema is needed, add a `version` field
/// to the struct itself rather than wrapping here.
public struct SharedConfigStore {
    public enum Error: Swift.Error, LocalizedError {
        case containerUnavailable
        case encodeFailed(Swift.Error)
        case writeFailed(Swift.Error)

        public var errorDescription: String? {
            switch self {
            case .containerUnavailable:
                return "App Group container unavailable. The build is not signed with the matching entitlement (see ADR-0008)."
            case .encodeFailed(let err):
                return "Failed to encode PacketTunnelConfig: \(err.localizedDescription)"
            case .writeFailed(let err):
                return "Failed to write PacketTunnelConfig to shared container: \(err.localizedDescription)"
            }
        }
    }

    private static let fileName = "packet-tunnel-config.json"

    private static let log = OSLog(
        subsystem: "org.openlibrecommunity.olcrtc.client.shared",
        category: "config"
    )

    /// Resolves to the JSON file URL inside the App Group container,
    /// or `nil` when the container is unavailable (unsigned CI path).
    /// Stored as a closure so the test-friendly init can pin a fixed
    /// URL without changing the read paths.
    private let resolveFileURL: () -> URL?

    /// Production initializer. Reads/writes
    /// `<AppGroup container>/packet-tunnel-config.json`. Degrades to
    /// no-op behavior when the container is unavailable.
    public init() {
        self.resolveFileURL = {
            AppGroup.containerURL()?
                .appendingPathComponent(SharedConfigStore.fileName, isDirectory: false)
        }
    }

    /// Direct-URL initializer for tests and for callers that want to
    /// pin a specific file path (e.g. a debug snapshot). Bypasses
    /// `AppGroup.containerURL()` entirely; the caller owns the URL
    /// and must guarantee its parent directory is writable.
    public init(fileURL: URL) {
        self.resolveFileURL = { fileURL }
    }

    /// Encode the config to JSON and write it atomically into the
    /// shared container. Throws `Error.containerUnavailable` in the
    /// unsigned-CI path; callers should treat that as a non-fatal
    /// log-and-continue.
    public func save(_ config: PacketTunnelConfig) throws {
        guard let url = resolveFileURL() else {
            AppGroup.warnContainerUnavailableOnce()
            throw Error.containerUnavailable
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys] // deterministic diffs for debugging
        let data: Data
        do {
            data = try encoder.encode(config)
        } catch {
            throw Error.encodeFailed(error)
        }
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw Error.writeFailed(error)
        }
    }

    /// Read and decode the config from the shared container, or `nil`
    /// if the container is unavailable, the file is missing, or the
    /// JSON cannot be decoded. Never throws; callers that need to
    /// distinguish "no config" from "decode failure" can read
    /// the `os_log` output (sanitized — no `keyHex` ever printed).
    public func load() -> PacketTunnelConfig? {
        guard let url = resolveFileURL() else {
            AppGroup.warnContainerUnavailableOnce()
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // File-not-found is the dominant case before the host app
            // has ever saved; log at .info, not .error.
            os_log("SharedConfigStore.load: no file yet at shared container (%{public}@)",
                   log: Self.log, type: .info, url.lastPathComponent)
            return nil
        }
        do {
            return try JSONDecoder().decode(PacketTunnelConfig.self, from: data)
        } catch {
            os_log("SharedConfigStore.load: decode failed: %{public}@",
                   log: Self.log, type: .error, String(describing: error))
            return nil
        }
    }

    /// Remove the stored config. Safe to call when nothing is stored.
    /// No-ops (returns `false`) in the unsigned path where the
    /// container is unavailable.
    @discardableResult
    public func clear() -> Bool {
        guard let url = resolveFileURL() else {
            AppGroup.warnContainerUnavailableOnce()
            return false
        }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch CocoaError.fileNoSuchFile {
            return false
        } catch {
            os_log("SharedConfigStore.clear: remove failed: %{public}@",
                   log: Self.log, type: .error, String(describing: error))
            return false
        }
    }
}
