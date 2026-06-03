import Foundation

/// Parses ISO8601 timestamps that Apple's `ISO8601DateFormatter` rejects —
/// notably microsecond precision (`...029958+00:00`) returned by some provider
/// APIs. Falls back to stripping fractional seconds.
public enum ISO8601Tolerant {
    public static func date(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let stripped = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: stripped)
    }
}
