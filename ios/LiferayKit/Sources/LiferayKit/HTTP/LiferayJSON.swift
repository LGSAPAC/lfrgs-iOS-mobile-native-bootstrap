import Foundation

/// JSON settings that match Liferay's headless APIs.
public enum LiferayJSON {
    /// Liferay sends dates in two shapes: `2026-11-01T03:40:37Z` for system fields such as
    /// `dateCreated`, and `2026-12-31T00:00:00.000Z` (fractional seconds) for Date fields on objects.
    /// The decoder accepts both, plus a plain `2026-12-31`.
    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = parseDate(string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(string)")
        }
        return decoder
    }

    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func parseDate(_ string: String) -> Date? {
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let withoutFraction = Date.ISO8601FormatStyle()
        let dayOnly = Date.ISO8601FormatStyle().year().month().day()
        for style in [withoutFraction, withFraction, dayOnly] {
            if let date = try? Date(string, strategy: style) { return date }
        }
        return nil
    }
}
