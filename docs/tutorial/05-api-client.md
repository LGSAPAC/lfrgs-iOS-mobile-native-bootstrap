# 05 — A small, correct API client

> **Unofficial reference.** This tutorial is an unofficial reference, not official Liferay
> documentation, and is not supported by Liferay. See [learn.liferay.com](https://learn.liferay.com)
> for official documentation.

Every screen from chapter 06 on calls Liferay. This chapter builds the one place that does it, and
encodes Liferay's conventions once so the screens don't have to: tokens, refresh, paging, errors,
dates and picklists.

**Time:** about 30 minutes. **Status:** everything in this chapter is unit-tested
(`cd ios/LiferayKit && swift test`) against responses recorded from Liferay DXP 2026.Q1.

## 1. An endpoint knows its response type

[`Endpoint.swift`](../../ios/LiferayKit/Sources/LiferayKit/HTTP/Endpoint.swift):

```swift
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
    public var method: HTTPMethod
    public var path: String
    public var queryItems: [URLQueryItem]
    public var body: Data?
}

extension UserAccount {
    public static var me: Endpoint<UserAccount> {
        Endpoint(.get, "/o/headless-admin-user/v1.0/my-user-account")
    }
}

let me = try await api.send(UserAccount.me)     // me is a UserAccount
```

The compiler checks that each call decodes to the right type. Calls that return no body, such as
`DELETE` (HTTP 204), use `Endpoint<NoContent>`.

## 2. Every request gets a valid token

[`APIClient.send(_:)`](../../ios/LiferayKit/Sources/LiferayKit/HTTP/APIClient.swift):

```swift
let token = try await session.validAccessToken()          // refreshes first if (nearly) expired
var (data, response) = try await transport.send(request(for: endpoint, token: token))

if response.statusCode == 401 {                           // e.g. token revoked, server restarted
    let retryToken = try await session.accessTokenAfterUnauthorized(token)
    (data, response) = try await transport.send(request(for: endpoint, token: retryToken))
    if response.statusCode == 401 {
        await session.signOut()
        throw APIError.unauthorized                        // → back to the sign-in screen
    }
}
```

Each request also sends `Accept: application/json` and **`Accept-Language`** with the device language,
so Liferay localizes picklist names and error messages.

### Only one refresh at a time

When the app comes back from the background, several screens may call Liferay at once, all with the
same expired token. If each refreshed on its own, Liferay would see a burst of refresh requests.
[`AuthSession`](../../ios/LiferayKit/Sources/LiferayKit/Auth/AuthSession.swift) is an `actor` that
keeps the refresh in flight as a `Task`; later callers await the same task:

```swift
let task: Task<OAuthTokens, Error>
if let refreshTask {
    task = refreshTask                                  // join the refresh already running
} else {
    task = Task { [oauth] in try await oauth.refresh(current) }
    refreshTask = task
}
let refreshed = try await task.value
```

`AuthSessionTests` fires ten concurrent requests with an expired token and checks that exactly
**one** refresh reaches the server. If Liferay rejects the refresh token (`invalid_grant`), the
session signs the user out and throws `SessionError.expired`.

By default Liferay returns the **same** refresh token on refresh. `OAuthTokens` keeps whatever the
response contains, falling back to the previous one, so the app also works if rotation is turned on.

## 3. Lists are pages

Every Liferay list response has the same envelope, decoded by
[`Page<Item>`](../../ios/LiferayKit/Sources/LiferayKit/Models/Page.swift):

```json
{ "items": [ … ], "page": 1, "pageSize": 20, "totalCount": 3, "lastPage": 1, "actions": {}, "facets": [] }
```

[`ListQuery`](../../ios/LiferayKit/Sources/LiferayKit/HTTP/Endpoint.swift) builds the parameters that
all list endpoints share:

```swift
let query = ListQuery(
    page: 1, pageSize: 20,
    sort: ["dateCreated:desc"],
    filter: "requestStatus eq \(ListQuery.quoted("open"))",   // OData; quoted() escapes ' as ''
    search: "printer"
)
```

> **Gotcha: `+` in query strings.** `URLComponents` leaves `+` unencoded, and servers read it as a
> space, so a search for `C++` would arrive as `C  `. `APIClient` encodes it as `%2B`.

## 4. Errors become something the UI can act on

[`APIError`](../../ios/LiferayKit/Sources/LiferayKit/HTTP/APIError.swift) maps the status code and
Liferay's error body:

| HTTP | Liferay body (recorded) | `APIError` | Typical UI |
|---|---|---|---|
| 400 | `{"status":"BAD_REQUEST","title":"No value was provided for required object field \"title\""}` | `.badRequest(problem)` | Show `title` next to the form |
| 401 | *(empty)* | `.unauthorized` (after one refresh) | Back to sign-in |
| 403 | `{"status":"FORBIDDEN","title":"Forbidden"}` | `.forbidden` | "You don't have permission" |
| 404 | `{"status":"NOT_FOUND"}` | `.notFound` | Remove the item from the list |

Two Liferay behaviours to keep in mind:

- **Unknown picklist keys return 403**, not 400. A 403 on create may mean a bad key, not missing
  permission, so the app only sends keys taken from the picklist.
- **Another user's entry returns 404**, not 403. Liferay doesn't reveal that it exists.

`APIError.userMessage` gives a short, human-readable message for each case.

## 5. Dates and picklists

[`LiferayJSON`](../../ios/LiferayKit/Sources/LiferayKit/HTTP/LiferayJSON.swift) decodes both date
formats Liferay sends, plus a plain date:

| Field | Example |
|---|---|
| System fields (`dateCreated`, `dateModified`) | `2026-11-01T03:40:37Z` |
| Date fields on objects (`dueDate`) | `2026-12-31T00:00:00.000Z` |

A single `.iso8601` strategy would fail on one or the other.

[`PicklistValue`](../../ios/LiferayKit/Sources/LiferayKit/Models/Picklist.swift) decodes
`{"key": "open", "name": "Open"}` and encodes only `{"key": "open"}`, which is what Liferay expects.

## 6. Testing without a server

`APIClient` and `OAuthClient` take an `HTTPTransport` instead of using `URLSession` directly:

```swift
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
```

`URLSession` conforms in production. Tests use `MockTransport`, which replies with files recorded from
the real Liferay (`Tests/LiferayKitTests/Fixtures/`) and records what was sent:

```swift
let (client, transport, _) = makeClient([try .json(200, fixture: "my-user-account")])
let me = try await client.send(UserAccount.me)
#expect(me.name == "Jane Doe")
#expect(transport.sentRequests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
```

Because the fixtures are real responses, a decoding test failing after a Liferay upgrade means the
API really changed. CI re-records them on every run and flags any change in their structure.

## Checkpoint

```bash
cd ios/LiferayKit
swift test
```

```
✔ Test "Ten concurrent calls with an expired token cause exactly one refresh" passed
✔ Test "A 401 triggers one refresh and a retry with the new token" passed
✔ Test "Liferay's real error responses map to APIError" passed
…
✔ Test run with 20 tests passed
```

Next: [06 — My Profile](06-my-profile.md).
