import Foundation
@testable import LiferayKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Loads a recorded Liferay response from `Fixtures/` (see `liferay/scripts/record-fixtures.sh`).
func fixture(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
        throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "Fixtures/\(name).json"])
    }
    return try Data(contentsOf: url)
}

/// A fake `HTTPTransport`: answers each request with the next canned response and records what
/// was sent.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int
        var body: Data
        var delay: Duration = .zero
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }

    var sentRequests: [URLRequest] { lock.withLock { requests } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply = lock.withLock {
            requests.append(request)
            return replies.isEmpty ? Reply(status: 500, body: Data("no reply queued".utf8)) : replies.removeFirst()
        }
        if reply.delay > .zero { try await Task.sleep(for: reply.delay) }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (reply.body, response)
    }
}

extension MockTransport.Reply {
    static func json(_ status: Int, fixture name: String) throws -> Self { Self(status: status, body: try fixture(name)) }
    static func json(_ status: Int, _ body: String) -> Self { Self(status: status, body: Data(body.utf8)) }
    static func empty(_ status: Int) -> Self { Self(status: status, body: Data()) }
}

let testConfiguration = LiferayConfiguration(
    baseURL: URL(string: "http://localhost:8080")!,
    clientID: "id-test",
    redirectURI: URL(string: "com.liferay.sample.selfservice://oauth2redirect")!
)

/// A clock the tests can move forward.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { current } }
    func advance(by seconds: TimeInterval) { lock.withLock { current += seconds } }
}

extension URLRequest {
    var formFields: [String: String] {
        let body = String(decoding: httpBody ?? Data(), as: UTF8.self)
        var fields: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
            fields[parts[0]] = parts.count > 1 ? parts[1] : ""
        }
        return fields
    }
}
