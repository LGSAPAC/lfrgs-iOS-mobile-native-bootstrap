import Foundation

/// One page of a Liferay list response: `{"items": [...], "page": 1, "pageSize": 20, "totalCount": 3, "lastPage": 1}`.
public struct Page<Item: Decodable & Sendable>: Decodable, Sendable {
    public var items: [Item]
    /// 1-based.
    public var page: Int
    public var pageSize: Int
    public var totalCount: Int
    public var lastPage: Int

    public var hasNextPage: Bool { page < lastPage }

    public init(items: [Item], page: Int, pageSize: Int, totalCount: Int, lastPage: Int) {
        self.items = items
        self.page = page
        self.pageSize = pageSize
        self.totalCount = totalCount
        self.lastPage = lastPage
    }
}

extension Page: Equatable where Item: Equatable {}
