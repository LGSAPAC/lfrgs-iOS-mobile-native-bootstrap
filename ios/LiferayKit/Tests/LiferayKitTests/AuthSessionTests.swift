import Foundation
import Testing
@testable import LiferayKit

@Suite("AuthSession")
struct AuthSessionTests {
    let refreshed = #"{"access_token":"fresh","token_type":"Bearer","expires_in":600}"#

    func makeSession(tokens: OAuthTokens?, replies: [MockTransport.Reply], clock: TestClock = TestClock())
        -> (AuthSession, MockTransport, InMemoryTokenStore) {
        let transport = MockTransport(replies)
        let store = InMemoryTokenStore(tokens)
        let oauth = OAuthClient(configuration: testConfiguration, transport: transport, now: { clock.now })
        return (AuthSession(oauth: oauth, store: store, now: { clock.now }), transport, store)
    }

    @Test("A valid token is used as is, without calling Liferay")
    func validTokenNoRefresh() async throws {
        let clock = TestClock()
        let tokens = OAuthTokens(accessToken: "a", refreshToken: "r", expiresAt: clock.now + 300, scope: nil)
        let (session, transport, _) = makeSession(tokens: tokens, replies: [], clock: clock)

        #expect(try await session.validAccessToken() == "a")
        #expect(transport.sentRequests.isEmpty)
    }

    @Test("Ten concurrent calls with an expired token cause exactly one refresh")
    func singleRefresh() async throws {
        let clock = TestClock()
        let expired = OAuthTokens(accessToken: "old", refreshToken: "r", expiresAt: clock.now - 1, scope: nil)
        let (session, transport, store) = makeSession(
            tokens: expired,
            replies: [.init(status: 200, body: Data(refreshed.utf8), delay: .milliseconds(100))],
            clock: clock
        )

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<10 { group.addTask { try await session.validAccessToken() } }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(tokens == Array(repeating: "fresh", count: 10))
        #expect(transport.sentRequests.count == 1)
        #expect(try store.load()?.accessToken == "fresh", "The refreshed tokens are persisted")
        #expect(try store.load()?.refreshToken == "r")
    }

    @Test("A rejected refresh token signs the user out")
    func expiredSession() async throws {
        let clock = TestClock()
        let expired = OAuthTokens(accessToken: "old", refreshToken: "r", expiresAt: clock.now - 1, scope: nil)
        let (session, _, store) = makeSession(tokens: expired, replies: [try .json(400, fixture: "oauth-token-error-invalid-refresh_token")], clock: clock)

        await #expect(throws: AuthSession.SessionError.expired) { try await session.validAccessToken() }
        #expect(await session.isSignedIn == false)
        #expect(try store.load() == nil)
    }

    @Test("Signing out forgets the tokens")
    func signOut() async throws {
        let tokens = OAuthTokens(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture, scope: nil)
        let (session, _, store) = makeSession(tokens: tokens, replies: [])

        #expect(await session.isSignedIn)
        await session.signOut()
        #expect(await session.isSignedIn == false)
        #expect(try store.load() == nil)
        await #expect(throws: AuthSession.SessionError.signedOut) { try await session.validAccessToken() }
    }
}
