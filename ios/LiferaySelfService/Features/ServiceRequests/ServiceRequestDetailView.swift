import LiferayKit
import SwiftUI

struct ServiceRequestDetailView: View {
    let api: APIClient
    @State var request: ServiceRequest
    let onSaved: (ServiceRequest) -> Void
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var isConfirmingDelete = false

    var body: some View {
        List {
            Section {
                Text(request.title).font(.title3.bold())
                if let description = request.description, !description.isEmpty {
                    Text(description)
                }
            }
            Section {
                LabeledContent("Status") { StatusBadge(status: request.requestStatus) }
                LabeledContent("Category", value: request.category.name ?? request.category.key)
                LabeledContent("Priority", value: request.priority.map { "P\($0)" } ?? "None")
                if let dueDate = request.dueDate {
                    LabeledContent("Due", value: dueDate.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: .gmt)))
                }
            }
            Section {
                if let created = request.dateCreated {
                    LabeledContent("Created", value: created.formatted(date: .abbreviated, time: .shortened))
                }
                if let modified = request.dateModified {
                    LabeledContent("Updated", value: modified.formatted(date: .abbreviated, time: .shortened))
                }
                if let creator = request.creator?.name {
                    LabeledContent("Created by", value: creator)
                }
            }
            Section {
                Button("Delete Request", role: .destructive) { isConfirmingDelete = true }
            }
        }
        .navigationTitle("Request")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { isEditing = true }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                ServiceRequestFormView(api: api, editing: request) { saved in
                    request = saved
                    onSaved(saved)
                }
            }
        }
        .confirmationDialog("Delete this request?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                onDeleted()
                dismiss()
            }
        }
    }
}
