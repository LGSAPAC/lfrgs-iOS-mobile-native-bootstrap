import Foundation
import LiferayKit

/// A short message for an error, suitable for showing to the user.
func userMessage(for error: Error) -> String {
    switch error {
    case let error as APIError: error.userMessage
    case AuthSession.SessionError.expired, AuthSession.SessionError.signedOut: "Your session has ended. Please sign in again."
    case let error as URLError where error.code == .notConnectedToInternet: "You're offline. Check your connection and try again."
    case let error as URLError where error.code == .cannotConnectToHost: "Can't reach Liferay. Is the server running?"
    default: error.localizedDescription
    }
}
