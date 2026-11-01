import SwiftUI

@main
struct LiferaySelfServiceApp: App {
    /// `--demo` runs against an in-memory backend instead of Liferay (see `DemoBackend`).
    /// `--tab requests|addresses|profile` picks the first tab. CI uses both for screenshots.
    @State private var model = LaunchOptions.isDemo ? AppModel.demo() : AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
        }
    }
}

enum LaunchOptions {
    static var arguments: [String] { ProcessInfo.processInfo.arguments }
    static var isDemo: Bool { arguments.contains("--demo") }
    static var initialTab: HomeView.Tab {
        guard let index = arguments.firstIndex(of: "--tab"), index + 1 < arguments.count else { return .requests }
        return HomeView.Tab(rawValue: arguments[index + 1]) ?? .requests
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
            HomeView(user: user, initialTab: LaunchOptions.initialTab)
        case let .misconfigured(message):
            ContentUnavailableView("Not configured", systemImage: "gearshape.2", description: Text(message))
        }
    }
}
