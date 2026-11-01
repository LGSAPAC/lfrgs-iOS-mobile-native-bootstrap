import Foundation

/// The tokens the app holds for a signed-in user. Stored in the Keychain, never in `UserDefaults`.
public struct OAuthTokens: Codable, Sendable, Equatable {
    public var accessToken: String
    /// Used to get a new access token without asking the user to sign in again.
    public var refreshToken: String?
    /// When `accessToken` stops working. Liferay's default lifetime is 10 minutes.
    public var expiresAt: Date
    /// Space-separated scopes Liferay actually granted.
    public var scope: String?

    public init(accessToken: String, refreshToken: String?, expiresAt: Date, scope: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
    }

    /// True if the token has expired, or will within `leeway` seconds (so a request in flight
    /// doesn't fail half-way).
    public func isExpired(at now: Date = Date(), leeway: TimeInterval = 30) -> Bool {
        now.addingTimeInterval(leeway) >= expiresAt
    }
}

/// The JSON body of a successful `POST /o/oauth2/token`.
struct TokenResponse: Decodable, Sendable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }

    func tokens(issuedAt now: Date, previousRefreshToken: String? = nil) -> OAuthTokens {
        OAuthTokens(
            accessToken: accessToken,
            // Liferay may or may not issue a new refresh token on refresh; keep the old one if not.
            refreshToken: refreshToken ?? previousRefreshToken,
            expiresAt: now.addingTimeInterval(TimeInterval(expiresIn)),
            scope: scope
        )
    }
}

/// The JSON body of a failed token request, for example `{"error": "invalid_grant"}` (RFC 6749 §5.2).
struct OAuthErrorResponse: Decodable, Sendable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
