import Foundation
import os.log

/// Append-only sanitized log file in the App Group shared container,
/// used by the `PacketTunnelProvider` extension to surface its
/// `os_log` output into the host app's Logs tab end-to-end.
///
/// **Why a file and not XPC.** App-extension <-> host-app IPC is
/// awkward on iOS: `NETunnelProviderSession.sendProviderMessage` only
/// works when the host app is in the foreground AND the tunnel
/// session is active, neither of which the extension can rely on.
/// A file in the App Group container is reachable from both sides
/// at any time the entitlement is granted; the cost is no
/// notification on append (the host app polls on Logs-tab refresh,
/// not in realtime).
///
/// **Sanitization is the writer's job.** This store does NOT call
/// `LogSanitizer` on its inputs — every line going in must already
/// be sanitized by the caller (ADR-0010). The extension's
/// `logSanitized` helper does this before invoking `append(_:)`.
/// The store treats inputs as opaque text and only enforces the
/// byte-cap.
///
/// **Unsigned-safe degradation.** Without code signing,
/// `AppGroup.containerURL()` returns `nil`. Every operation here
/// detects that, logs once via `os_log`, and no-ops. Reading
/// returns an empty array; writing silently drops the line. This
/// matches the unsigned CI path where the extension is never
/// actually invoked anyway.
///
/// **Size cap.** The file is bounded at `byteCap` bytes (default
/// 64 KiB) to keep the App Group container small and the
/// LogsView responsive. When an append would push the file over
/// `byteCap`, the store rewrites the file with only the most
/// recent `byteCap / 2` bytes (truncating from the head at the
/// nearest newline). This bounds steady-state disk to `byteCap`
/// and amortizes the rewrite cost.
public struct SharedLogStore {
    private static let fileName = "extension.log"
    public static let defaultByteCap = 64 * 1024

    private static let log = OSLog(
        subsystem: "org.openlibrecommunity.olcrtc.client.shared",
        category: "log-mirror"
    )

    private let byteCap: Int
    private let resolveFileURL: () -> URL?

    /// Production initializer. Reads/writes
    /// `<AppGroup container>/extension.log`. Degrades to no-op
    /// behavior when the container is unavailable.
    public init(byteCap: Int = SharedLogStore.defaultByteCap) {
        self.byteCap = byteCap
        self.resolveFileURL = {
            AppGroup.containerURL()?
                .appendingPathComponent(SharedLogStore.fileName, isDirectory: false)
        }
    }

    /// Direct-URL initializer for tests and for callers that want to
    /// pin a specific file path. Bypasses `AppGroup.containerURL()`
    /// entirely; the caller owns the URL and must guarantee its
    /// parent directory is writable.
    public init(
        fileURL: URL,
        byteCap: Int = SharedLogStore.defaultByteCap
    ) {
        self.byteCap = byteCap
        self.resolveFileURL = { fileURL }
    }

    /// Append a single sanitized line. Adds a trailing newline if
    /// the input does not have one. Silently drops the line if the
    /// shared container is unavailable.
    public func append(_ sanitizedLine: String) {
        guard let url = resolveFileURL() else {
            AppGroup.warnContainerUnavailableOnce()
            return
        }
        var line = sanitizedLine
        if !line.hasSuffix("\n") { line.append("\n") }
        guard let data = line.data(using: .utf8) else { return }

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forUpdating: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url, options: [.atomic])
            }
        } catch {
            os_log("SharedLogStore.append: write failed: %{public}@",
                   log: Self.log, type: .error, String(describing: error))
            return
        }
        truncateIfNeeded(url: url)
    }

    /// Read the whole log file as line-separated strings, oldest
    /// first. Returns `[]` if the container is unavailable or the
    /// file does not exist yet.
    public func readAll() -> [String] {
        guard let url = resolveFileURL() else {
            AppGroup.warnContainerUnavailableOnce()
            return []
        }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    /// Remove the log file entirely. No-op if absent or container
    /// unavailable.
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
            os_log("SharedLogStore.clear: remove failed: %{public}@",
                   log: Self.log, type: .error, String(describing: error))
            return false
        }
    }

    // MARK: - Internal

    private func truncateIfNeeded(url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int,
              size > byteCap else {
            return
        }
        guard let full = try? Data(contentsOf: url) else { return }
        let keep = byteCap / 2
        let start = full.count - keep
        var slice = full.subdata(in: start..<full.count)
        // Align to the next newline so we never start mid-line.
        if let nl = slice.firstIndex(of: 0x0A) {
            slice = slice.subdata(in: (nl + 1)..<slice.count)
        }
        try? slice.write(to: url, options: [.atomic])
    }
}
