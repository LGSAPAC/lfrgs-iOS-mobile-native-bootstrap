import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"
}

/// The response type for calls that return no body, such as `DELETE` (HTTP 204).
public struct NoContent: Decodable, Sendable, Equatable {
    public init() {}
}

/// One Liferay API call and the type its response decodes to.
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
    public var method: HTTPMethod
    /// Path below the Liferay base URL, for example `/o/headless-admin-user/v1.0/my-user-account`.
    public var path: String
    public var queryItems: [URLQueryItem]
    public var body: Data?

    public init(_ method: HTTPMethod, _ path: String, queryItems: [URLQueryItem] = [], body: Data? = nil) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.body = body
    }

    /// An endpoint with a JSON body, encoded the way Liferay expects.
    public init<Body: Encodable>(_ method: HTTPMethod, _ path: String, json: Body, queryItems: [URLQueryItem] = []) throws {
        self.init(method, path, queryItems: queryItems, body: try LiferayJSON.encoder.encode(json))
    }
}

/// Paging, sorting, searching and filtering, shared by every Liferay list endpoint.
public struct ListQuery: Sendable, Equatable {
    /// 1-based, as in Liferay.
    public var page: Int
    public var pageSize: Int
    /// For example `["dateCreated:desc"]`.
    public var sort: [String]
    /// An OData filter, for example `requestStatus eq 'open'`.
    public var filter: String?
    /// Full-text search.
    public var search: String?

    public init(page: Int = 1, pageSize: Int = 20, sort: [String] = [], filter: String? = nil, search: String? = nil) {
        self.page = page
        self.pageSize = pageSize
        self.sort = sort
        self.filter = filter
        self.search = search
    }

    public var queryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "pageSize", value: String(pageSize))]
        if !sort.isEmpty { items.append(URLQueryItem(name: "sort", value: sort.joined(separator: ","))) }
        if let filter, !filter.isEmpty { items.append(URLQueryItem(name: "filter", value: filter)) }
        if let search, !search.isEmpty { items.append(URLQueryItem(name: "search", value: search)) }
        return items
    }

    /// Quotes a value for an OData filter: `O'Brien` becomes `'O''Brien'`.
    public static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }
}
