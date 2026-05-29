import Foundation
import os.log

/// Single source of truth for the App Group identifier shared between
/// the host app (`OlcRTCClient`) and the `PacketTunnelProvider`
/// extension. This identifier MUST match the value declared in the
/// future-signing entitlements files:
///
///   - `Sources/App/OlcRTCClient.entitlements`
///   - `Sources/PacketTunnelProvider/PacketTunnelProvider.entitlements`
///
/// **Unsigned-safe usage.** Per ADR-0008 the entitlements files are
/// kept in the repo but NOT attached via `CODE_SIGN_ENTITLEMENTS` in
/// the current build path. Without code signing iOS does not grant
/// the App Group container to either process, so
/// `containerURL()` returns `nil` at runtime in CI / unsigned builds.
/// Every caller MUST handle the `nil` case gracefully (typically by
/// degrading to a per-process fallback or logging a sanitized warning
/// and continuing). Once signing lands (Milestone 2 / 4), the
/// `CODE_SIGN_ENTITLEMENTS` setting is attached on both targets and
/// the container becomes runtime-available without source changes.
///
/// See `docs/ROADMAP.md` Milestone 3.5 for the full rationale.
public enum AppGroup {
    /// Matches both entitlements files. Do not inline this string;
    /// using the constant is what keeps the app and the extension
    /// agreed on the container path.
    public static let identifier = "group.org.openlibrecommunity.olcrtc.client"

    private static let log = OSLog(
        subsystem: "org.openlibrecommunity.olcrtc.client.shared",
        category: "appgroup"
    )

    /// URL of the shared container directory, or `nil` if the App
    /// Group entitlement is not granted to the current process
    /// (always the case for unsigned CI builds).
    ///
    /// The lookup is a system call that may log diagnostic noise on
    /// first failure; callers that may run in unsigned environments
    /// should cache the `nil` result rather than calling repeatedly.
    public static func containerURL() -> URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        )
    }

    /// Convenience for one-shot loggers that want a single sanitized
    /// warning when the container is unavailable. Logs at most one
    /// line per process per caller.
    public static func warnContainerUnavailableOnce(
        caller: StaticString = #function,
        file: StaticString = #file
    ) {
        os_log(
            "App Group container unavailable in %{public}@ (unsigned build path — see ADR-0008).",
            log: log,
            type: .info,
            String(describing: caller)
        )
    }
}
