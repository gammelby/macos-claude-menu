import Foundation

public protocol HTTPTransport: Sendable {
    func get(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func get(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageFetchError.invalidResponse }
        return (data, http)
    }
}

public struct OAuthToken: Sendable {
    public var accessToken: String
    public var expiresAt: Date?

    public init(accessToken: String, expiresAt: Date?) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }
}

public protocol TokenProvider: Sendable {
    func currentToken() throws -> OAuthToken
}

/// Reads Claude Code's OAuth token through `/usr/bin/security`, the same way the statusline does,
/// so the existing Keychain approval applies and rebuilding this app does not trigger a new prompt.
public struct KeychainTokenProvider: TokenProvider {
    public init() {}

    public func currentToken() throws -> OAuthToken {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UsageFetchError.notSignedIn }
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> OAuthToken {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { throw UsageFetchError.notSignedIn }
        let expiresAt = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return OAuthToken(accessToken: token, expiresAt: expiresAt)
    }
}

public enum UsageFetchError: Error, Equatable, Sendable {
    case notSignedIn
    case tokenExpired
    case unauthorized
    case rateLimited
    case http(Int)
    case invalidResponse
    case network(String)

    public var message: String {
        switch self {
        case .notSignedIn: return "Not signed in. Log in with Claude Code."
        case .tokenExpired, .unauthorized: return "Token expired. Open Claude Code to refresh it."
        case .rateLimited: return "Rate limited. Retrying later."
        case .http(let code): return "Usage API returned HTTP \(code)."
        case .invalidResponse: return "Unexpected response from the usage API."
        case .network(let detail): return "Network error: \(detail)"
        }
    }

    /// Errors worth retrying with backoff rather than waiting for the user to sign in again.
    public var isTransient: Bool {
        switch self {
        case .rateLimited, .http, .network, .invalidResponse: return true
        case .notSignedIn, .tokenExpired, .unauthorized: return false
        }
    }
}

/// Fetches plan usage, sharing `~/.claude/.statusline-usage-cache.json` with the statusline script
/// so the two never double the request rate. Never refreshes OAuth tokens itself.
public actor UsageClient {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static var defaultCacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.statusline-usage-cache.json")
    }

    private let cacheURL: URL
    private let cacheTTL: TimeInterval
    private let transport: HTTPTransport
    private let tokens: TokenProvider
    private let now: @Sendable () -> Date

    public init(cacheURL: URL = UsageClient.defaultCacheURL, cacheTTL: TimeInterval = 120,
                transport: HTTPTransport = URLSessionTransport(), tokens: TokenProvider = KeychainTokenProvider(),
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.cacheURL = cacheURL
        self.cacheTTL = cacheTTL
        self.transport = transport
        self.tokens = tokens
        self.now = now
    }

    public func fetch(force: Bool = false) async throws -> (usage: UsageResponse, fetchedAt: Date) {
        if !force, let cached = readFreshCache() { return cached }

        let token = try tokens.currentToken()
        if let expiresAt = token.expiresAt, expiresAt <= now() { throw UsageFetchError.tokenExpired }

        var request = URLRequest(url: Self.endpoint, timeoutInterval: 10)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.get(request)
        } catch let error as UsageFetchError {
            throw error
        } catch {
            throw UsageFetchError.network(error.localizedDescription)
        }

        switch response.statusCode {
        case 200: break
        case 401, 403: throw UsageFetchError.unauthorized
        case 429: throw UsageFetchError.rateLimited
        default: throw UsageFetchError.http(response.statusCode)
        }

        guard let usage = try? UsageResponse.decode(from: data), usage.limits != nil else {
            throw UsageFetchError.invalidResponse
        }
        try? data.write(to: cacheURL, options: .atomic)
        return (usage, now())
    }

    private func readFreshCache() -> (usage: UsageResponse, fetchedAt: Date)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
              let modified = attributes[.modificationDate] as? Date,
              now().timeIntervalSince(modified) < cacheTTL,
              let data = try? Data(contentsOf: cacheURL),
              let usage = try? UsageResponse.decode(from: data), usage.limits != nil
        else { return nil }
        return (usage, modified)
    }
}
