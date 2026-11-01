import LiferayKit
import SwiftUI

/// Chapter 06: the signed-in user's own profile (the User system object).
struct ProfileView: View {
    let api: APIClient
    let user: UserAccount

    @Environment(AppModel.self) private var model
    @State private var draft: UserProfileDraft
    @State private var isSaving = false
    @State private var message: (text: String, isError: Bool)?
    @State private var isConfirmingSignOut = false

    init(api: APIClient, user: UserAccount) {
        self.api = api
        self.user = user
        _draft = State(initialValue: UserProfileDraft(user))
    }

    private var hasChanges: Bool { draft != UserProfileDraft(user) }

    var body: some View {
        Form {
            Section("Name") {
                TextField("First name", text: $draft.givenName).textContentType(.givenName)
                TextField("Last name", text: $draft.familyName).textContentType(.familyName)
                TextField("Job title", text: $draft.jobTitle).textContentType(.jobTitle)
            }
            Section {
                LabeledContent("Email", value: user.emailAddress)
                LabeledContent("Screen name", value: user.alternateName ?? "–")
            } footer: {
                Text("Email and screen name can only be changed by an administrator.")
            }
            if let message {
                Section { Text(message.text).foregroundStyle(message.isError ? .red : .green) }
            }
            Section {
                Button("Sign Out", role: .destructive) { isConfirmingSignOut = true }
            }
        }
        .navigationTitle("My Profile")
        .disabled(isSaving)
        .toolbar {
            if isSaving {
                ProgressView()
            } else {
                Button("Save") { Task { await save() } }.disabled(!hasChanges)
            }
        }
        .confirmationDialog("Sign out of Liferay?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { Task { await model.signOut() } }
        }
    }

    private func save() async {
        if let problem = draft.validationErrors.first {
            message = (problem, true)
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            // PATCH sends only the three fields; Liferay keeps everything else as it is.
            let updated = try await api.send(UserAccount.updateProfile(of: user.id, with: draft))
            model.userDidChange(updated)
            draft = UserProfileDraft(updated)
            message = ("Saved.", false)
        } catch {
            // A self-service user may edit only their own account; anything else is a 403.
            message = (userMessage(for: error), true)
        }
    }
}
