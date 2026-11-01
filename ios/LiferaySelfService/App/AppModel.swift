import AuthenticationServices
import Foundation
import LiferayKit
import Observation

/// The app's top-level state: who is signed in, and the Liferay clients every screen shares.
@MainActor
@Observable
final class AppModel {
    enum State: Equatable {
        case starting
        case signedOut
        case signingIn
        case signedIn(UserAccount)
        /// The app can't run, for example because `Config/Local.xcconfig` is missing.
        case misconfigured(String)
    }

    /// Opens Liferay's sign-in page in a browser sheet and returns the callback URL.
    /// In the app this is SwiftUI's `webAuthenticationSession`; tests can pass a fake.
    typealias Authenticate = @MainActor (_ url: URL, _ callbackURLScheme: String) async throws -> URL

    private(set) var state: State = .starting
    /// A message to show after a failed sign-in, cleared on the next attempt.
    var errorMessage: String?

    private let oauth: OAuthClient?
    private let session: AuthSession?
    let api: APIClient?

    init(bundle: Bundle = .main, store: TokenStore = KeychainTokenStore()) {
        do {
            let configuration = try LiferayConfiguration(bundle: bundle)
            let oauth = OAuthClient(configuration: configuration)
            let session = AuthSession(oauth: oauth, store: store)
            self.oauth = oauth
            self.session = session
            self.api = APIClient(baseURL: configuration.baseURL, session: session)
        } catch {
            self.oauth = nil
            self.session = nil
            self.api = nil
            self.state = .misconfigured(
                "Missing or invalid settings (\(error)). Copy ios/Config/Local.xcconfig.example to Local.xcconfig and fill it in."
            )
        }
    }

    /// Restores the previous session from the Keychain, if there is one.
    func start() async {
        guard let session, state == .starting else { return }
        if await session.isSignedIn {
            await loadSignedInUser()
        } else {
            state = .signedOut
        }
    }

    func signIn(using authenticate: Authenticate) async {
        guard let oauth, let session else { return }
        errorMessage = nil
        state = .signingIn

        let request = oauth.makeAuthorizationRequest()
        do {
            let callbackURL = try await authenticate(request.url, oauth.configuration.callbackURLScheme)
            let code = try oauth.authorizationCode(from: callbackURL, for: request)
            let tokens = try await oauth.exchange(code: code, for: request)
            try await session.signIn(with: tokens)
            await loadSignedInUser()
        } catch {
            state = .signedOut
            errorMessage = Self.message(for: error)
        }
    }

    func signOut() async {
        await session?.signOut()
        state = .signedOut
    }

    private func loadSignedInUser() async {
        guard let api else { return }
        do {
            state = .signedIn(try await api.send(UserAccount.me))
        } catch {
            await session?.signOut()
            state = .signedOut
            errorMessage = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String? {
        switch error {
        case let error as APIError:
            return error.userMessage
        case OAuthError.authorizationFailed("access_denied"):
            return "Access wasn't granted. Choose Authorize to continue."
        case let error as OAuthError:
            return "Sign-in failed (\(error)). Please try again."
        case AuthSession.SessionError.expired:
            return "Your session has ended. Please sign in again."
        case let error as ASWebAuthenticationSessionError where error.code == .canceledLogin:
            return nil // The user closed the sign-in sheet: not an error worth showing.
        default:
            return error.localizedDescription
        }
    }
}
