import Foundation

/// Internal helper for parsing ISO8601 timestamps from the Gate/AI server.
///
/// The server sends JavaScript `Date.toISOString()` values (e.g. `2026-09-01T00:00:00.000Z`),
/// so parsing must tolerate fractional seconds as well as plain `Z` timestamps.
enum ISO8601DateParsing {
    /// Parses an ISO8601 timestamp, accepting both fractional-second and whole-second forms.
    ///
    /// - Parameter string: The ISO8601 string to parse.
    /// - Returns: The parsed date, or `nil` if the string is not a valid ISO8601 timestamp.
    static func date(from string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) {
            return date
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
