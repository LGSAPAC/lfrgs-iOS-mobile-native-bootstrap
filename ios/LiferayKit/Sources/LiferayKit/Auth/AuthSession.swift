import Foundation

/// Owns the signed-in user's tokens and hands out a valid access token.
///
/// It is an `actor` so that when several requests find the access token expired at the same time,
/// only **one** refresh request goes to Liferay and the others wait for its result.
public actor AuthSession {
    public enum SessionError: Error, Sendable, Equatable {
        /// Nobody is signed in.
        case signedOut
        /// The refresh token was rejected; the user has been signed out and must sign in again.
        case expired
    }

    private let oauth: OAuthClient
    private let store: TokenStore
    private let now: @Sendable () -> Date
    private var tokens: OAuthTokens?
    private var refreshTask: Task<OAuthTokens, Error>?

    public init(oauth: OAuthClient, store: TokenStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.oauth = oauth
        self.store = store
        self.now = now
        // Restore the previous session, if any. A corrupt Keychain item just means "signed out".
        self.tokens = try? store.load()
    }

    public var isSignedIn: Bool { tokens != nil }

    /// Stores the tokens from a successful sign-in.
    public func signIn(with tokens: OAuthTokens) throws {
        try store.save(tokens)
        self.tokens = tokens
    }

    /// Forgets the tokens on this device. (Liferay 2026.Q1 has no endpoint to revoke them.)
    public func signOut() {
        refreshTask?.cancel()
        refreshTask = nil
        tokens = nil
        try? store.clear()
    }

    /// A token that is valid now, refreshing first if it has (nearly) expired.
    public func validAccessToken() async throws -> String {
        guard let tokens else { throw SessionError.signedOut }
        if !tokens.isExpired(at: now()) { return tokens.accessToken }
        return try await refresh().accessToken
    }

    /// Call after a request with `rejectedToken` got HTTP 401. Refreshes unless another request
    /// already did, and returns the token to retry with.
    public func accessTokenAfterUnauthorized(_ rejectedToken: String) async throws -> String {
        guard let tokens else { throw SessionError.signedOut }
        if tokens.accessToken != rejectedToken { return tokens.accessToken }
        return try await refresh().accessToken
    }

    private func refresh() async throws -> OAuthTokens {
        // Join a refresh that is already running, or start one.
        let task: Task<OAuthTokens, Error>
        if let refreshTask {
            task = refreshTask
        } else {
            guard let current = tokens else { throw SessionError.signedOut }
            task = Task { [oauth] in try await oauth.refresh(current) }
            refreshTask = task
        }

        do {
            let refreshed = try await task.value
            if refreshTask == task {
                // The first caller to resume stores the result; the others just use it.
                refreshTask = nil
                try store.save(refreshed)
                tokens = refreshed
            }
            return refreshed
        } catch OAuthError.invalidGrant {
            if refreshTask == task { signOut() }
            throw SessionError.expired
        } catch {
            if refreshTask == task { refreshTask = nil }
            throw error
        }
    }
}
