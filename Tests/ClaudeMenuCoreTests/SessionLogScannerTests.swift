import Foundation
import Testing
@testable import ClaudeMenuCore

@Suite struct SessionLogScannerTests {
    let root: URL
    let now = ISO8601DateFormatter().date(from: "2026-09-16T12:00:00Z")!
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scanner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("proj/sess/subagents"),
                                                withIntermediateDirectories: true)
    }

    func line(id: String, req: String = "r", ts: String, model: String = "claude-opus-5",
              input: Int = 0, output: Int = 0, read: Int = 0, write1h: Int = 0) -> String {
        """
        {"type":"assistant","timestamp":"\(ts)","requestId":"\(req)","message":{"id":"\(id)","model":"\(model)","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_read_input_tokens":\(read),"cache_creation_input_tokens":\(write1h),"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":\(write1h)}}}}
        """ + "\n"
    }

    func write(_ text: String, to name: String, append: Bool = false) throws {
        let url = root.appendingPathComponent(name)
        if append, let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try handle.close()
        } else {
            try Data(text.utf8).write(to: url)
        }
    }

    @Test func deduplicatesRepeatedMessages() throws {
        let l = line(id: "m1", ts: "2026-09-16T09:00:00.000Z", input: 10, output: 100)
        try write(l + l + l + "{\"type\":\"user\"}\n", to: "proj/a.jsonl")
        let scanner = SessionLogScanner(root: root)
        scanner.scan(now: now)
        let summary = scanner.summary(now: now, calendar: calendar)
        #expect(summary.today.requests == 1)
        #expect(summary.today.tokens.output == 100)
    }

    @Test func picksUpAppendedLinesAndSubagents() throws {
        try write(line(id: "m1", ts: "2026-09-16T09:00:00.000Z", output: 1), to: "proj/a.jsonl")
        try write(line(id: "s1", ts: "2026-09-16T09:00:00.000Z", output: 2), to: "proj/sess/subagents/agent.jsonl")
        let scanner = SessionLogScanner(root: root)
        scanner.scan(now: now)
        #expect(scanner.summary(now: now, calendar: calendar).today.tokens.output == 3)

        // A partial trailing line is not consumed until it is complete.
        let next = line(id: "m2", ts: "2026-09-16T10:00:00.000Z", output: 4)
        try write(String(next.prefix(40)), to: "proj/a.jsonl", append: true)
        scanner.scan(now: now)
        #expect(scanner.summary(now: now, calendar: calendar).today.tokens.output == 3)
        try write(String(next.dropFirst(40)), to: "proj/a.jsonl", append: true)
        scanner.scan(now: now)
        #expect(scanner.summary(now: now, calendar: calendar).today.tokens.output == 7)
    }

    @Test func resetsOffsetWhenFileShrinks() throws {
        try write(line(id: "m1", ts: "2026-09-16T09:00:00.000Z", output: 1)
                  + line(id: "m2", ts: "2026-09-16T09:00:00.000Z", output: 1), to: "proj/a.jsonl")
        let scanner = SessionLogScanner(root: root)
        scanner.scan(now: now)
        try write(line(id: "m3", ts: "2026-09-16T09:30:00.000Z", output: 5), to: "proj/a.jsonl")
        scanner.scan(now: now)
        #expect(scanner.summary(now: now, calendar: calendar).today.tokens.output == 7)
    }

    @Test func splitsTodayAndWeekAndDropsOld() throws {
        try write(line(id: "today", ts: "2026-09-16T01:00:00.000Z", output: 1)
                  + line(id: "yesterday", ts: "2026-09-15T23:00:00.000Z", output: 10)
                  + line(id: "old", ts: "2026-09-01T00:00:00.000Z", output: 100), to: "proj/a.jsonl")
        let scanner = SessionLogScanner(root: root)
        scanner.scan(now: now)
        let summary = scanner.summary(now: now, calendar: calendar)
        #expect(summary.today.tokens.output == 1)
        #expect(summary.week.tokens.output == 11)
        #expect(summary.week.requests == 2)
    }

    @Test func aggregatesCostPerModel() throws {
        try write(line(id: "a", ts: "2026-09-16T01:00:00.000Z", model: "claude-opus-5", output: 1_000_000)
                  + line(id: "b", ts: "2026-09-16T01:00:00.000Z", model: "claude-haiku-4-5", output: 1_000_000)
                  + line(id: "c", ts: "2026-09-16T01:00:00.000Z", model: "mystery", output: 7), to: "proj/a.jsonl")
        let scanner = SessionLogScanner(root: root)
        scanner.scan(now: now)
        let week = scanner.summary(now: now, calendar: calendar).week
        #expect(abs(week.cost - 30) < 1e-9)
        #expect(week.costByModel["claude-opus-5"] == 25)
        #expect(week.unpricedTokens == 7)
        #expect(week.topModels(limit: 1).map(\.model) == ["claude-opus-5"])
    }
}
