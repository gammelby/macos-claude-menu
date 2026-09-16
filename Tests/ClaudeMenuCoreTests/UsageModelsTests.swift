import Foundation
import Testing
@testable import ClaudeMenuCore

@Suite struct UsageModelsTests {
    func fixture() throws -> UsageResponse {
        let url = try #require(Bundle.module.url(forResource: "usage", withExtension: "json", subdirectory: "Fixtures"))
        return try UsageResponse.decode(from: Data(contentsOf: url))
    }

    @Test func decodesLimits() throws {
        let usage = try fixture()
        let limits = usage.effectiveLimits
        #expect(limits.map(\.kind) == ["session", "weekly_all", "weekly_scoped"])
        #expect(limits[0].percent == 12)
        #expect(limits[0].displayName == "Session")
        #expect(limits[1].displayName == "Weekly")
        #expect(limits[2].displayName == "Weekly · Fable")
        #expect(limits[0].severity == .normal)
        let reset = try #require(limits[1].resetsAt)
        #expect(reset == ISO8601DateFormatter().date(from: "2026-09-19T07:00:00Z")!.addingTimeInterval(0.592027))
    }

    @Test func decodesBreakdownAndExtraUsage() throws {
        let usage = try fixture()
        #expect(usage.sevenDayBreakdown?.rows.map(\.key) == ["claude_code", "chat", "cowork", "other"])
        #expect(usage.sevenDayBreakdown?.rows.first?.percent == 87)
        #expect(usage.extraUsage?.isEnabled == false)
        #expect(usage.spend?.used?.amount == 0)
    }

    @Test func fallsBackToWindowsWhenLimitsMissing() throws {
        let json = """
        {"five_hour": {"utilization": 42.0, "resets_at": "2026-09-16T10:00:00+00:00"},
         "seven_day": {"utilization": 80.0, "resets_at": null}}
        """
        let usage = try UsageResponse.decode(from: Data(json.utf8))
        let limits = usage.effectiveLimits
        #expect(limits.map(\.kind) == ["session", "weekly_all"])
        #expect(limits.map(\.percent) == [42, 80])
        #expect(limits[1].severity == .warning)
    }

    @Test func severityFromRawOrPercent() {
        #expect(Severity(raw: "normal", percent: 95) == .critical)
        #expect(Severity(raw: "critical", percent: 10) == .critical)
        #expect(Severity(raw: "warning", percent: 10) == .warning)
        #expect(Severity(raw: nil, percent: 50) == .normal)
        #expect(Severity(raw: "mystery", percent: 76) == .warning)
    }

    @Test func moneyUsesExponent() {
        let money = Money(amountMinor: 1234, currency: "USD", exponent: 2)
        #expect(money.amount == 12.34)
    }
}
