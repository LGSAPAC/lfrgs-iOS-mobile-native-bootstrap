import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends authenticated requests to Liferay's headless APIs.
///
/// For every call it adds a valid Bearer token, `Accept: application/json` and the user's language.
/// If Liferay answers 401 it refreshes the token once and retries; if that fails too, the user is
/// signed out and the call throws ``APIError/unauthorized``.
public struct APIClient: Sendable {
    public let baseURL: URL
    let session: AuthSession
    let transport: HTTPTransport
    /// Sent as `Accept-Language`, so picklist names and error messages come back localized.
    let language: String

    public init(baseURL: URL, session: AuthSession, transport: HTTPTransport = URLSession.shared,
                language: String = Locale.preferredLanguages.first ?? "en-US") {
        self.baseURL = baseURL
        self.session = session
        self.transport = transport
        self.language = language
    }

    public func send<Response>(_ endpoint: Endpoint<Response>) async throws -> Response {
        let token = try await session.validAccessToken()
        var (data, response) = try await transport.send(request(for: endpoint, token: token))

        if response.statusCode == 401 {
            let retryToken = try await session.accessTokenAfterUnauthorized(token)
            (data, response) = try await transport.send(request(for: endpoint, token: retryToken))
            if response.statusCode == 401 {
                await session.signOut()
                throw APIError.unauthorized
            }
        }

        guard (200..<300).contains(response.statusCode) else {
            throw APIError(status: response.statusCode, body: data)
        }
        if Response.self == NoContent.self, let empty = NoContent() as? Response { return empty }
        do {
            return try LiferayJSON.decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    func request<Response>(for endpoint: Endpoint<Response>, token: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(String(endpoint.path.dropFirst())),
                                       resolvingAgainstBaseURL: false)!
        if !endpoint.queryItems.isEmpty {
            components.queryItems = endpoint.queryItems
            // URLComponents leaves "+" alone, but servers read it as a space: "C++" must stay "C++".
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(language, forHTTPHeaderField: "Accept-Language")
        if let body = endpoint.body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}
