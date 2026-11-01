import Foundation
import Testing
@testable import LiferayKit

/// A minimal Service Request, enough to test decoding of Liferay's real list response.
/// (The full model arrives in chapter 08.)
private struct ServiceRequestStub: Decodable, Sendable, Equatable {
    var id: Int
    var title: String
    var requestStatus: PicklistValue
    var dueDate: Date?
    var dateCreated: Date
    var creator: Creator
}

@Suite("APIClient")
struct APIClientTests {
    func makeClient(_ replies: [MockTransport.Reply], accessToken: String = "token-1")
        -> (APIClient, MockTransport, AuthSession) {
        let transport = MockTransport(replies)
        let tokens = OAuthTokens(accessToken: accessToken, refreshToken: "r", expiresAt: .distantFuture, scope: nil)
        let session = AuthSession(oauth: OAuthClient(configuration: testConfiguration, transport: transport),
                                  store: InMemoryTokenStore(tokens))
        let client = APIClient(baseURL: testConfiguration.baseURL, session: session, transport: transport, language: "en-US")
        return (client, transport, session)
    }

    @Test("Sends the Bearer token and headers, and decodes the real my-user-account response")
    func myUserAccount() async throws {
        let (client, transport, _) = makeClient([try .json(200, fixture: "my-user-account")])

        let me = try await client.send(UserAccount.me)

        #expect(me.name == "Jane Doe")
        #expect(me.emailAddress == "jane.doe@example.com")
        #expect(me.jobTitle == "Customer")
        let sent = try #require(transport.sentRequests.first)
        #expect(sent.url?.absoluteString == "http://localhost:8080/o/headless-admin-user/v1.0/my-user-account")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        #expect(sent.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(sent.value(forHTTPHeaderField: "Accept-Language") == "en-US")
    }

    @Test("Decodes a real page of Service Requests, including both date formats")
    func page() async throws {
        let (client, _, _) = makeClient([try .json(200, fixture: "service-requests-page")])

        let page = try await client.send(Endpoint<Page<ServiceRequestStub>>(.get, "/o/c/servicerequests"))

        #expect(page.page == 1)
        #expect(page.totalCount == page.items.count)
        #expect(page.hasNextPage == false)
        let fixtureItem = try #require(page.items.first { $0.title.hasPrefix("Fixture:") })
        #expect(fixtureItem.requestStatus == PicklistValue(key: "inProgress", name: "In Progress"))
        #expect(fixtureItem.creator.name == "Jane Doe")
        // "2026-12-31T00:00:00.000Z" (fractional seconds) and "…T03:40:37Z" (none) both decode.
        #expect(fixtureItem.dueDate == LiferayJSON.parseDate("2026-12-31T00:00:00Z"))
    }

    @Test("Paging, sorting, filtering and searching become query parameters")
    func listQuery() async throws {
        let (client, transport, _) = makeClient([try .json(200, fixture: "service-requests-page-empty")])
        let query = ListQuery(page: 2, pageSize: 10, sort: ["dateCreated:desc"],
                              filter: "requestStatus eq \(ListQuery.quoted("open"))", search: "C++ O'Brien")

        _ = try await client.send(Endpoint<Page<ServiceRequestStub>>(.get, "/o/c/servicerequests", queryItems: query.queryItems))

        let url = try #require(transport.sentRequests.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query2 = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(query2["page"] == "2")
        #expect(query2["pageSize"] == "10")
        #expect(query2["sort"] == "dateCreated:desc")
        #expect(query2["filter"] == "requestStatus eq 'open'")
        #expect(query2["search"] == "C++ O'Brien")
        #expect(url.absoluteString.contains("C%2B%2B"), "'+' must be encoded")
    }

    @Test("A 401 triggers one refresh and a retry with the new token")
    func retryAfterUnauthorized() async throws {
        let (client, transport, _) = makeClient([
            .empty(401),
            .json(200, #"{"access_token":"token-2","token_type":"Bearer","expires_in":600}"#),
            try .json(200, fixture: "my-user-account"),
        ])

        let me = try await client.send(UserAccount.me)

        #expect(me.name == "Jane Doe")
        let authorizations = transport.sentRequests.map { $0.value(forHTTPHeaderField: "Authorization") }
        #expect(authorizations == ["Bearer token-1", nil, "Bearer token-2"])
    }

    @Test("A second 401 signs the user out")
    func unauthorizedTwice() async throws {
        let (client, _, session) = makeClient([
            .empty(401),
            .json(200, #"{"access_token":"token-2","token_type":"Bearer","expires_in":600}"#),
            .empty(401),
        ])

        await #expect(throws: APIError.unauthorized) { try await client.send(UserAccount.me) }
        #expect(await session.isSignedIn == false)
    }

    @Test("Liferay's real error responses map to APIError", arguments: [
        ("error-400-missing-required-field", 400),
        ("error-403-invalid-picklist-key", 403),
        ("error-403-update-other-user", 403),
        ("error-404-other-users-request", 404),
    ])
    func errors(fixtureName: String, status: Int) async throws {
        let (client, _, _) = makeClient([try .json(status, fixture: fixtureName)])

        do {
            _ = try await client.send(UserAccount.me)
            Issue.record("Expected an error")
        } catch let error as APIError {
            switch (status, error) {
            case (400, .badRequest(let problem)):
                #expect(problem?.title == #"No value was provided for required object field "title""#)
                #expect(error.userMessage == problem?.title)
            case (403, .forbidden(let problem)): #expect(problem?.status == "FORBIDDEN")
            case (404, .notFound(let problem)): #expect(problem?.status == "NOT_FOUND")
            default: Issue.record("Unexpected mapping \(error) for HTTP \(status)")
            }
        }
    }

    @Test("DELETE's empty 204 response decodes as NoContent")
    func noContent() async throws {
        let (client, _, _) = makeClient([.empty(204)])
        #expect(try await client.send(Endpoint<NoContent>(.delete, "/o/c/servicerequests/1")) == NoContent())
    }

    @Test("Picklist values encode as {\"key\": …} only")
    func picklistEncoding() throws {
        let data = try LiferayJSON.encoder.encode(PicklistValue(key: "open", name: "Open"))
        #expect(String(decoding: data, as: UTF8.self) == #"{"key":"open"}"#)
    }
}
