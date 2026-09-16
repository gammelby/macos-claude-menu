import Foundation
import Testing
@testable import ClaudeMenuCore

final class StubTransport: HTTPTransport, @unchecked Sendable {
    var status = 200
    var body = Data()
    var requests: [URLRequest] = []

    func get(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }
}

struct StubTokens: TokenProvider {
    var token: OAuthToken?
    func currentToken() throws -> OAuthToken {
        guard let token else { throw UsageFetchError.notSignedIn }
        return token
    }
}

@Suite struct UsageClientTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("client-\(UUID().uuidString)")
    var cacheURL: URL { dir.appendingPathComponent("cache.json") }
    let now = Date()
    let validBody = Data(#"{"limits":[{"kind":"session","percent":33,"severity":"normal","resets_at":null}]}"#.utf8)

    init() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func client(_ transport: StubTransport, token: OAuthToken? = OAuthToken(accessToken: "secret", expiresAt: .distantFuture)) -> UsageClient {
        UsageClient(cacheURL: cacheURL, transport: transport, tokens: StubTokens(token: token), now: { now })
    }

    func writeCache(_ data: Data, age: TimeInterval) throws {
        try data.write(to: cacheURL)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: cacheURL.path)
    }

    @Test func freshCacheSkipsNetwork() async throws {
        try writeCache(validBody, age: 30)
        let transport = StubTransport()
        let result = try await client(transport).fetch()
        #expect(result.usage.effectiveLimits.first?.percent == 33)
        #expect(transport.requests.isEmpty)
    }

    @Test func staleCacheFetchesAndWritesCache() async throws {
        try writeCache(validBody, age: 600)
        let transport = StubTransport()
        transport.body = Data(#"{"limits":[{"kind":"session","percent":44}]}"#.utf8)
        let result = try await client(transport).fetch()
        #expect(result.usage.effectiveLimits.first?.percent == 44)
        let request = try #require(transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(try Data(contentsOf: cacheURL) == transport.body)
    }

    @Test func forceIgnoresFreshCache() async throws {
        try writeCache(validBody, age: 10)
        let transport = StubTransport()
        transport.body = validBody
        _ = try await client(transport).fetch(force: true)
        #expect(transport.requests.count == 1)
    }

    @Test func emptyCacheFileIsIgnored() async throws {
        try writeCache(Data(), age: 5)
        let transport = StubTransport()
        transport.body = validBody
        _ = try await client(transport).fetch()
        #expect(transport.requests.count == 1)
    }

    @Test func mapsHTTPErrors() async throws {
        let transport = StubTransport()
        transport.status = 401
        await #expect(throws: UsageFetchError.unauthorized) { try await client(transport).fetch() }
        transport.status = 429
        await #expect(throws: UsageFetchError.rateLimited) { try await client(transport).fetch() }
        transport.status = 503
        await #expect(throws: UsageFetchError.http(503)) { try await client(transport).fetch() }
    }

    @Test func invalidBodyDoesNotOverwriteCache() async throws {
        try writeCache(validBody, age: 600)
        let transport = StubTransport()
        transport.body = Data(#"{"error":"nope"}"#.utf8)
        await #expect(throws: UsageFetchError.invalidResponse) { try await client(transport).fetch() }
        #expect(try Data(contentsOf: cacheURL) == validBody)
    }

    @Test func expiredTokenDoesNotHitNetwork() async throws {
        let transport = StubTransport()
        let expired = OAuthToken(accessToken: "old", expiresAt: now.addingTimeInterval(-1))
        await #expect(throws: UsageFetchError.tokenExpired) { try await client(transport, token: expired).fetch() }
        #expect(transport.requests.isEmpty)
    }

    @Test func parsesKeychainCredentialJSON() throws {
        let json = Data(#"{"claudeAiOauth":{"accessToken":"abc","expiresAt":1789580038735}}"#.utf8)
        let token = try KeychainTokenProvider.parse(json)
        #expect(token.accessToken == "abc")
        #expect(token.expiresAt == Date(timeIntervalSince1970: 1789580038.735))
    }
}
