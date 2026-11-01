import Foundation
import Testing
@testable import LiferayKit

@Suite("OAuthClient")
struct OAuthClientTests {
    @Test("The authorize URL carries the client, redirect URI, PKCE challenge and state")
    func authorizeURL() throws {
        let request = OAuthClient(configuration: testConfiguration, transport: MockTransport([])).makeAuthorizationRequest()
        let components = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(components.path == "/o/oauth2/authorize")
        #expect(query["response_type"] == "code")
        #expect(query["client_id"] == "id-test")
        #expect(query["redirect_uri"] == "com.liferay.sample.selfservice://oauth2redirect")
        #expect(query["code_challenge"] == request.pkce.challenge)
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["state"] == request.state)
        #expect(query["code_verifier"] == nil, "The verifier must never be in the authorize URL")
    }

    @Test("The callback's code is accepted only with the matching state")
    func callbackParsing() throws {
        let client = OAuthClient(configuration: testConfiguration, transport: MockTransport([]))
        let request = client.makeAuthorizationRequest()
        let base = "com.liferay.sample.selfservice://oauth2redirect"

        #expect(try client.authorizationCode(from: URL(string: "\(base)?state=\(request.state)&code=abc")!, for: request) == "abc")
        #expect(throws: OAuthError.stateMismatch) {
            try client.authorizationCode(from: URL(string: "\(base)?state=forged&code=abc")!, for: request)
        }
        #expect(throws: OAuthError.authorizationFailed("access_denied")) {
            try client.authorizationCode(from: URL(string: "\(base)?state=\(request.state)&error=access_denied")!, for: request)
        }
        #expect(throws: OAuthError.missingAuthorizationCode) {
            try client.authorizationCode(from: URL(string: "\(base)?state=\(request.state)")!, for: request)
        }
    }

    @Test("Exchanging the code sends the PKCE verifier and decodes Liferay's real token response")
    func exchange() async throws {
        let transport = MockTransport([try .json(200, fixture: "oauth-token-response")])
        let clock = TestClock()
        let client = OAuthClient(configuration: testConfiguration, transport: transport, now: { clock.now })
        let request = client.makeAuthorizationRequest()

        let tokens = try await client.exchange(code: "the-code", for: request)

        let sent = try #require(transport.sentRequests.first)
        #expect(sent.url?.path == "/o/oauth2/token")
        #expect(sent.httpMethod == "POST")
        #expect(sent.formFields == [
            "grant_type": "authorization_code",
            "client_id": "id-test",
            "code": "the-code",
            "redirect_uri": "com.liferay.sample.selfservice://oauth2redirect",
            "code_verifier": request.pkce.verifier,
        ])
        #expect(tokens.accessToken.hasPrefix("REDACTED"))
        #expect(tokens.refreshToken != nil)
        #expect(tokens.expiresAt == clock.now.addingTimeInterval(600), "Liferay's default lifetime is 600 s")
        #expect(tokens.scope?.contains("c_servicerequest.everything") == true)
    }

    @Test("Refresh keeps the old refresh token when Liferay doesn't send a new one")
    func refreshKeepsRefreshToken() async throws {
        let transport = MockTransport([.json(200, #"{"access_token":"new","token_type":"Bearer","expires_in":600}"#)])
        let client = OAuthClient(configuration: testConfiguration, transport: transport)
        let old = OAuthTokens(accessToken: "old", refreshToken: "refresh-1", expiresAt: .distantPast, scope: nil)

        let tokens = try await client.refresh(old)

        #expect(tokens.accessToken == "new")
        #expect(tokens.refreshToken == "refresh-1")
        #expect(transport.sentRequests.first?.formFields["grant_type"] == "refresh_token")
    }

    @Test("Liferay's invalid_grant response becomes OAuthError.invalidGrant")
    func invalidGrant() async throws {
        let transport = MockTransport([try .json(400, fixture: "oauth-token-error-invalid-refresh_token")])
        let client = OAuthClient(configuration: testConfiguration, transport: transport)
        let old = OAuthTokens(accessToken: "old", refreshToken: "bad", expiresAt: .distantPast, scope: nil)

        await #expect(throws: OAuthError.invalidGrant) { try await client.refresh(old) }
    }

    @Test("Form values are fully percent-encoded")
    func formEncoding() {
        #expect(OAuthClient.formEncode(["a": "x+y z/&="]) == "a=x%2By%20z%2F%26%3D")
    }
}
