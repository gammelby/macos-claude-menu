import Foundation

public struct UsageRecord: Sendable {
    public var timestamp: Date
    public var model: String
    public var tokens: TokenCounts
}

public struct UsageAggregate: Sendable {
    public var tokens = TokenCounts()
    public var requests = 0
    public var cost = 0.0
    public var unpricedTokens = 0
    public var costByModel: [String: Double] = [:]

    public init() {}

    mutating func add(_ record: UsageRecord) {
        tokens += record.tokens
        requests += 1
        if let c = Pricing.cost(record.tokens, model: record.model) {
            cost += c
            costByModel[record.model, default: 0] += c
        } else {
            unpricedTokens += record.tokens.total
        }
    }

    public func topModels(limit: Int) -> [(model: String, cost: Double)] {
        costByModel.sorted { $0.value > $1.value }.prefix(limit).map { ($0.key, $0.value) }
    }

    /// Share of input-side tokens served from the prompt cache.
    public var cacheReadShare: Double {
        let inputSide = tokens.input + tokens.cacheRead + tokens.cacheWrite
        return inputSide == 0 ? 0 : Double(tokens.cacheRead) / Double(inputSide)
    }
}

public struct LocalUsageSummary: Sendable {
    public var today: UsageAggregate
    public var week: UsageAggregate
}

/// Incrementally reads Claude Code session logs (`~/.claude/projects/**/*.jsonl`) and keeps one
/// usage record per API response. Not thread-safe: call it from a single serial queue.
public final class SessionLogScanner: @unchecked Sendable {
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }

    private let root: URL
    private let retention: TimeInterval
    private var offsets: [String: UInt64] = [:]
    private var records: [String: UsageRecord] = [:]
    private static let usageMarker = Data("\"usage\"".utf8)

    public init(root: URL = SessionLogScanner.defaultRoot, retention: TimeInterval = 7 * 86400) {
        self.root = root
        self.retention = retention
    }

    public func scan(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-retention)
        let fileCutoff = cutoff.addingTimeInterval(-86400)
        var seen = Set<String>()
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate, modified >= fileCutoff
            else { continue }
            seen.insert(url.path)
            readAppended(url: url, size: UInt64(values.fileSize ?? 0), cutoff: cutoff)
        }
        offsets = offsets.filter { seen.contains($0.key) }
        records = records.filter { $0.value.timestamp >= cutoff }
    }

    public func summary(now: Date = Date(), calendar: Calendar = .current) -> LocalUsageSummary {
        let startOfDay = calendar.startOfDay(for: now)
        let weekStart = now.addingTimeInterval(-retention)
        var today = UsageAggregate()
        var week = UsageAggregate()
        for record in records.values where record.timestamp >= weekStart {
            week.add(record)
            if record.timestamp >= startOfDay { today.add(record) }
        }
        return LocalUsageSummary(today: today, week: week)
    }

    private func readAppended(url: URL, size: UInt64, cutoff: Date) {
        var offset = offsets[url.path] ?? 0
        if size < offset { offset = 0 }
        guard size > offset, let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty,
              let lastNewline = data.lastIndex(of: 0x0A)
        else { return }

        var lineStart = data.startIndex
        while lineStart <= lastNewline {
            let lineEnd = data[lineStart...lastNewline].firstIndex(of: 0x0A)!
            let line = data[lineStart..<lineEnd]
            if line.range(of: Self.usageMarker) != nil { ingest(line, cutoff: cutoff) }
            lineStart = lineEnd + 1
        }
        offsets[url.path] = offset + UInt64(lastNewline - data.startIndex + 1)
    }

    private func ingest(_ line: Data, cutoff: Date) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let messageID = message["id"] as? String,
              let model = message["model"] as? String, model != "<synthetic>",
              let stamp = object["timestamp"] as? String,
              let timestamp = DateParsing.iso8601(stamp), timestamp >= cutoff
        else { return }

        let key = messageID + "|" + ((object["requestId"] as? String) ?? "")
        guard records[key] == nil else { return }

        func int(_ dict: [String: Any]?, _ name: String) -> Int { (dict?[name] as? NSNumber)?.intValue ?? 0 }
        var tokens = TokenCounts(input: int(usage, "input_tokens"), output: int(usage, "output_tokens"),
                                 cacheRead: int(usage, "cache_read_input_tokens"))
        if let creation = usage["cache_creation"] as? [String: Any] {
            tokens.cacheWrite5m = int(creation, "ephemeral_5m_input_tokens")
            tokens.cacheWrite1h = int(creation, "ephemeral_1h_input_tokens")
        } else {
            tokens.cacheWrite5m = int(usage, "cache_creation_input_tokens")
        }
        records[key] = UsageRecord(timestamp: timestamp, model: model, tokens: tokens)
    }
}
