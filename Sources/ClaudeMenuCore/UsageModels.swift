import Foundation

/// Response of `GET https://api.anthropic.com/api/oauth/usage`, the endpoint behind `/usage`.
/// Only the fields the menu shows are decoded; everything is optional because the payload evolves.
public struct UsageResponse: Decodable, Sendable {
    public var fiveHour: UsageWindow?
    public var sevenDay: UsageWindow?
    public var limits: [UsageLimit]?
    public var sevenDayBreakdown: UsageBreakdown?
    public var extraUsage: ExtraUsage?
    public var spend: Spend?

    public static func decode(from data: Data) throws -> UsageResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleContainer()
            let string = try container.decode(String.self)
            guard let date = DateParsing.iso8601(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date \(string)")
            }
            return date
        }
        return try decoder.decode(UsageResponse.self, from: data)
    }

    /// `limits` when present, otherwise session and weekly limits built from the legacy window fields.
    public var effectiveLimits: [UsageLimit] {
        if let limits, !limits.isEmpty { return limits }
        var result: [UsageLimit] = []
        if let w = fiveHour, let u = w.utilization {
            result.append(UsageLimit(kind: "session", percent: u, severityRaw: nil, resetsAt: w.resetsAt, scopeModelName: nil))
        }
        if let w = sevenDay, let u = w.utilization {
            result.append(UsageLimit(kind: "weekly_all", percent: u, severityRaw: nil, resetsAt: w.resetsAt, scopeModelName: nil))
        }
        return result
    }
}

private extension Decoder {
    func singleContainer() throws -> SingleValueDecodingContainer { try singleValueContainer() }
}

public struct UsageWindow: Decodable, Sendable {
    public var utilization: Double?
    public var resetsAt: Date?
}

public enum Severity: Int, Comparable, Sendable {
    case normal, warning, critical

    /// Uses the server's severity but never reports less than the percentage implies.
    public init(raw: String?, percent: Double) {
        let fromPercent: Severity = percent >= 90 ? .critical : percent >= 75 ? .warning : .normal
        let fromRaw: Severity
        switch raw?.lowercased() {
        case "warning", "warn", "approaching", "elevated": fromRaw = .warning
        case "critical", "exceeded", "limited", "blocked", "error": fromRaw = .critical
        default: fromRaw = .normal
        }
        self = max(fromPercent, fromRaw)
    }

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct UsageLimit: Decodable, Sendable, Identifiable {
    public var kind: String
    public var percent: Double
    public var severityRaw: String?
    public var resetsAt: Date?
    public var scopeModelName: String?

    public var id: String { kind + (scopeModelName ?? "") }
    public var severity: Severity { Severity(raw: severityRaw, percent: percent) }

    public var displayName: String {
        switch kind {
        case "session": return "Session"
        case "weekly_all": return "Weekly"
        case "weekly_scoped": return scopeModelName.map { "Weekly · \($0)" } ?? "Weekly (scoped)"
        default: return kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    public init(kind: String, percent: Double, severityRaw: String?, resetsAt: Date?, scopeModelName: String?) {
        self.kind = kind
        self.percent = percent
        self.severityRaw = severityRaw
        self.resetsAt = resetsAt
        self.scopeModelName = scopeModelName
    }

    private enum CodingKeys: String, CodingKey { case kind, percent, severity, resetsAt, scope }
    private struct Scope: Decodable {
        struct Model: Decodable { var displayName: String? }
        var model: Model?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        percent = try c.decodeIfPresent(Double.self, forKey: .percent) ?? 0
        severityRaw = try c.decodeIfPresent(String.self, forKey: .severity)
        resetsAt = try c.decodeIfPresent(Date.self, forKey: .resetsAt)
        scopeModelName = try c.decodeIfPresent(Scope.self, forKey: .scope)?.model?.displayName
    }
}

public struct UsageBreakdown: Decodable, Sendable {
    public struct Row: Decodable, Sendable, Identifiable {
        public var key: String
        public var displayName: String
        public var percent: Double
        public var id: String { key }
    }
    public var rows: [Row]
}

public struct ExtraUsage: Decodable, Sendable {
    public var isEnabled: Bool?
}

public struct Money: Decodable, Sendable, Equatable {
    public var amountMinor: Int
    public var currency: String?
    public var exponent: Int?

    public init(amountMinor: Int, currency: String?, exponent: Int?) {
        self.amountMinor = amountMinor
        self.currency = currency
        self.exponent = exponent
    }

    public var amount: Double { Double(amountMinor) / pow(10, Double(exponent ?? 2)) }
}

public struct Spend: Decodable, Sendable {
    public var used: Money?
    public var limit: Money?
    public var percent: Double?
    public var enabled: Bool?
}

enum DateParsing {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()
    private static let lock = NSLock()

    /// Parses ISO 8601 with any number of fractional digits (the usage API sends microseconds).
    static func iso8601(_ string: String) -> Date? {
        var base = string
        var fraction = 0.0
        if let dot = string.firstIndex(of: "."),
           let end = string[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            fraction = Double("0" + string[dot..<end]) ?? 0
            base = String(string[..<dot] + string[end...])
        }
        lock.lock()
        defer { lock.unlock() }
        guard let date = plain.date(from: base) ?? withFraction.date(from: string) else { return nil }
        return date.addingTimeInterval(fraction)
    }
}
