import Foundation

public enum TitleMode: String, CaseIterable, Identifiable, Sendable {
    case allLimits, highestLimit, iconOnly

    /// Restores a persisted mode; unknown values (such as the retired `compactPair`) fall back to the default.
    public init(storedValue: String?) {
        self = storedValue.flatMap(TitleMode.init(rawValue:)) ?? .allLimits
    }

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .allLimits: return "All limits"
        case .highestLimit: return "Highest limit"
        case .iconOnly: return "Icon only"
        }
    }
}

public enum TitleContent: Equatable, Sendable {
    case placeholder
    /// Drawn in the plain menubar text color. Colored digits are hard to read against the
    /// translucent menubar, so a leading emoji carries the severity instead.
    case text(String)
    case icon(symbol: String, severity: Severity)
}

public enum TitleFormatter {
    public static func content(mode: TitleMode, limits: [UsageLimit]) -> TitleContent {
        guard let highest = limits.max(by: { $0.percent < $1.percent }) else { return .placeholder }
        switch mode {
        case .allLimits:
            // Thin spaces give the pipes a little air without widening the item much.
            let percentages = limits.map { Formatting.percent($0.percent) }.joined(separator: "\u{2009}|\u{2009}")
            return .text(prefix(worst(limits)) + percentages)
        case .highestLimit:
            return .text(prefix(worst(limits)) + Formatting.percent(highest.percent))
        case .iconOnly:
            return .icon(symbol: gaugeSymbol(percent: highest.percent), severity: worst(limits))
        }
    }

    static func worst(_ limits: [UsageLimit]) -> Severity {
        limits.map(\.severity).max() ?? .normal
    }

    static func prefix(_ severity: Severity) -> String {
        switch severity {
        case .normal: return ""
        case .warning: return "⚠️ "
        case .critical: return "🚨 "
        }
    }

    static func gaugeSymbol(percent: Double) -> String {
        let step: String
        switch percent {
        case ..<17: step = "0"
        case ..<42: step = "33"
        case ..<59: step = "50"
        case ..<84: step = "67"
        default: step = "100"
        }
        return "gauge.with.dots.needle.\(step)percent"
    }
}
