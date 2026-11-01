import Foundation
import LiferayKit
import Observation

/// Chapter 07: the signed-in user's postal addresses (a Liferay system object).
@MainActor
@Observable
final class AddressListModel {
    private let api: APIClient
    let userAccountID: Int
    private(set) var addresses: [PostalAddress] = []
    private(set) var countries: [Country] = []
    private(set) var hasLoaded = false
    var errorMessage: String?

    init(api: APIClient, userAccountID: Int) {
        self.api = api
        self.userAccountID = userAccountID
    }

    func load() async {
        do {
            async let list = api.send(PostalAddress.list(userAccountID: userAccountID))
            if countries.isEmpty {
                // ~250 countries with their regions, sorted by the user's language. Loaded once.
                countries = try await api.send(Country.all).items
                    .sorted { $0.title().localizedStandardCompare($1.title()) == .orderedAscending }
            }
            addresses = try await list.items
            errorMessage = nil
        } catch {
            errorMessage = userMessage(for: error)
        }
        hasLoaded = true
    }

    /// Adds an address. Liferay 2026.Q1 has no POST for a user's addresses, so this sends the
    /// complete list (every existing address plus the new one) with PATCH on the user account.
    /// An address missing from that list would be deleted, so reload first to include any added
    /// elsewhere since the screen opened.
    func add(_ draft: PostalAddressDraft) async throws {
        let current = try await api.send(PostalAddress.list(userAccountID: userAccountID)).items
        _ = try await api.send(UserAccount.replaceAddresses(of: userAccountID, with: current + [draft.postalAddress(id: nil)]))
        await load()
    }

    /// Edits one address in place (PUT, so a cleared field really is cleared).
    func update(_ id: Int, with draft: PostalAddressDraft) async throws {
        let saved = try await api.send(PostalAddress.update(id, with: draft))
        if let index = addresses.firstIndex(where: { $0.id == id }) { addresses[index] = saved }
    }

    func delete(_ address: PostalAddress) async {
        guard let id = address.id, let index = addresses.firstIndex(where: { $0.id == id }) else { return }
        addresses.remove(at: index)
        do {
            _ = try await api.send(PostalAddress.delete(id))
        } catch {
            addresses.insert(address, at: min(index, addresses.count))
            errorMessage = userMessage(for: error)
        }
    }
}
