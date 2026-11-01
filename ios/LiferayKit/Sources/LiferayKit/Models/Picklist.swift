import Foundation

/// A picklist value. Liferay returns `{"key": "open", "name": "Open"}`, with `name` localized to
/// the request's `Accept-Language`, and expects `{"key": "open"}` when you send one.
///
/// Only ever send keys that exist in the picklist: an unknown key makes Liferay answer
/// `403 Forbidden`, not a validation error.
public struct PicklistValue: Codable, Sendable, Hashable {
    public var key: String
    public var name: String?

    public init(key: String, name: String? = nil) {
        self.key = key
        self.name = name
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
    }
}

/// Who created an entry: `{"id": 34267, "name": "Jane Doe", ...}`.
public struct Creator: Decodable, Sendable, Equatable {
    public var id: Int
    public var name: String?
    public var givenName: String?
    public var familyName: String?
}
