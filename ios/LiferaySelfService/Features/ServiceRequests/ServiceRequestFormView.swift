import LiferayKit
import SwiftUI

/// Creates a Service Request (`editing == nil`) or edits one.
struct ServiceRequestFormView: View {
    let api: APIClient
    let editing: ServiceRequest?
    let onSaved: (ServiceRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ServiceRequestDraft
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Generated once per new form: retrying "Save" after a network error updates the same entry
    /// instead of creating a duplicate (PUT …/by-external-reference-code/{code}).
    @State private var externalReferenceCode = UUID().uuidString

    init(api: APIClient, editing: ServiceRequest?, onSaved: @escaping (ServiceRequest) -> Void) {
        self.api = api
        self.editing = editing
        self.onSaved = onSaved
        let draft = editing.map { ServiceRequestDraft($0) } ?? ServiceRequestDraft(
            category: ServiceRequestPicklists.categories[0], requestStatus: ServiceRequestPicklists.statuses[0])
        _draft = State(initialValue: draft)
        _hasDueDate = State(initialValue: draft.dueDate != nil)
        // The picker shows the user's calendar day; Liferay stores the same day at midnight UTC.
        _dueDate = State(initialValue: draft.dueDate.flatMap { Calendar.current.date(from: $0) } ?? .now)
    }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $draft.title)
                TextField("Description", text: $draft.description, axis: .vertical)
                    .lineLimit(3...8)
            }
            Section {
                // Only keys from the picklist: Liferay answers an unknown key with 403.
                Picker("Category", selection: $draft.category.key) {
                    ForEach(ServiceRequestPicklists.categories, id: \.key) { Text($0.name ?? $0.key).tag($0.key) }
                }
                Picker("Status", selection: $draft.requestStatus.key) {
                    ForEach(ServiceRequestPicklists.statuses, id: \.key) { Text($0.name ?? $0.key).tag($0.key) }
                }
                Picker("Priority", selection: $draft.priority) {
                    Text("None").tag(Int?.none)
                    Text("P1 — High").tag(Int?.some(1))
                    Text("P2 — Medium").tag(Int?.some(2))
                    Text("P3 — Low").tag(Int?.some(3))
                }
            }
            Section {
                Toggle("Due date", isOn: $hasDueDate.animation())
                if hasDueDate {
                    DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(editing == nil ? "New Request" : "Edit Request")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { Task { await save() } }
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() async {
        var draft = draft
        draft.dueDate = hasDueDate ? Calendar.current.dateComponents([.year, .month, .day], from: dueDate) : nil
        if let problem = draft.validationErrors.first {
            errorMessage = problem
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved: ServiceRequest
            if let editing {
                saved = try await api.send(ServiceRequest.update(editing.id, with: draft))
            } else {
                saved = try await api.send(ServiceRequest.upsert(draft, externalReferenceCode: externalReferenceCode))
            }
            onSaved(saved)
            dismiss()
        } catch {
            errorMessage = userMessage(for: error)
        }
    }
}
