import Foundation

/// The parts of Liferay's `UserAccount` the app uses (headless-admin-user v1.0).
///
/// Optional fields really are optional: for example `lastLoginDate` is missing until the user has
/// signed in through the browser at least once.
public struct UserAccount: Decodable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String
    public var givenName: String?
    public var familyName: String?
    public var alternateName: String?
    public var emailAddress: String
    public var jobTitle: String?
    public var languageId: String?
    public var dateCreated: Date?
    public var lastLoginDate: Date?
}

extension UserAccount {
    /// `GET /o/headless-admin-user/v1.0/my-user-account`: the signed-in user.
    public static var me: Endpoint<UserAccount> {
        Endpoint(.get, "/o/headless-admin-user/v1.0/my-user-account")
    }
}
