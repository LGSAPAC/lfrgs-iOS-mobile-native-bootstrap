import AuthenticationServices
import SwiftUI

/// The signed-out screen. "Sign in" opens Liferay's own sign-in page in a secure browser sheet
/// (`ASWebAuthenticationSession`); the app never sees the user's password.
struct LoginView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "person.badge.key")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Liferay Self-Service")
                .font(.largeTitle.bold())
            Text("Sign in with your Liferay account to manage your profile, addresses and service requests.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if let message = model.errorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Spacer()

            Button {
                Task { await model.signIn(using: authenticate) }
            } label: {
                if model.state == .signingIn {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Sign in").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.state == .signingIn)
        }
        .padding(24)
    }

    /// `.ephemeral` doesn't share cookies with Safari, so after "Sign out" the next "Sign in" really
    /// asks for credentials again. (Liferay 2026.Q1 has no token revocation endpoint, so ending the
    /// web session this way is the cleanest sign-out available.)
    private func authenticate(url: URL, callbackURLScheme: String) async throws -> URL {
        try await webAuthenticationSession.authenticate(
            using: url,
            callbackURLScheme: callbackURLScheme,
            preferredBrowserSession: .ephemeral
        )
    }
}
