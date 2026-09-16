import Testing
@testable import ClaudeMenuCore

@Suite struct PricingTests {
    @Test func matchesModelsByPrefix() {
        #expect(Pricing.price(for: "claude-opus-5")?.input == 5)
        #expect(Pricing.price(for: "claude-fable-5-1")?.output == 50)
        #expect(Pricing.price(for: "claude-sonnet-4-5-20250929")?.input == 3)
        #expect(Pricing.price(for: "claude-opus-4-1-20250805")?.input == 15)
        #expect(Pricing.price(for: "claude-opus-4-6")?.input == 5)
        #expect(Pricing.price(for: "claude-haiku-4-5-20251001")?.output == 5)
        #expect(Pricing.price(for: "gpt-5") == nil)
    }

    @Test func costAppliesCacheMultipliers() throws {
        let tokens = TokenCounts(input: 1_000_000, output: 1_000_000, cacheRead: 1_000_000,
                                 cacheWrite5m: 1_000_000, cacheWrite1h: 1_000_000)
        // Opus 5: 5 + 25 + 0.5 + 6.25 + 10
        let cost = try #require(Pricing.cost(tokens, model: "claude-opus-5"))
        #expect(abs(cost - 46.75) < 1e-9)
    }

    @Test func fable51CacheReadOverride() throws {
        let tokens = TokenCounts(cacheRead: 1_000_000)
        let cost = try #require(Pricing.cost(tokens, model: "claude-fable-5-1"))
        #expect(abs(cost - 0.25) < 1e-9)
    }

    @Test func unknownModelHasNoCost() {
        #expect(Pricing.cost(TokenCounts(input: 10), model: "mystery") == nil)
    }

    @Test func displayNames() {
        #expect(ModelNames.display("claude-opus-5") == "Opus 5")
        #expect(ModelNames.display("claude-fable-5-1") == "Fable 5.1")
        #expect(ModelNames.display("claude-sonnet-4-5-20250929") == "Sonnet 4.5")
        #expect(ModelNames.display("something-else") == "something-else")
    }
}
