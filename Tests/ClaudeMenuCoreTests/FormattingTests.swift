import Foundation
import Testing
@testable import ClaudeMenuCore

@Suite struct FormattingTests {
    @Test func tokens() {
        #expect(Formatting.tokens(950) == "950")
        #expect(Formatting.tokens(87_342) == "87k")
        #expect(Formatting.tokens(1_000_000) == "1M")
        #expect(Formatting.tokens(1_250_000) == "1.3M")
        #expect(Formatting.tokens(2_400_000_000) == "2.4B")
    }

    @Test func dollars() {
        #expect(Formatting.dollars(12.345) == "$12.35")
        #expect(Formatting.dollars(1234.5) == "$1,235")
    }

    @Test func countdown() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(Formatting.countdown(to: now.addingTimeInterval(2 * 3600 + 14 * 60 + 5), from: now) == "2h 14m")
        #expect(Formatting.countdown(to: now.addingTimeInterval(3 * 86400 + 4 * 3600), from: now) == "3d 4h")
        #expect(Formatting.countdown(to: now.addingTimeInterval(12 * 60), from: now) == "12m")
        #expect(Formatting.countdown(to: now.addingTimeInterval(-5), from: now) == "now")
    }

    @Test func ago() {
        let now = Date(timeIntervalSince1970: 1000)
        #expect(Formatting.ago(now.addingTimeInterval(-40), from: now) == "40s ago")
        #expect(Formatting.ago(now.addingTimeInterval(-600), from: now) == "10m ago")
    }
}

@Suite struct TitleFormatterTests {
    func limit(_ kind: String, _ percent: Double, severity: String = "normal", model: String? = nil) -> UsageLimit {
        UsageLimit(kind: kind, percent: percent, severityRaw: severity, resetsAt: nil, scopeModelName: model)
    }

    var limits: [UsageLimit] {
        [limit("session", 11), limit("weekly_all", 18), limit("weekly_scoped", 91, severity: "normal", model: "Fable")]
    }

    @Test func allLimitsInDropdownOrder() {
        let calm = [limit("session", 11), limit("weekly_all", 18)]
        #expect(TitleFormatter.content(mode: .allLimits, limits: calm)
                == .text("11%\u{2009}|\u{2009}18%"))
    }

    @Test func allLimitsWithSingleLimit() {
        #expect(TitleFormatter.content(mode: .allLimits, limits: [limit("session", 5)]) == .text("5%"))
    }

    @Test func warningSignPrefixesTheWorstLimit() {
        let warning = [limit("session", 11), limit("weekly_all", 80)]
        #expect(TitleFormatter.content(mode: .allLimits, limits: warning)
                == .text("⚠️ 11%\u{2009}|\u{2009}80%"))
        // Severity reported by the server counts even when the percentage looks calm.
        let flagged = [limit("session", 11, severity: "warning")]
        #expect(TitleFormatter.content(mode: .allLimits, limits: flagged) == .text("⚠️ 11%"))
    }

    @Test func alarmPrefixesACriticalLimit() {
        #expect(TitleFormatter.content(mode: .allLimits, limits: limits)
                == .text("🚨 11%\u{2009}|\u{2009}18%\u{2009}|\u{2009}91%"))
        #expect(TitleFormatter.content(mode: .highestLimit, limits: limits) == .text("🚨 91%"))
    }

    @Test func unknownStoredModeFallsBackToAllLimits() {
        #expect(TitleMode(storedValue: "compactPair") == .allLimits)
        #expect(TitleMode(storedValue: nil) == .allLimits)
        #expect(TitleMode(storedValue: "iconOnly") == .iconOnly)
    }

    @Test func highestLimit() {
        #expect(TitleFormatter.content(mode: .highestLimit, limits: [limit("session", 11), limit("weekly_all", 18)])
                == .text("18%"))
    }

    @Test func iconOnlyUsesWorstSeverity() {
        let mixed = [limit("session", 10), limit("weekly_all", 60, severity: "warning")]
        #expect(TitleFormatter.content(mode: .iconOnly, limits: mixed)
                == .icon(symbol: "gauge.with.dots.needle.67percent", severity: .warning))
        #expect(TitleFormatter.content(mode: .iconOnly, limits: limits)
                == .icon(symbol: "gauge.with.dots.needle.100percent", severity: .critical))
        #expect(TitleFormatter.content(mode: .iconOnly, limits: [limit("session", 40)])
                == .icon(symbol: "gauge.with.dots.needle.33percent", severity: .normal))
    }

    @Test func placeholderWithoutData() {
        for mode in TitleMode.allCases {
            #expect(TitleFormatter.content(mode: mode, limits: []) == .placeholder)
        }
    }
}
