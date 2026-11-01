import LiferayKit
import SwiftUI

/// Chapter 08: the user's Service Requests, newest first.
struct ServiceRequestListView: View {
    let api: APIClient
    @State private var model: ServiceRequestListModel
    @State private var isCreating = false
    @State private var pendingDelete: ServiceRequest?

    init(api: APIClient) {
        self.api = api
        _model = State(initialValue: ServiceRequestListModel(api: api))
    }

    var body: some View {
        List {
            if let message = model.errorMessage {
                Text(message).foregroundStyle(.red)
            }
            ForEach(model.items) { request in
                NavigationLink {
                    ServiceRequestDetailView(api: api, request: request, onSaved: model.didSave, onDeleted: {
                        Task { await model.delete(request) }
                    })
                } label: {
                    ServiceRequestRow(request: request)
                }
                .task { await model.loadMoreIfNeeded(after: request) }
                .swipeActions {
                    Button("Delete", role: .destructive) { pendingDelete = request }
                }
            }
            if model.isLoading && !model.items.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .overlay {
            if model.hasLoaded && model.items.isEmpty && model.errorMessage == nil {
                ContentUnavailableView(
                    model.searchText.isEmpty && model.statusFilter == nil ? "No service requests" : "No matches",
                    systemImage: "tray",
                    description: Text("Tap + to create one.")
                )
            } else if !model.hasLoaded {
                ProgressView()
            }
        }
        .navigationTitle("Service Requests")
        .searchable(text: $model.searchText, prompt: "Search requests")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Status", selection: $model.statusFilter) {
                        Text("All").tag(String?.none)
                        ForEach(ServiceRequestPicklists.statuses, id: \.key) { status in
                            Text(status.name ?? status.key).tag(String?.some(status.key))
                        }
                    }
                } label: {
                    Label("Filter", systemImage: model.statusFilter == nil
                          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("New request", systemImage: "plus") { isCreating = true }
            }
        }
        // Reload when the search text or filter changes, after a short pause while typing.
        .task(id: model.queryKey) {
            if model.hasLoaded { try? await Task.sleep(for: .milliseconds(350)) }
            guard !Task.isCancelled else { return }
            await model.reload()
        }
        .refreshable { await model.reload() }
        .sheet(isPresented: $isCreating) {
            NavigationStack {
                ServiceRequestFormView(api: api, editing: nil, onSaved: model.didSave)
            }
        }
        .confirmationDialog("Delete this request?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible, presenting: pendingDelete) { request in
            Button("Delete \"\(request.title)\"", role: .destructive) {
                Task { await model.delete(request) }
            }
        }
    }
}

struct ServiceRequestRow: View {
    let request: ServiceRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(request.title).font(.headline).lineLimit(2)
                Spacer()
                StatusBadge(status: request.requestStatus)
            }
            HStack(spacing: 8) {
                Text(request.category.name ?? request.category.key)
                if let priority = request.priority {
                    Text("·")
                    Text("P\(priority)")
                }
                if let dueDate = request.dueDate {
                    Text("·")
                    Text("Due \(dueDate.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt)))")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct StatusBadge: View {
    let status: PicklistValue

    var body: some View {
        Text(status.name ?? status.key)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status.key {
        case "open": .blue
        case "inProgress": .orange
        case "closed": .gray
        default: .secondary
        }
    }
}
