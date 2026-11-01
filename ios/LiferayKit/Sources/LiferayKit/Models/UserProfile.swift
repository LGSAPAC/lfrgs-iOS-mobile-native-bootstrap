import Foundation

/// The profile fields a self-service user may change about themselves.
public struct UserProfileDraft: Encodable, Sendable, Equatable {
    public var givenName: String
    public var familyName: String
    public var jobTitle: String

    public init(givenName: String = "", familyName: String = "", jobTitle: String = "") {
        self.givenName = givenName
        self.familyName = familyName
        self.jobTitle = jobTitle
    }

    public init(_ user: UserAccount) {
        self.init(givenName: user.givenName ?? "", familyName: user.familyName ?? "", jobTitle: user.jobTitle ?? "")
    }

    public var validationErrors: [String] {
        var errors: [String] = []
        if givenName.trimmed.isEmpty { errors.append("Enter a first name.") }
        if familyName.trimmed.isEmpty { errors.append("Enter a last name.") }
        return errors
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(givenName.trimmed, forKey: .givenName)
        try container.encode(familyName.trimmed, forKey: .familyName)
        try container.encode(jobTitle.trimmed, forKey: .jobTitle)
    }

    enum CodingKeys: String, CodingKey { case givenName, familyName, jobTitle }
}

extension UserAccount {
    /// Updates only the fields in `draft`. PATCH keeps everything else (roles, addresses…) as is.
    public static func updateProfile(of id: Int, with draft: UserProfileDraft) throws -> Endpoint<UserAccount> {
        try Endpoint(.patch, "/o/headless-admin-user/v1.0/user-accounts/\(id)", json: draft)
    }

    /// Replaces the user's **complete** address list. Liferay 2026.Q1 has no POST for a user's
    /// addresses, so adding one means sending all existing addresses plus the new one; any address
    /// left out is deleted.
    public static func replaceAddresses(of id: Int, with addresses: [PostalAddress]) throws -> Endpoint<UserAccount> {
        struct Body: Encodable { let userAccountContactInformation: Contact }
        struct Contact: Encodable { let postalAddresses: [PostalAddress] }
        return try Endpoint(.patch, "/o/headless-admin-user/v1.0/user-accounts/\(id)",
                            json: Body(userAccountContactInformation: Contact(postalAddresses: addresses)))
    }
}
