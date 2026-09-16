import Foundation

public struct TokenCounts: Equatable, Sendable {
    public var input = 0
    public var output = 0
    public var cacheRead = 0
    public var cacheWrite5m = 0
    public var cacheWrite1h = 0

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite5m: Int = 0, cacheWrite1h: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
    }

    public var total: Int { input + output + cacheRead + cacheWrite5m + cacheWrite1h }
    public var cacheWrite: Int { cacheWrite5m + cacheWrite1h }

    public static func += (lhs: inout TokenCounts, rhs: TokenCounts) {
        lhs.input += rhs.input
        lhs.output += rhs.output
        lhs.cacheRead += rhs.cacheRead
        lhs.cacheWrite5m += rhs.cacheWrite5m
        lhs.cacheWrite1h += rhs.cacheWrite1h
    }
}

/// Dollars per million tokens at Anthropic first-party API rates.
public struct ModelPrice: Sendable {
    public var input: Double
    public var output: Double
    public var cacheReadOverride: Double?

    public var cacheRead: Double { cacheReadOverride ?? input * 0.1 }
    public var cacheWrite5m: Double { input * 1.25 }
    public var cacheWrite1h: Double { input * 2 }
}

public enum Pricing {
    /// Ordered so more specific prefixes win (e.g. `claude-opus-4-1` before `claude-opus-4`).
    static let table: [(prefix: String, price: ModelPrice)] = [
        ("claude-fable-5-1", ModelPrice(input: 10, output: 50, cacheReadOverride: 0.25)),
        ("claude-mythos-5-1", ModelPrice(input: 10, output: 50)),
        ("claude-fable-5", ModelPrice(input: 10, output: 50)),
        ("claude-mythos-5", ModelPrice(input: 10, output: 50)),
        ("claude-opus-5", ModelPrice(input: 5, output: 25)),
        ("claude-opus-4-8", ModelPrice(input: 5, output: 25)),
        ("claude-opus-4-7", ModelPrice(input: 5, output: 25)),
        ("claude-opus-4-6", ModelPrice(input: 5, output: 25)),
        ("claude-opus-4-5", ModelPrice(input: 5, output: 25)),
        ("claude-opus-4", ModelPrice(input: 15, output: 75)),
        ("claude-sonnet-5", ModelPrice(input: 2, output: 10)),
        ("claude-sonnet-4", ModelPrice(input: 3, output: 15)),
        ("claude-3-7-sonnet", ModelPrice(input: 3, output: 15)),
        ("claude-haiku-4-5", ModelPrice(input: 1, output: 5)),
        ("claude-3-5-haiku", ModelPrice(input: 0.8, output: 4)),
    ]

    public static func price(for model: String) -> ModelPrice? {
        table.first { model.hasPrefix($0.prefix) }?.price
    }

    public static func cost(_ tokens: TokenCounts, model: String) -> Double? {
        guard let p = price(for: model) else { return nil }
        let perToken = [
            (tokens.input, p.input), (tokens.output, p.output), (tokens.cacheRead, p.cacheRead),
            (tokens.cacheWrite5m, p.cacheWrite5m), (tokens.cacheWrite1h, p.cacheWrite1h),
        ]
        return perToken.reduce(0) { $0 + Double($1.0) * $1.1 } / 1_000_000
    }
}

public enum ModelNames {
    /// `claude-sonnet-4-5-20250929` -> `Sonnet 4.5`. Unrecognized ids are returned unchanged.
    public static func display(_ id: String) -> String {
        guard id.hasPrefix("claude-") else { return id }
        var parts = id.dropFirst("claude-".count).split(separator: "-").map(String.init)
        if let last = parts.last, last.count == 8, Int(last) != nil { parts.removeLast() }
        guard let family = parts.first, Int(family) == nil else { return id }
        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? family.capitalized : "\(family.capitalized) \(version)"
    }
}
