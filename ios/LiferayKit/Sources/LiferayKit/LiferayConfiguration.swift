import Foundation

/// Where the app's Liferay is, and how the app is registered there.
public struct LiferayConfiguration: Sendable, Equatable {
    /// For example `http://localhost:8080`.
    public var baseURL: URL
    /// The *Client ID* of the OAuth 2 application (chapter 02, step 3).
    public var clientID: String
    /// One of the application's *Callback URIs*, for example `com.liferay.sample.selfservice://oauth2redirect`.
    public var redirectURI: URL

    public init(baseURL: URL, clientID: String, redirectURI: URL) {
        self.baseURL = baseURL
        self.clientID = clientID
        self.redirectURI = redirectURI
    }

    /// The custom URL scheme that `ASWebAuthenticationSession` listens for.
    public var callbackURLScheme: String { redirectURI.scheme ?? "" }

    public enum ConfigurationError: Error, Equatable {
        case missingValue(key: String)
        case invalidURL(key: String, value: String)
    }

    /// Reads `LiferayBaseURL`, `OAuthClientID` and `OAuthRedirectURI` from the app's `Info.plist`.
    /// Their values come from `Config/Local.xcconfig` (chapter 03).
    public init(bundle: Bundle) throws {
        func value(_ key: String) throws -> String {
            guard let value = bundle.object(forInfoDictionaryKey: key) as? String,
                  !value.isEmpty, !value.hasPrefix("$(") else {
                throw ConfigurationError.missingValue(key: key)
            }
            return value
        }
        func url(_ key: String) throws -> URL {
            let string = try value(key)
            guard let url = URL(string: string), url.scheme != nil else {
                throw ConfigurationError.invalidURL(key: key, value: string)
            }
            return url
        }
        self.init(
            baseURL: try url("LiferayBaseURL"),
            clientID: try value("OAuthClientID"),
            redirectURI: try url("OAuthRedirectURI")
        )
    }
}
