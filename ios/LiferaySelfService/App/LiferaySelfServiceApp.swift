import SwiftUI

@main
struct LiferaySelfServiceApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
        }
    }
}

/// Shows the screen that matches the app's state.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.state {
        case .starting:
            ProgressView("Starting…")
        case .signedOut, .signingIn:
            LoginView()
        case let .signedIn(user):
            HomeView(user: user)
        case let .misconfigured(message):
            ContentUnavailableView("Not configured", systemImage: "gearshape.2", description: Text(message))
        }
    }
}
