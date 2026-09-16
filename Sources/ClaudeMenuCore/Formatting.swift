import Foundation

public enum Formatting {
    public static func tokens(_ n: Int) -> String {
        func scaled(_ divisor: Double, _ suffix: String) -> String {
            let v = Double(n) / divisor
            let rounded = (v * 10).rounded() / 10
            return rounded == rounded.rounded() ? "\(Int(rounded))\(suffix)" : String(format: "%.1f%@", rounded, suffix)
        }
        switch n {
        case 1_000_000_000...: return scaled(1_000_000_000, "B")
        case 1_000_000...: return scaled(1_000_000, "M")
        case 1_000...: return "\(n / 1000)k"
        default: return "\(n)"
        }
    }

    public static func dollars(_ amount: Double, currency: String = "USD") -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.locale = Locale(identifier: "en_US")
        f.roundingMode = .halfUp
        f.maximumFractionDigits = amount >= 1000 ? 0 : 2
        f.minimumFractionDigits = amount >= 1000 ? 0 : 2
        return f.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }

    public static func countdown(to date: Date, from now: Date = Date()) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return "now" }
        let days = seconds / 86400, hours = seconds % 86400 / 3600, minutes = seconds % 3600 / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(minutes, 1))m"
    }

    public static func ago(_ date: Date, from now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }

    public static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }
}
