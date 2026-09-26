import Foundation
import Testing

@testable import TelemetryKit

/// The menu bar panel's five `claude.*` signals, from the same readings the console reads.
@Suite struct ClaudeSummaryTests {

    let moment = Date(timeIntervalSince1970: 1_800_000_000)

    func reading(_ key: SessionKey, _ field: Field, _ value: Value) -> Reading {
        Reading(.session(key), field, value, at: moment, ttl: 6)
    }

    func roster(_ keys: [SessionKey]) -> Reading {
        Reading(.machine, .roster, .keys(keys), at: moment, ttl: 6)
    }

    func line(_ id: String, in lines: [ClaudeSummary.Line]) -> ClaudeSummary.Line? {
        lines.first { $0.id == id }
    }

    @Test func aWorkingSessionIsTheOneReportedOn() throws {
        let lines = ClaudeSummary.lines(from: [
            roster(["old", "busy"]),
            reading("old", .status, .text("idle")),
            reading("old", .startedAt, .time(moment)),
            reading("old", .costUSD, .amount(1)),
            reading("busy", .status, .text("busy")),
            reading("busy", .name, .text("familyhub-3")),
            reading("busy", .startedAt, .time(moment.addingTimeInterval(-3600))),
            reading("busy", .contextUsed, .count(800_000)),
            reading("busy", .contextWindow, .count(1_000_000)),
            reading("busy", .costUSD, .amount(42.17)),
            reading("busy", .outputTokens, .count(391_400)),
            reading("busy", .inputTokens, .count(48_210)),
        ])

        #expect(line("claude.sessions", in: lines)?.text == "1 of 2 working")
        #expect(line("claude.busy", in: lines)?.text == "familyhub-3")
        let context = try #require(line("claude.context", in: lines))
        #expect(abs((context.fraction ?? 0) - 0.2) < 1e-9)
        #expect(context.text == "200K left")
        // Room left, not room used: nearly full raises the lamp.
        #expect(context.active)
        #expect(line("claude.cost", in: lines)?.text == "$42.17")
        #expect(line("claude.tokens", in: lines)?.text == "391K out · 48K in")
    }

    @Test func withNobodyWorkingTheNewestSessionIsReportedOn() {
        let lines = ClaudeSummary.lines(from: [
            roster(["a", "b"]),
            reading("a", .startedAt, .time(moment.addingTimeInterval(-60))),
            reading("a", .costUSD, .amount(1)),
            reading("b", .startedAt, .time(moment)),
            reading("b", .costUSD, .amount(2)),
        ])
        #expect(line("claude.cost", in: lines)?.text == "$2.00")
        #expect(line("claude.sessions", in: lines)?.text == "2 idle")
        #expect(line("claude.busy", in: lines)?.active == false)
    }

    /// A failed `claude agents` run sends no roster: say nothing, and let the signals expire.
    @Test func noRosterSaysNothing() {
        #expect(ClaudeSummary.lines(from: [reading("a", .costUSD, .amount(1))]).isEmpty)
        #expect(
            line("claude.sessions", in: ClaudeSummary.lines(from: [roster([])]))?.text
                == "None running")
    }

    @Test func countsAreCompact() {
        #expect(ClaudeSummary.compact(999) == "999")
        #expect(ClaudeSummary.compact(61_000) == "61K")
        #expect(ClaudeSummary.compact(1_234_567) == "1.2M")
        #expect(ClaudeSummary.compact(12_600_000) == "13M")
    }
}
