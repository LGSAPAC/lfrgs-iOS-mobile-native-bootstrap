import Foundation

/// One of the signed-in user's postal addresses (the **Postal Address** system object).
public struct PostalAddress: Codable, Sendable, Equatable, Identifiable {
    /// `nil` for an address that hasn't been saved yet.
    public var id: Int?
    public var name: String?
    public var streetAddressLine1: String
    public var streetAddressLine2: String?
    public var addressLocality: String
    /// Liferay returns the region's display name, for example `California`. Send its code (`CA`).
    public var addressRegion: String?
    public var postalCode: String
    /// The country's English name, for example `United States` (see ``PostalAddressDraft``).
    public var addressCountry: String?
    /// `personal`, `business` or `other`.
    public var addressType: String?
    public var primary: Bool?

    public init(id: Int? = nil, name: String? = nil, streetAddressLine1: String, streetAddressLine2: String? = nil,
                addressLocality: String, addressRegion: String? = nil, postalCode: String,
                addressCountry: String?, addressType: String? = "personal", primary: Bool? = false) {
        self.id = id
        self.name = name
        self.streetAddressLine1 = streetAddressLine1
        self.streetAddressLine2 = streetAddressLine2
        self.addressLocality = addressLocality
        self.addressRegion = addressRegion
        self.postalCode = postalCode
        self.addressCountry = addressCountry
        self.addressType = addressType
        self.primary = primary
    }

    /// A one-line summary such as `1400 Montefino Ave, Diamond Bar, California 91765`.
    public var singleLine: String {
        [streetAddressLine1, addressLocality, [addressRegion, postalCode].compactMap { $0 }.joined(separator: " ")]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

/// What the address form edits.
///
/// Liferay is picky about how the country is written, and the two address endpoints disagree:
///
/// | `addressCountry`  | PATCH user-account (add)       | PUT postal-addresses/{id} (edit) |
/// |-------------------|--------------------------------|----------------------------------|
/// | `United States`   | ✅                              | ✅                                |
/// | `US`, `united-states` | ✅                          | ❌ 400 "Country not found"         |
/// | `Etats-Unis`      | ⚠️ 200, saved with no country   | ❌ 400                             |
/// | empty             | ⚠️ 200, saved as Afghanistan    | ❌ 400                             |
///
/// So the draft always sends the **English country name**, plus the **region code** (`CA`), which
/// is required whenever the country has regions ("Region not found" otherwise).
public struct PostalAddressDraft: Sendable, Equatable {
    public var name: String = ""
    public var street: String = ""
    public var street2: String = ""
    public var city: String = ""
    public var postalCode: String = ""
    /// The chosen country, from ``Country/all``.
    public var country: Country?
    /// The chosen region's `regionCode`, for example `CA`; empty if the country has no regions.
    public var regionCode: String = ""
    public var primary: Bool = false

    public init() {}

    public init(_ address: PostalAddress, countries: [Country]) {
        name = address.name ?? ""
        street = address.streetAddressLine1
        street2 = address.streetAddressLine2 ?? ""
        city = address.addressLocality
        postalCode = address.postalCode
        primary = address.primary ?? false
        country = countries.first { $0.matches(address.addressCountry) }
        regionCode = country?.regions.first { $0.matches(address.addressRegion) }?.regionCode ?? ""
    }

    public var validationErrors: [String] {
        var errors: [String] = []
        if street.trimmed.isEmpty { errors.append("Enter a street address.") }
        if city.trimmed.isEmpty { errors.append("Enter a city.") }
        if postalCode.trimmed.isEmpty { errors.append("Enter a postal code.") }
        if let country {
            if !country.regions.isEmpty, !country.regions.contains(where: { $0.regionCode == regionCode }) {
                errors.append("Choose a state or region.")
            }
        } else {
            errors.append("Choose a country.")
        }
        return errors
    }

    func postalAddress(id: Int?) -> PostalAddress {
        PostalAddress(id: id, name: name.trimmed.isEmpty ? nil : name.trimmed,
                      streetAddressLine1: street.trimmed, streetAddressLine2: street2.trimmed,
                      addressLocality: city.trimmed, addressRegion: regionCode.isEmpty ? nil : regionCode,
                      postalCode: postalCode.trimmed, addressCountry: country?.englishName,
                      addressType: "personal", primary: primary)
    }
}

/// A country from `headless-admin-address`, with its regions.
public struct Country: Decodable, Sendable, Equatable, Identifiable {
    public var id: Int
    /// A slug such as `united-states`; use ``title(for:)`` for display.
    public var name: String
    public var a2: String
    public var regions: [Region]
    public var titleI18n: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id, name, a2, regions
        case titleI18n = "title_i18n"
    }

    /// The name Liferay's address APIs accept, for example `United States`.
    public var englishName: String { titleI18n?["en_US"] ?? name }

    /// The display name in the user's language, falling back to English.
    public func title(for locale: Locale = .current) -> String {
        let key = locale.identifier.replacingOccurrences(of: "-", with: "_")
        return titleI18n?[key] ?? titleI18n?["en_US"] ?? name
    }

    func matches(_ value: String?) -> Bool {
        guard let value, !value.isEmpty else { return false }
        return [a2, name, titleI18n?["en_US"]].contains { $0?.caseInsensitiveCompare(value) == .orderedSame }
    }
}

public struct Region: Decodable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String
    public var regionCode: String
    public var titleI18n: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id, name, regionCode
        case titleI18n = "title_i18n"
    }

    public func title(for locale: Locale = .current) -> String {
        let key = locale.identifier.replacingOccurrences(of: "-", with: "_")
        return titleI18n?[key] ?? titleI18n?["en_US"] ?? name
    }

    func matches(_ value: String?) -> Bool {
        guard let value, !value.isEmpty else { return false }
        return [regionCode, name, titleI18n?["en_US"]].contains { $0?.caseInsensitiveCompare(value) == .orderedSame }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension PostalAddress {
    public static func list(userAccountID: Int) -> Endpoint<Page<PostalAddress>> {
        Endpoint(.get, "/o/headless-admin-user/v1.0/user-accounts/\(userAccountID)/postal-addresses",
                 queryItems: [URLQueryItem(name: "pageSize", value: "-1")])
    }

    /// PUT (full replace), so that clearing an optional field such as the region really clears it.
    public static func update(_ id: Int, with draft: PostalAddressDraft) throws -> Endpoint<PostalAddress> {
        try Endpoint(.put, "/o/headless-admin-user/v1.0/postal-addresses/\(id)", json: draft.postalAddress(id: nil))
    }

    public static func delete(_ id: Int) -> Endpoint<NoContent> {
        Endpoint(.delete, "/o/headless-admin-user/v1.0/postal-addresses/\(id)")
    }
}

extension Country {
    /// All countries, sorted by name, each with its regions (about 250, in one call).
    public static var all: Endpoint<Page<Country>> {
        Endpoint(.get, "/o/headless-admin-address/v1.0/countries",
                 queryItems: [URLQueryItem(name: "pageSize", value: "-1"), URLQueryItem(name: "sort", value: "name:asc")])
    }
}
