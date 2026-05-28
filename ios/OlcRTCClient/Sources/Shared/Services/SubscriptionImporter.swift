import Foundation

/// Downloads a plain-text subscription file and parses each line as an
/// `olcrtc://` URI. Invalid lines are skipped, not fatal; the caller
/// gets back a `Result` describing what was imported and what was
/// rejected (with sanitized reason strings — never the raw line, never
/// the key).
///
/// Network surface is intentionally minimal: `URLSession.shared` with a
/// fixed timeout, GET only. No redirects beyond the system default, no
/// custom headers. The fetched body is decoded as UTF-8 with a Latin-1
/// fallback so a subscription that came from a non-UTF-8 source still
/// imports as long as the URIs themselves are ASCII (which they are by
/// `docs/uri.md`).
public final class SubscriptionImporter: @unchecked Sendable {
    public struct Outcome: Sendable, Equatable {
        public var imported: [OlcRTCProfile]
        public var skippedCount: Int
        public var skippedReasons: [String]
        public var sourceURL: URL

        public init(
            imported: [OlcRTCProfile],
            skippedCount: Int,
            skippedReasons: [String],
            sourceURL: URL
        ) {
            self.imported = imported
            self.skippedCount = skippedCount
            self.skippedReasons = skippedReasons
            self.sourceURL = sourceURL
        }
    }

    public enum ImportError: Error, LocalizedError {
        case invalidURL
        case unsupportedScheme(String)
        case httpStatus(Int)
        case emptyBody
        case undecodable
        case transport(String)

        public var errorDescription: String? {
            switch self {
            case .invalidURL:                  return "Subscription URL is not a valid URL."
            case .unsupportedScheme(let s):    return "Subscription URL scheme '\(s)' is not supported. Use http or https."
            case .httpStatus(let code):        return "Subscription fetch failed with HTTP \(code)."
            case .emptyBody:                   return "Subscription body is empty."
            case .undecodable:                 return "Subscription body could not be decoded as UTF-8."
            case .transport(let message):      return "Subscription fetch failed: \(message)"
            }
        }
    }

    private let session: URLSession
    private let parser = OlcRTCURIParser()

    /// Default subscription import client: 15 s timeout, no caching,
    /// no cookies — we treat each fetch as a one-shot download.
    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 15
            cfg.timeoutIntervalForResource = 30
            cfg.httpCookieStorage = nil
            cfg.urlCache = nil
            self.session = URLSession(configuration: cfg)
        }
    }

    /// Fetch + parse. Throws on transport/HTTP problems; line-level
    /// parse failures are reported via `Outcome.skipped*`.
    public func fetch(urlString: String) async throws -> Outcome {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            throw ImportError.invalidURL
        }
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw ImportError.unsupportedScheme(url.scheme ?? "<none>")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw ImportError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ImportError.httpStatus(http.statusCode)
        }
        if data.isEmpty {
            throw ImportError.emptyBody
        }

        let body: String
        if let utf8 = String(data: data, encoding: .utf8) {
            body = utf8
        } else if let latin1 = String(data: data, encoding: .isoLatin1) {
            body = latin1
        } else {
            throw ImportError.undecodable
        }

        return parse(body: body, sourceURL: url)
    }

    /// Pure parser entry point; exposed so unit tests don't need a
    /// `URLSession` to exercise line-level behavior.
    public func parse(body: String, sourceURL: URL) -> Outcome {
        var imported: [OlcRTCProfile] = []
        var skippedCount = 0
        var skippedReasons: [String] = []

        for (idx, rawLine) in body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // Allow `# comment` lines so subscription authors can
            // annotate without breaking the file.
            if line.hasPrefix("#") { continue }
            do {
                let parsed = try parser.parse(line)
                let profile = parsed.toProfile(name: "Imported")
                imported.append(profile)
            } catch {
                skippedCount += 1
                // Never include the raw line — it could be a full
                // `olcrtc://` URI with a key. Only the line number and
                // the structured error description are safe.
                if let parseError = error as? OlcRTCURIParser.ParseError {
                    skippedReasons.append("line \(idx + 1): \(parseError.description)")
                } else {
                    skippedReasons.append("line \(idx + 1): \(error.localizedDescription)")
                }
            }
        }

        return Outcome(
            imported: imported,
            skippedCount: skippedCount,
            skippedReasons: skippedReasons,
            sourceURL: sourceURL
        )
    }
}
