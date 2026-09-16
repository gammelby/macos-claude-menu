import ClaudeMenuCore
import SwiftUI

struct PopoverView: View {
    @Bindable var store: UsageStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(alignment: .leading, spacing: 16) {
                header
                if let error = store.usageError {
                    ErrorBanner(message: error.message, stale: store.usage != nil)
                }
                LimitsSection(limits: store.limits, now: context.date, loading: store.usage == nil && store.usageError == nil)
                if let rows = store.usage?.sevenDayBreakdown?.rows, rows.contains(where: { $0.percent > 0 }) {
                    BreakdownSection(rows: rows)
                }
                LocalUsageSection(summary: store.local)
                if let usage = store.usage {
                    ExtraUsageSection(extra: usage.extraUsage, spend: usage.spend)
                }
                Divider()
                footer(now: context.date)
            }
            .padding(14)
            .frame(width: 320)
        }
    }

    private var header: some View {
        HStack {
            Text("Claude usage").font(.headline)
            Spacer()
            if store.isFetchingUsage || store.isScanningLocal {
                ProgressView().controlSize(.small)
            }
            Button {
                store.refreshAll()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("r")
            .help("Refresh (⌘R)")
        }
    }

    private func footer(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Menubar shows", selection: $store.titleMode) {
                ForEach(TitleMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)

            Toggle("Launch at login", isOn: Binding(
                get: { store.launchAtLogin },
                set: { store.setLaunchAtLogin($0) }
            ))
            if let error = store.loginItemError {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                if let fetched = store.usageFetchedAt {
                    Text("Updated \(Formatting.ago(fetched, from: now))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Usage page") {
                    NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
                }
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .controlSize(.small)
        }
    }
}

// MARK: - Sections

private struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct ErrorBanner: View {
    let message: String
    let stale: Bool

    var body: some View {
        Label {
            Text(stale ? "\(message) Showing last known values." : message)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.caption)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct LimitsSection: View {
    let limits: [UsageLimit]
    let now: Date
    let loading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Plan limits")
            if limits.isEmpty {
                Text(loading ? "Loading…" : "No limit data")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(limits) { limit in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(limit.displayName).font(.callout)
                        Spacer()
                        if limit.severity != .normal {
                            Label(limit.severity == .critical ? "Near limit" : "High",
                                  systemImage: "exclamationmark.triangle.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.caption)
                                .foregroundStyle(severityColor(limit.severity))
                        }
                        Text(Formatting.percent(limit.percent))
                            .font(.callout.monospacedDigit().weight(.semibold))
                    }
                    MeterBar(fraction: limit.percent / 100, color: severityColor(limit.severity))
                    if let reset = limit.resetsAt {
                        Text(reset > now ? "Resets in \(Formatting.countdown(to: reset, from: now))" : "Resetting now")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct BreakdownSection: View {
    let rows: [UsageBreakdown.Row]

    private static let colors: [String: Color] = [
        "claude_code": .indigo, "chat": .teal, "cowork": .mint, "other": .gray,
    ]

    private var visible: [UsageBreakdown.Row] { rows.filter { $0.percent > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "This week by surface")
            GeometryReader { geo in
                let gaps = CGFloat(max(visible.count - 1, 0)) * 2
                let total = max(visible.reduce(0) { $0 + $1.percent }, 1)
                HStack(spacing: 2) {
                    ForEach(visible) { row in
                        Rectangle()
                            .fill(color(row))
                            .frame(width: (geo.size.width - gaps) * row.percent / total)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)

            HStack(spacing: 12) {
                ForEach(visible) { row in
                    HStack(spacing: 4) {
                        Circle().fill(color(row)).frame(width: 7, height: 7)
                        Text("\(row.displayName) \(Formatting.percent(row.percent))")
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        }
    }

    private func color(_ row: UsageBreakdown.Row) -> Color { Self.colors[row.key] ?? .brown }
}

private struct LocalUsageSection: View {
    let summary: LocalUsageSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Claude Code on this Mac")
            if let summary {
                Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .gridColumnAlignment(.leading)
                        Text("Today").foregroundStyle(.secondary)
                        Text("7 days").foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    row("Tokens", summary.today.tokens.total, summary.week.tokens.total, Formatting.tokens)
                    row("Output", summary.today.tokens.output, summary.week.tokens.output, Formatting.tokens)
                    row("Cache hits", summary.today.cacheReadShare, summary.week.cacheReadShare) {
                        Formatting.percent($0 * 100)
                    }
                    row("Requests", summary.today.requests, summary.week.requests) { "\($0)" }
                    row("Est. cost", summary.today.cost, summary.week.cost) { Formatting.dollars($0) }
                }
                .font(.callout.monospacedDigit())

                let top = summary.week.topModels(limit: 3)
                if !top.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(top, id: \.model) { entry in
                            HStack {
                                Text(ModelNames.display(entry.model))
                                Spacer()
                                Text(Formatting.dollars(entry.cost)).monospacedDigit()
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Text(footnote(summary))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Scanning session logs…").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row<T>(_ label: String, _ today: T, _ week: T, _ format: (T) -> String) -> some View {
        GridRow {
            Text(label).gridColumnAlignment(.leading)
            Text(format(today))
            Text(format(week))
        }
    }

    private func footnote(_ summary: LocalUsageSummary) -> String {
        var text = "Cost is an API-list-price estimate, not your bill."
        if summary.week.unpricedTokens > 0 {
            text += " \(Formatting.tokens(summary.week.unpricedTokens)) tokens from unpriced models."
        }
        return text
    }
}

private struct ExtraUsageSection: View {
    let extra: ExtraUsage?
    let spend: Spend?

    private var enabled: Bool { extra?.isEnabled == true || spend?.enabled == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionTitle(text: "Extra usage")
                Spacer()
                if !enabled {
                    Text("Off").font(.callout).foregroundStyle(.secondary)
                }
            }
            if enabled, let used = spend?.used {
                let currency = used.currency ?? "USD"
                HStack {
                    Text(Formatting.dollars(used.amount, currency: currency))
                    if let limit = spend?.limit {
                        Text("of \(Formatting.dollars(limit.amount, currency: currency))").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let percent = spend?.percent {
                        Text(Formatting.percent(percent)).fontWeight(.semibold)
                    }
                }
                .font(.callout.monospacedDigit())
                if let percent = spend?.percent {
                    MeterBar(fraction: percent / 100,
                             color: severityColor(Severity(raw: nil, percent: percent)))
                }
            }
        }
    }
}

// MARK: - Shared pieces

private struct MeterBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color)
                    .frame(width: clamped > 0 ? max(geo.size.width * clamped, 6) : 0)
            }
        }
        .frame(height: 6)
    }
}

private func severityColor(_ severity: Severity) -> Color {
    switch severity {
    case .normal: return .accentColor
    case .warning: return .orange
    case .critical: return .red
    }
}
