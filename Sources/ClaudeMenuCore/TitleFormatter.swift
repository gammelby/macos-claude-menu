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

public struct TitleSegment: Equatable, Sendable {
    public var text: String
    /// `nil` for separators, which use the plain menubar text color (full opacity so they stay visible on the translucent menubar).
    public var severity: Severity?

    public init(_ text: String, _ severity: Severity?) {
        self.text = text
        self.severity = severity
    }
}

public enum TitleContent: Equatable, Sendable {
    case placeholder
    case text([TitleSegment])
    case icon(symbol: String, severity: Severity)
}

public enum TitleFormatter {
    public static func content(mode: TitleMode, limits: [UsageLimit]) -> TitleContent {
        guard let highest = limits.max(by: { $0.percent < $1.percent }) else { return .placeholder }
        switch mode {
        case .allLimits:
            var segments: [TitleSegment] = []
            for (i, limit) in limits.enumerated() {
                // Thin spaces give the pipes a little air without widening the item much.
                if i > 0 { segments.append(TitleSegment("\u{2009}|\u{2009}", nil)) }
                segments.append(segment(limit))
            }
            return .text(segments)
        case .highestLimit:
            return .text([segment(highest)])
        case .iconOnly:
            let worst = limits.map(\.severity).max() ?? .normal
            return .icon(symbol: gaugeSymbol(percent: highest.percent), severity: worst)
        }
    }

    static func segment(_ limit: UsageLimit) -> TitleSegment {
        TitleSegment(Formatting.percent(limit.percent), limit.severity)
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
