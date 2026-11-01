import Foundation
import Testing
@testable import LiferayKit

@Suite("Models")
struct ModelTests {
    let decoder = LiferayJSON.decoder

    func json(_ value: some Encodable) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: LiferayJSON.encoder.encode(value)) as? [String: Any] ?? [:]
    }

    // MARK: Service Request

    @Test("A recorded Service Request decodes, including picklists, creator and due date")
    func serviceRequest() throws {
        let request = try decoder.decode(ServiceRequest.self, from: fixture("service-request"))
        #expect(request.title == "Fixture: VPN keeps disconnecting")
        #expect(request.category == PicklistValue(key: "technical", name: "Technical"))
        #expect(request.requestStatus.key == "open")
        #expect(request.priority == 1)
        #expect(request.creator?.name == "Jane Doe")
        #expect(request.externalReferenceCode == "fixture-sr-0001")
        let day = Calendar.utc.dateComponents([.year, .month, .day], from: try #require(request.dueDate))
        #expect((day.year, day.month, day.day) == (2026, 12, 31))
    }

    @Test("Liferay returns an empty Integer field as 0; the model reads it as no priority")
    func emptyPriority() throws {
        let body = #"{"id":1,"title":"T","category":{"key":"other"},"requestStatus":{"key":"open"},"priority":0}"#
        #expect(try decoder.decode(ServiceRequest.self, from: Data(body.utf8)).priority == nil)
    }

    @Test("A draft sends only editable fields, picklist keys, a plain date and explicit nulls")
    func serviceRequestDraftEncoding() throws {
        var draft = ServiceRequestDraft(title: "  Printer jam ", description: "Tray 2",
                                        category: PicklistValue(key: "technical", name: "Technical"),
                                        requestStatus: PicklistValue(key: "open"), priority: 2,
                                        dueDate: DateComponents(year: 2026, month: 12, day: 24))
        var body = try json(draft)
        #expect(Set(body.keys) == ["title", "description", "category", "requestStatus", "priority", "dueDate"])
        #expect(body["title"] as? String == "Printer jam")
        #expect(body["category"] as? [String: String] == ["key": "technical"])
        #expect(body["dueDate"] as? String == "2026-12-24")
        #expect(body["priority"] as? Int == 2)

        draft.priority = nil
        draft.dueDate = nil
        body = try json(draft)
        #expect(body["priority"] is NSNull, "PUT replaces the entry, so null clears the field")
        #expect(body["dueDate"] is NSNull)
    }

    @Test("Editing pre-fills the draft from the entry, keeping the due date's calendar day")
    func draftFromRequest() throws {
        let request = try decoder.decode(ServiceRequest.self, from: fixture("service-request"))
        let draft = ServiceRequestDraft(request)
        #expect(draft.title == request.title)
        #expect(draft.category.key == "technical")
        #expect(draft.dueDate?.day == 31)
        #expect(draft.validationErrors.isEmpty)
        #expect(ServiceRequestDraft(category: draft.category, requestStatus: draft.requestStatus).validationErrors == ["Enter a title."])
    }

    @Test("Edits use PUT, creation uses PUT by external reference code, and lists sort newest first")
    func serviceRequestEndpoints() throws {
        let draft = ServiceRequestDraft(title: "T", category: ServiceRequestPicklists.categories[0],
                                        requestStatus: ServiceRequestPicklists.statuses[0])
        #expect(try ServiceRequest.update(7, with: draft).method == .put)
        let upsert = try ServiceRequest.upsert(draft, externalReferenceCode: "abc-123")
        #expect(upsert.method == .put)
        #expect(upsert.path == "/o/c/servicerequests/by-external-reference-code/abc-123")
        #expect(ServiceRequest.list().queryItems.contains(URLQueryItem(name: "sort", value: "dateCreated:desc")))
        #expect(ServiceRequest.delete(7).method == .delete)
    }

    // MARK: Addresses

    @Test("Recorded countries and regions decode, with English and localized titles")
    func countries() throws {
        let page = try decoder.decode(Page<Country>.self, from: fixture("countries-page"))
        let afghanistan = try #require(page.items.first)
        #expect(afghanistan.name == "afghanistan")
        #expect(afghanistan.englishName == "Afghanistan")
        #expect(afghanistan.a2 == "AF")
        #expect(!afghanistan.regions.isEmpty)
        let regions = try decoder.decode(Page<Region>.self, from: fixture("regions-page"))
        #expect(regions.items.first?.regionCode == "AL")
        #expect(regions.items.first?.title(for: Locale(identifier: "en_US")) == "Alabama")
    }

    @Test("A recorded postal address decodes and pre-fills the form with codes")
    func postalAddress() throws {
        let address = try decoder.decode(PostalAddress.self, from: fixture("postal-address"))
        #expect(address.addressCountry == "United States")
        #expect(address.singleLine.hasPrefix(address.streetAddressLine1))

        let california = Region(id: 1, name: "California", regionCode: "CA", titleI18n: ["en_US": "California"])
        let us = Country(id: 1, name: "united-states", a2: "US", regions: [california], titleI18n: ["en_US": "United States"])
        let draft = PostalAddressDraft(address, countries: [us])
        #expect(draft.country?.a2 == "US")
        #expect(draft.regionCode == "CA")
        #expect(draft.validationErrors.isEmpty)
    }

    @Test("The address draft sends the English country name and the region code")
    func postalAddressEncoding() throws {
        let berlin = Region(id: 1, name: "Berlin", regionCode: "BE", titleI18n: nil)
        var draft = PostalAddressDraft()
        draft.street = "Unter den Linden 1"
        draft.city = "Berlin"
        draft.postalCode = "10115"
        draft.country = Country(id: 2, name: "germany", a2: "DE", regions: [berlin],
                                titleI18n: ["en_US": "Germany", "de_DE": "Deutschland"])

        #expect(draft.validationErrors == ["Choose a state or region."])
        draft.regionCode = "BE"
        #expect(draft.validationErrors.isEmpty)

        let body = try json(draft.postalAddress(id: nil))
        #expect(body["addressCountry"] as? String == "Germany", "Not 'DE' or 'Deutschland': only the English name works everywhere")
        #expect(body["addressRegion"] as? String == "BE")
        #expect(body["id"] == nil)

        #expect(PostalAddressDraft().validationErrors.contains("Choose a country."),
                "An empty country would be saved as Afghanistan")
    }

    @Test("Adding an address replaces the whole list via PATCH on the user account")
    func replaceAddresses() throws {
        let existing = PostalAddress(id: 5, streetAddressLine1: "1 A St", addressLocality: "X", postalCode: "1", addressCountry: "United States")
        let endpoint = try UserAccount.replaceAddresses(of: 34267, with: [existing])
        #expect(endpoint.method == .patch)
        #expect(endpoint.path == "/o/headless-admin-user/v1.0/user-accounts/34267")
        let body = try JSONSerialization.jsonObject(with: try #require(endpoint.body)) as? [String: [String: [[String: Any]]]]
        #expect(body?["userAccountContactInformation"]?["postalAddresses"]?.first?["id"] as? Int == 5)
    }

    // MARK: Profile

    @Test("The profile draft sends only names and job title")
    func profileDraft() throws {
        let me = try decoder.decode(UserAccount.self, from: fixture("my-user-account"))
        var draft = UserProfileDraft(me)
        #expect(draft.givenName == "Jane")
        draft.jobTitle = " Analyst "
        let body = try json(draft)
        #expect(Set(body.keys) == ["givenName", "familyName", "jobTitle"])
        #expect(body["jobTitle"] as? String == "Analyst")
        draft.givenName = ""
        #expect(draft.validationErrors == ["Enter a first name."])
    }
}
