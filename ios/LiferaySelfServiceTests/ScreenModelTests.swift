import Foundation
import LiferayKit
import Testing
@testable import LiferaySelfService

/// Tests for the screens' models, run against `DemoBackend` (no server needed). They check what
/// the user sees after each action: the same logic the views call.
@MainActor
@Suite("Screen models")
struct ScreenModelTests {
    func makeAPI() -> APIClient {
        let backend = DemoBackend()
        let tokens = OAuthTokens(accessToken: "demo", refreshToken: "demo", expiresAt: .distantFuture, scope: nil)
        let configuration = LiferayConfiguration(baseURL: URL(string: "https://demo.invalid")!, clientID: "demo",
                                                 redirectURI: URL(string: "com.liferay.sample.selfservice://oauth2redirect")!)
        let session = AuthSession(oauth: OAuthClient(configuration: configuration, transport: backend),
                                  store: InMemoryTokenStore(tokens))
        return APIClient(baseURL: configuration.baseURL, session: session, transport: backend, language: "en-US")
    }

    // MARK: Service Requests (chapter 08)

    @Test("The list loads, filters by status and searches")
    func listFilterAndSearch() async {
        let model = ServiceRequestListModel(api: makeAPI())
        await model.reload()
        #expect(model.items.count == 4)
        #expect(model.hasLoaded)

        model.statusFilter = "open"
        await model.reload()
        #expect(model.items.map(\.requestStatus.key) == ["open", "open"])

        model.statusFilter = nil
        model.searchText = "invoice"
        await model.reload()
        #expect(model.items.map(\.title) == ["Invoice 2026-10 is missing"])
    }

    @Test("Saving a new request puts it at the top; deleting removes it on the server too")
    func createAndDelete() async throws {
        let api = makeAPI()
        let model = ServiceRequestListModel(api: api)
        await model.reload()

        let draft = ServiceRequestDraft(title: "Printer jam", category: PicklistValue(key: "technical"),
                                        requestStatus: PicklistValue(key: "open"), priority: 2)
        let created = try await api.send(ServiceRequest.upsert(draft, externalReferenceCode: "test-1"))
        model.didSave(created)
        #expect(model.items.first?.title == "Printer jam")

        await model.delete(created)
        #expect(!model.items.contains { $0.id == created.id })
        await model.reload()
        #expect(model.items.count == 4, "The delete reached the backend")
    }

    // MARK: Addresses (chapter 07)

    @Test("Addresses and countries load; adding keeps the existing addresses")
    func addAddress() async throws {
        let model = AddressListModel(api: makeAPI(), userAccountID: 34267)
        await model.load()
        #expect(model.addresses.count == 2)
        #expect(model.countries.map(\.a2).contains("SG"))

        var draft = PostalAddressDraft()
        draft.street = "1 Raffles Place"
        draft.city = "Singapore"
        draft.postalCode = "048616"
        draft.country = model.countries.first { $0.a2 == "SG" }
        #expect(draft.validationErrors.isEmpty)

        try await model.add(draft)
        #expect(model.addresses.count == 3)
        #expect(model.addresses.last?.addressCountry == "Singapore")
    }

    @Test("Editing an address changes its region")
    func editAddress() async throws {
        let model = AddressListModel(api: makeAPI(), userAccountID: 34267)
        await model.load()
        let home = try #require(model.addresses.first)
        var draft = PostalAddressDraft(home, countries: model.countries)
        #expect(draft.country?.a2 == "US")
        #expect(draft.regionCode == "CA")

        draft.regionCode = "NY"
        try await model.update(try #require(home.id), with: draft)
        #expect(model.addresses.first?.addressRegion == "New York")
    }

    // MARK: Sign-in state (chapter 04)

    @Test("The demo app starts signed in as Jane and signs out")
    func appModelSession() async {
        let model = AppModel.demo()
        await model.start()
        guard case let .signedIn(user) = model.state else {
            Issue.record("Expected signed in, got \(model.state)")
            return
        }
        #expect(user.name == "Jane Doe")

        await model.signOut()
        #expect(model.state == .signedOut)
    }
}
