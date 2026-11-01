import LiferayKit
import SwiftUI

struct AddressFormView: View {
    let title: String
    let countries: [Country]
    let onSave: (PostalAddressDraft) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PostalAddressDraft
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(title: String, draft: PostalAddressDraft, countries: [Country],
         onSave: @escaping (PostalAddressDraft) async throws -> Void) {
        self.title = title
        self.countries = countries
        self.onSave = onSave
        _draft = State(initialValue: draft)
    }

    /// Countries are picked by their two-letter code; choosing another country clears the region.
    private var countryCode: Binding<String> {
        Binding(
            get: { draft.country?.a2 ?? "" },
            set: { code in
                draft.country = countries.first { $0.a2 == code }
                draft.regionCode = ""
            }
        )
    }

    var body: some View {
        Form {
            Section {
                TextField("Label (e.g. Home)", text: $draft.name)
                TextField("Street", text: $draft.street).textContentType(.streetAddressLine1)
                TextField("Street line 2", text: $draft.street2).textContentType(.streetAddressLine2)
                TextField("City", text: $draft.city).textContentType(.addressCity)
                TextField("Postal code", text: $draft.postalCode).textContentType(.postalCode)
            }
            Section {
                Picker("Country", selection: countryCode) {
                    Text("Choose…").tag("")
                    ForEach(countries) { Text($0.title()).tag($0.a2) }
                }
                .pickerStyle(.navigationLink)

                if let regions = draft.country?.regions, !regions.isEmpty {
                    // Required when the country has regions: Liferay answers "Region not found" otherwise.
                    Picker("State / Region", selection: $draft.regionCode) {
                        Text("Choose…").tag("")
                        ForEach(regions) { Text($0.title()).tag($0.regionCode) }
                    }
                    .pickerStyle(.navigationLink)
                }
            }
            Section {
                Toggle("Primary address", isOn: $draft.primary)
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving { ProgressView() } else { Button("Save") { Task { await save() } } }
            }
        }
    }

    private func save() async {
        if let problem = draft.validationErrors.first {
            errorMessage = problem
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(draft)
            dismiss()
        } catch {
            errorMessage = userMessage(for: error)
        }
    }
}
