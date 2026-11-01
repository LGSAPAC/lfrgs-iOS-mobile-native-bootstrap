import Foundation

/// An entry of the custom **Service Request** object (`/o/c/servicerequests`, chapter 02).
public struct ServiceRequest: Decodable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var externalReferenceCode: String?
    public var title: String
    public var description: String?
    public var category: PicklistValue
    public var requestStatus: PicklistValue
    public var priority: Int?
    public var dueDate: Date?
    public var dateCreated: Date?
    public var dateModified: Date?
    public var creator: Creator?

    enum CodingKeys: String, CodingKey {
        case id, externalReferenceCode, title, description, category, requestStatus, priority, dueDate,
             dateCreated, dateModified, creator
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        externalReferenceCode = try c.decodeIfPresent(String.self, forKey: .externalReferenceCode)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        category = try c.decode(PicklistValue.self, forKey: .category)
        requestStatus = try c.decode(PicklistValue.self, forKey: .requestStatus)
        // An empty Integer field comes back as 0, not null: treat 0 as "no priority".
        priority = try c.decodeIfPresent(Int.self, forKey: .priority).flatMap { $0 == 0 ? nil : $0 }
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        dateCreated = try c.decodeIfPresent(Date.self, forKey: .dateCreated)
        dateModified = try c.decodeIfPresent(Date.self, forKey: .dateModified)
        creator = try c.decodeIfPresent(Creator.self, forKey: .creator)
    }
}

/// What the app sends when creating or editing a Service Request: only the fields a user may set.
public struct ServiceRequestDraft: Encodable, Sendable, Equatable {
    public var title: String
    public var description: String
    public var category: PicklistValue
    public var requestStatus: PicklistValue
    public var priority: Int?
    /// A calendar day; sent as `2026-12-31`.
    public var dueDate: DateComponents?

    public init(title: String = "", description: String = "", category: PicklistValue,
                requestStatus: PicklistValue, priority: Int? = nil, dueDate: DateComponents? = nil) {
        self.title = title
        self.description = description
        self.category = category
        self.requestStatus = requestStatus
        self.priority = priority
        self.dueDate = dueDate
    }

    /// Pre-fills an edit form from an existing entry.
    public init(_ request: ServiceRequest, calendar: Calendar = .utc) {
        self.init(
            title: request.title,
            description: request.description ?? "",
            category: PicklistValue(key: request.category.key),
            requestStatus: PicklistValue(key: request.requestStatus.key),
            priority: request.priority,
            dueDate: request.dueDate.map { calendar.dateComponents([.year, .month, .day], from: $0) }
        )
    }

    /// Problems to fix before saving, or an empty list.
    public var validationErrors: [String] {
        var errors: [String] = []
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("Enter a title.") }
        if let priority, !(1...3).contains(priority) { errors.append("Priority must be 1, 2 or 3.") }
        return errors
    }

    enum CodingKeys: String, CodingKey {
        case title, description, category, requestStatus, priority, dueDate
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(category, forKey: .category)
        try container.encode(requestStatus, forKey: .requestStatus)
        // Sent with PUT (full replace): a missing value clears the field. PATCH would ignore nulls.
        try container.encode(priority, forKey: .priority)
        if let day = dueDate, let year = day.year, let month = day.month, let date = day.day {
            try container.encode(String(format: "%04d-%02d-%02d", year, month, date), forKey: .dueDate)
        } else {
            try container.encodeNil(forKey: .dueDate)
        }
    }
}

extension Calendar {
    /// Liferay stores Date fields as midnight UTC, so read them back in UTC to get the same day.
    public static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}

extension ServiceRequest {
    static let path = "/o/c/servicerequests"

    /// One page of the signed-in user's requests. Liferay only returns entries the user may view,
    /// so no "created by me" filter is needed.
    public static func list(_ query: ListQuery = ListQuery(sort: ["dateCreated:desc"])) -> Endpoint<Page<ServiceRequest>> {
        Endpoint(.get, path, queryItems: query.queryItems)
    }

    public static func get(_ id: Int) -> Endpoint<ServiceRequest> {
        Endpoint(.get, "\(path)/\(id)")
    }

    /// Creates or updates by external reference code. With a code generated once per new form, a
    /// retried request (for example after a dropped connection) can't create a duplicate.
    public static func upsert(_ draft: ServiceRequestDraft, externalReferenceCode: String) throws -> Endpoint<ServiceRequest> {
        let code = externalReferenceCode.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? externalReferenceCode
        return try Endpoint(.put, "\(path)/by-external-reference-code/\(code)", json: draft)
    }

    /// Replaces the user-editable fields. PUT rather than PATCH: Liferay's PATCH ignores `null`,
    /// so clearing the priority or due date would silently do nothing.
    public static func update(_ id: Int, with draft: ServiceRequestDraft) throws -> Endpoint<ServiceRequest> {
        try Endpoint(.put, "\(path)/\(id)", json: draft)
    }

    public static func delete(_ id: Int) -> Endpoint<NoContent> {
        Endpoint(.delete, "\(path)/\(id)")
    }
}

/// The picklist keys created by `liferay/scripts/setup.sh`. The app only ever sends these keys,
/// because Liferay answers an unknown key with `403 Forbidden`.
public enum ServiceRequestPicklists {
    public static let categories: [PicklistValue] = [
        PicklistValue(key: "account", name: "Account"),
        PicklistValue(key: "billing", name: "Billing"),
        PicklistValue(key: "technical", name: "Technical"),
        PicklistValue(key: "other", name: "Other"),
    ]
    public static let statuses: [PicklistValue] = [
        PicklistValue(key: "open", name: "Open"),
        PicklistValue(key: "inProgress", name: "In Progress"),
        PicklistValue(key: "closed", name: "Closed"),
    ]
}
