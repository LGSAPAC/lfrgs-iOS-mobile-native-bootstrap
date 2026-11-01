import LiferayKit
import SwiftUI

/// The signed-in app: one tab per chapter (06 Profile, 07 Addresses, 08 Service Requests).
struct HomeView: View {
    enum Tab: String { case requests, addresses, profile }

    @Environment(AppModel.self) private var model
    let user: UserAccount
    @State private var tab: Tab

    init(user: UserAccount, initialTab: Tab = .requests) {
        self.user = user
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        if let api = model.api {
            TabView(selection: $tab) {
                NavigationStack { ServiceRequestListView(api: api) }
                    .tabItem { Label("Requests", systemImage: "wrench.and.screwdriver") }
                    .tag(Tab.requests)
                NavigationStack { AddressListView(api: api, userAccountID: user.id) }
                    .tabItem { Label("Addresses", systemImage: "house") }
                    .tag(Tab.addresses)
                NavigationStack { ProfileView(api: api, user: user) }
                    .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                    .tag(Tab.profile)
            }
        }
    }
}
