import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum OAuthError: Error, Sendable, Equatable {
    /// The `state` in the callback doesn't match the one we sent: possible CSRF, so stop.
    case stateMismatch
    /// The callback URL has neither a `code` nor an `error`.
    case missingAuthorizationCode
    /// The user cancelled or Liferay refused, for example `access_denied`.
    case authorizationFailed(String)
    /// The code or refresh token is invalid or expired (`invalid_grant`): sign in again.
    case invalidGrant
    /// Any other error from the token endpoint.
    case tokenEndpoint(status: Int, error: String?)
}

/// One sign-in attempt: open `url` in a browser session, then check the callback against `state`
/// and redeem the code with `pkce`.
public struct AuthorizationRequest: Sendable, Equatable {
    public let url: URL
    public let pkce: PKCE
    public let state: String
}

/// Talks to Liferay's OAuth 2 endpoints: `/o/oauth2/authorize` and `/o/oauth2/token`.
///
/// Liferay 2026.Q1 has no token revocation endpoint, so there is no `revoke` method: signing out
/// means deleting the tokens on the device (see ``AuthSession/signOut()``).
public struct OAuthClient: Sendable {
    public let configuration: LiferayConfiguration
    let transport: HTTPTransport
    let now: @Sendable () -> Date

    public init(configuration: LiferayConfiguration, transport: HTTPTransport = URLSession.shared, now: @escaping @Sendable () -> Date = { Date() }) {
        self.configuration = configuration
        self.transport = transport
        self.now = now
    }

    /// Builds the authorize URL with a fresh PKCE verifier and `state`.
    public func makeAuthorizationRequest() -> AuthorizationRequest {
        let pkce = PKCE.generate()
        let state = Data.random(count: 16).base64URLEncodedString()
        var components = URLComponents(url: endpoint("/o/oauth2/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: PKCE.method),
            URLQueryItem(name: "state", value: state),
        ]
        return AuthorizationRequest(url: components.url!, pkce: pkce, state: state)
    }

    /// Extracts the authorization code from the callback URL, after checking `state`.
    public func authorizationCode(from callbackURL: URL, for request: AuthorizationRequest) throws -> String {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func item(_ name: String) -> String? { items.first { $0.name == name }?.value }

        guard item("state") == request.state else { throw OAuthError.stateMismatch }
        if let error = item("error") { throw OAuthError.authorizationFailed(error) }
        guard let code = item("code"), !code.isEmpty else { throw OAuthError.missingAuthorizationCode }
        return code
    }

    /// Exchanges the authorization code (plus the PKCE verifier) for tokens.
    public func exchange(code: String, for request: AuthorizationRequest) async throws -> OAuthTokens {
        try await requestTokens([
            "grant_type": "authorization_code",
            "client_id": configuration.clientID,
            "code": code,
            "redirect_uri": configuration.redirectURI.absoluteString,
            "code_verifier": request.pkce.verifier,
        ], previousRefreshToken: nil)
    }

    /// Gets a new access token with the refresh token.
    public func refresh(_ tokens: OAuthTokens) async throws -> OAuthTokens {
        guard let refreshToken = tokens.refreshToken else { throw OAuthError.invalidGrant }
        return try await requestTokens([
            "grant_type": "refresh_token",
            "client_id": configuration.clientID,
            "refresh_token": refreshToken,
        ], previousRefreshToken: refreshToken)
    }

    private func requestTokens(_ form: [String: String], previousRefreshToken: String?) async throws -> OAuthTokens {
        var request = URLRequest(url: endpoint("/o/oauth2/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(Self.formEncode(form).utf8)

        let issuedAt = now()
        let (data, response) = try await transport.send(request)

        guard (200..<300).contains(response.statusCode) else {
            let error = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data)
            if error?.error == "invalid_grant" { throw OAuthError.invalidGrant }
            throw OAuthError.tokenEndpoint(status: response.statusCode, error: error?.error)
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
                .tokens(issuedAt: issuedAt, previousRefreshToken: previousRefreshToken)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    private func endpoint(_ path: String) -> URL {
        configuration.baseURL.appendingPathComponent(String(path.dropFirst()))
    }

    /// `application/x-www-form-urlencoded`, encoding everything except unreserved characters
    /// (`URLComponents` would leave `+` alone, which a server reads as a space).
    static func formEncode(_ form: [String: String]) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func encode(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s }
        return form.sorted { $0.key < $1.key }.map { "\(encode($0.key))=\(encode($0.value))" }.joined(separator: "&")
    }
}
