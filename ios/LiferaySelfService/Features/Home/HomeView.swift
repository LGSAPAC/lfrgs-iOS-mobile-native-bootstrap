import LiferayKit
import SwiftUI

/// The signed-in screen. Chapters 06–08 add Profile, Addresses and Service Requests here.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    let user: UserAccount

    var body: some View {
        NavigationStack {
            List {
                Section("Signed in as") {
                    LabeledContent("Name", value: user.name)
                    LabeledContent("Email", value: user.emailAddress)
                    if let jobTitle = user.jobTitle, !jobTitle.isEmpty {
                        LabeledContent("Job title", value: jobTitle)
                    }
                }
                Section("Coming in the next chapters") {
                    Label("My Profile", systemImage: "person.crop.circle")
                    Label("My Addresses", systemImage: "house")
                    Label("Service Requests", systemImage: "wrench.and.screwdriver")
                }
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Hi, \(user.givenName ?? user.name)")
            .toolbar {
                Button("Sign out", role: .destructive) {
                    Task { await model.signOut() }
                }
            }
        }
    }
}
