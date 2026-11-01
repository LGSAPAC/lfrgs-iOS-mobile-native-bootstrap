import Foundation
import LiferayKit
import Observation

/// The signed-in user's Service Requests: paging, search, status filter, delete.
@MainActor
@Observable
final class ServiceRequestListModel {
    private let api: APIClient
    private(set) var items: [ServiceRequest] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var canLoadMore = false
    var errorMessage: String?

    /// Bound to `.searchable`. Liferay's `search=` matches title and description.
    var searchText = ""
    /// A `requestStatus` key, or `nil` for all.
    var statusFilter: String?

    private var page = 1
    private let pageSize = 20

    init(api: APIClient) { self.api = api }

    /// Changes whenever the list must be reloaded from page 1.
    var queryKey: String { "\(searchText)|\(statusFilter ?? "")" }

    func reload() async {
        page = 1
        await load(replacing: true)
    }

    /// Infinite scroll: call when `item` appears on screen.
    func loadMoreIfNeeded(after item: ServiceRequest) async {
        guard item.id == items.last?.id, canLoadMore, !isLoading else { return }
        page += 1
        await load(replacing: false)
    }

    private func load(replacing: Bool) async {
        isLoading = true
        defer { isLoading = false }
        let query = ListQuery(
            page: page,
            pageSize: pageSize,
            sort: ["dateCreated:desc"],
            filter: statusFilter.map { "requestStatus eq \(ListQuery.quoted($0))" },
            search: searchText.trimmingCharacters(in: .whitespaces)
        )
        do {
            let result = try await api.send(ServiceRequest.list(query))
            items = replacing ? result.items : items + result.items.filter { new in !items.contains { $0.id == new.id } }
            canLoadMore = result.hasNextPage
            errorMessage = nil
        } catch is CancellationError {
            // The search text changed while loading; the next load replaces this one.
        } catch {
            errorMessage = userMessage(for: error)
        }
        hasLoaded = true
    }

    /// Removes the row at once, then asks Liferay; puts it back if that fails.
    func delete(_ request: ServiceRequest) async {
        guard let index = items.firstIndex(where: { $0.id == request.id }) else { return }
        items.remove(at: index)
        do {
            _ = try await api.send(ServiceRequest.delete(request.id))
        } catch APIError.notFound(_) {
            // Already gone: nothing to undo.
        } catch {
            items.insert(request, at: min(index, items.count))
            errorMessage = userMessage(for: error)
        }
    }

    /// A request was created or edited in the form.
    func didSave(_ request: ServiceRequest) {
        if let index = items.firstIndex(where: { $0.id == request.id }) {
            items[index] = request
        } else {
            items.insert(request, at: 0)
        }
    }
}
