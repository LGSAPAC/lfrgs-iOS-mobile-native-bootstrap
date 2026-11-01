import Foundation
import LiferayKit

/// An in-memory stand-in for the Liferay endpoints the app uses, so the app can run without a
/// server: in SwiftUI previews, and in CI, which launches it with `--demo` to take screenshots.
///
/// The JSON shapes copy the responses recorded from Liferay DXP 2026.Q1
/// (`ios/LiferayKit/Tests/LiferayKitTests/Fixtures`). It is **not** used unless the app is
/// launched with `--demo`.
actor DemoBackend: HTTPTransport {
    private var user: [String: Any] = [
        "id": 34267, "name": "Jane Doe", "givenName": "Jane", "familyName": "Doe",
        "alternateName": "jane.doe", "emailAddress": "jane.doe@example.com", "jobTitle": "Customer",
        "languageId": "en_US", "dateCreated": "2026-11-01T00:31:48Z",
    ]
    private var addresses: [[String: Any]] = [
        ["id": 501, "name": "Home", "streetAddressLine1": "1400 Montefino Ave", "addressLocality": "Diamond Bar",
         "addressRegion": "California", "postalCode": "91765", "addressCountry": "United States",
         "addressType": "personal", "primary": true],
        ["id": 502, "name": "Office", "streetAddressLine1": "Unter den Linden 1", "addressLocality": "Berlin",
         "addressRegion": "Berlin", "postalCode": "10115", "addressCountry": "Germany",
         "addressType": "personal", "primary": false],
    ]
    private var requests: [[String: Any]] = [
        DemoBackend.request(id: 901, title: "VPN keeps disconnecting", description: "Drops every 10 minutes on the office Wi-Fi.",
                            category: "technical", status: "inProgress", priority: 1, dueDate: "2026-11-15", created: "2026-11-01T09:12:00Z"),
        DemoBackend.request(id: 902, title: "Update billing address", description: "We moved to a new office.",
                            category: "billing", status: "open", priority: 2, dueDate: nil, created: "2026-10-30T14:03:00Z"),
        DemoBackend.request(id: 903, title: "Add a second admin user", description: "",
                            category: "account", status: "open", priority: 3, dueDate: "2026-12-01", created: "2026-10-28T08:40:00Z"),
        DemoBackend.request(id: 904, title: "Invoice 2026-10 is missing", description: "Not in the portal yet.",
                            category: "billing", status: "closed", priority: 0, dueDate: nil, created: "2026-10-21T11:25:00Z"),
    ]
    private var nextID = 1000

    // MARK: HTTPTransport

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(for: .milliseconds(250)) // feel like a network
        let url = request.url!
        let path = url.path
        let method = request.httpMethod ?? "GET"
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let query = Dictionary((URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
                               uniquingKeysWith: { a, _ in a })

        switch (method, path) {
        case ("POST", "/o/oauth2/token"):
            return respond(url, ["access_token": "demo", "token_type": "Bearer", "expires_in": 600, "refresh_token": "demo"])

        case ("GET", "/o/headless-admin-user/v1.0/my-user-account"):
            return respond(url, user)

        case ("PATCH", "/o/headless-admin-user/v1.0/user-accounts/34267"):
            if let contact = body["userAccountContactInformation"] as? [String: Any],
               let list = contact["postalAddresses"] as? [[String: Any]] {
                addresses = list.map { address in
                    var address = normalized(address)
                    if address["id"] == nil { address["id"] = newID() }
                    return address
                }
            }
            for key in ["givenName", "familyName", "jobTitle"] { if let value = body[key] { user[key] = value } }
            user["name"] = "\(user["givenName"] ?? "") \(user["familyName"] ?? "")"
            return respond(url, user)

        case ("GET", "/o/headless-admin-user/v1.0/user-accounts/34267/postal-addresses"):
            return respond(url, page(addresses))

        case ("GET", "/o/headless-admin-address/v1.0/countries"):
            return respond(url, page(Self.countries))

        case ("GET", "/o/c/servicerequests"):
            var items = requests
            if let filter = query["filter"], let key = filter.split(separator: "'").dropFirst().first {
                items = items.filter { ($0["requestStatus"] as? [String: Any])?["key"] as? String == String(key) }
            }
            if let search = query["search"], !search.isEmpty {
                items = items.filter { ($0["title"] as? String ?? "").localizedCaseInsensitiveContains(search) }
            }
            return respond(url, page(items))

        default:
            break
        }

        if path.hasPrefix("/o/headless-admin-user/v1.0/postal-addresses/"), let id = Int(path.split(separator: "/").last!) {
            guard let index = addresses.firstIndex(where: { $0["id"] as? Int == id }) else { return status(url, 404) }
            if method == "DELETE" { addresses.remove(at: index); return status(url, 204) }
            if method == "PUT" { addresses[index] = normalized(body).merging(["id": id]) { $1 } }
            return respond(url, addresses[index])
        }

        if path.hasPrefix("/o/c/servicerequests/by-external-reference-code/"), method == "PUT" {
            let code = String(path.split(separator: "/").last!)
            if let index = requests.firstIndex(where: { $0["externalReferenceCode"] as? String == code }) {
                requests[index] = updated(requests[index], with: body)
                return respond(url, requests[index])
            }
            var created = updated(Self.request(id: newID(), title: "", description: "", category: "other", status: "open",
                                               priority: 0, dueDate: nil, created: Date.now.ISO8601Format()), with: body)
            created["externalReferenceCode"] = code
            requests.insert(created, at: 0)
            return respond(url, created)
        }

        if path.hasPrefix("/o/c/servicerequests/"), let id = Int(path.split(separator: "/").last!) {
            guard let index = requests.firstIndex(where: { $0["id"] as? Int == id }) else { return status(url, 404) }
            switch method {
            case "DELETE": requests.remove(at: index); return status(url, 204)
            case "PUT": requests[index] = updated(requests[index], with: body)
            default: break
            }
            return respond(url, requests[index])
        }

        return status(url, 404)
    }

    // MARK: Helpers

    private func newID() -> Int { nextID += 1; return nextID }

    private func page(_ items: [[String: Any]]) -> [String: Any] {
        ["items": items, "page": 1, "pageSize": max(items.count, 20), "totalCount": items.count, "lastPage": 1]
    }

    private func respond(_ url: URL, _ json: [String: Any]) -> (Data, HTTPURLResponse) {
        (try! JSONSerialization.data(withJSONObject: json), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    private func status(_ url: URL, _ code: Int) -> (Data, HTTPURLResponse) {
        (Data(), HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!)
    }

    /// Liferay stores the country/region it matched and returns their names; mimic that.
    private func normalized(_ address: [String: Any]) -> [String: Any] {
        var address = address
        let countryValue = address["addressCountry"] as? String
        let regionValue = address["addressRegion"] as? String
        if let country = Self.countries.first(where: { Self.matches($0, countryValue) }) {
            address["addressCountry"] = (country["title_i18n"] as? [String: String])?["en_US"]
            let regions = country["regions"] as? [[String: Any]] ?? []
            address["addressRegion"] = regions.first { $0["regionCode"] as? String == regionValue
                || $0["name"] as? String == regionValue }?["name"]
        }
        return address
    }

    private static func matches(_ country: [String: Any], _ value: String?) -> Bool {
        guard let value else { return false }
        return [country["a2"] as? String, country["name"] as? String, (country["title_i18n"] as? [String: String])?["en_US"]]
            .contains { $0 == value }
    }

    private func updated(_ request: [String: Any], with body: [String: Any]) -> [String: Any] {
        var request = request
        for key in ["title", "description"] { if let value = body[key] as? String { request[key] = value } }
        for (key, names) in [("category", ServiceRequestPicklists.categories), ("requestStatus", ServiceRequestPicklists.statuses)] {
            if let picked = (body[key] as? [String: Any])?["key"] as? String {
                request[key] = ["key": picked, "name": names.first { $0.key == picked }?.name ?? picked]
            }
        }
        request["priority"] = body["priority"] as? Int ?? 0
        if let day = body["dueDate"] as? String { request["dueDate"] = day + "T00:00:00.000Z" } else { request["dueDate"] = nil }
        request["dateModified"] = Date.now.ISO8601Format()
        return request
    }

    private static func request(id: Int, title: String, description: String, category: String, status: String,
                                priority: Int, dueDate: String?, created: String) -> [String: Any] {
        var request: [String: Any] = [
            "id": id, "externalReferenceCode": UUID().uuidString, "title": title, "description": description,
            "category": ["key": category, "name": ServiceRequestPicklists.categories.first { $0.key == category }?.name ?? category],
            "requestStatus": ["key": status, "name": ServiceRequestPicklists.statuses.first { $0.key == status }?.name ?? status],
            "priority": priority, "dateCreated": created, "dateModified": created,
            "creator": ["id": 34267, "name": "Jane Doe"],
        ]
        if let dueDate { request["dueDate"] = dueDate + "T00:00:00.000Z" }
        return request
    }

    // Computed, not stored: a static stored [String: Any] isn't concurrency-safe in Swift 6.
    private static var countries: [[String: Any]] { [
        country(1, "australia", "AU", "Australia", [("NSW", "New South Wales"), ("VIC", "Victoria"), ("QLD", "Queensland")]),
        country(2, "germany", "DE", "Germany", [("BE", "Berlin"), ("BY", "Bavaria"), ("HH", "Hamburg")]),
        country(3, "singapore", "SG", "Singapore", []),
        country(4, "united-states", "US", "United States", [("CA", "California"), ("NY", "New York"), ("TX", "Texas")]),
    ] }

    private static func country(_ id: Int, _ name: String, _ a2: String, _ title: String, _ regions: [(String, String)]) -> [String: Any] {
        ["id": id, "name": name, "a2": a2, "title_i18n": ["en_US": title],
         "regions": regions.enumerated().map { ["id": id * 100 + $0.offset, "name": $0.element.1, "regionCode": $0.element.0,
                                                "title_i18n": ["en_US": $0.element.1]] }]
    }
}

extension AppModel {
    /// The app running against ``DemoBackend``, already signed in as Jane.
    static func demo() -> AppModel {
        let configuration = LiferayConfiguration(baseURL: URL(string: "https://demo.invalid")!, clientID: "demo",
                                                 redirectURI: URL(string: "com.liferay.sample.selfservice://oauth2redirect")!)
        let tokens = OAuthTokens(accessToken: "demo", refreshToken: "demo", expiresAt: .distantFuture, scope: nil)
        return AppModel(configuration: configuration, transport: DemoBackend(), store: InMemoryTokenStore(tokens))
    }
}
