import Foundation

/// Liferay's JSON error body, for example
/// `{"status": "BAD_REQUEST", "title": "No value was provided for required object field \"title\""}`.
/// Both fields are optional: a 404 carries only `status`, and a 401 has no body at all.
public struct Problem: Decodable, Sendable, Equatable {
    public var status: String?
    public var title: String?
    public var type: String?

    public init(status: String? = nil, title: String? = nil, type: String? = nil) {
        self.status = status
        self.title = title
        self.type = type
    }
}

/// Every way a Liferay API call can fail, already sorted into what the UI needs to do about it.
public enum APIError: Error, Sendable, Equatable {
    /// 401 even after refreshing the token: the user must sign in again.
    case unauthorized
    /// 403. **Note:** Liferay also answers 403 when a request names an unknown picklist key.
    case forbidden(Problem?)
    /// 404. Liferay also answers 404 for an entry that exists but the user may not see.
    case notFound(Problem?)
    /// 400, typically a validation error such as a missing required field.
    case badRequest(Problem?)
    /// Any other non-2xx status.
    case server(status: Int, Problem?)
    /// The response was not the JSON we expected.
    case decoding(String)

    init(status: Int, body: Data) {
        let problem = body.isEmpty ? nil : try? LiferayJSON.decoder.decode(Problem.self, from: body)
        switch status {
        case 400: self = .badRequest(problem)
        case 401: self = .unauthorized
        case 403: self = .forbidden(problem)
        case 404: self = .notFound(problem)
        default: self = .server(status: status, problem)
        }
    }

    /// A short message that can be shown to the user.
    public var userMessage: String {
        switch self {
        case .unauthorized: "Your session has ended. Please sign in again."
        case .forbidden: "You don't have permission to do that."
        case .notFound: "That item no longer exists."
        case let .badRequest(problem): problem?.title ?? "Please check the form and try again."
        case .server: "Something went wrong on the server. Please try again."
        case .decoding: "The server sent an unexpected response."
        }
    }
}
