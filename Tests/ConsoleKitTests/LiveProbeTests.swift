#if !APP_STORE

import Foundation
import Testing

@testable import ConsoleKit
@testable import TelemetryKit

/// Reads this Mac's real `~/.claude` into the console and prints the desk.
///
/// Off unless asked for, because it depends on what is running here:
///
///     PK4_LIVE=1 swift test --filter LiveProbe
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PK4_LIVE"] == "1"))
struct LiveProbeTests {

    @Test func theRealClaudeCodeOnThisMac() {
        // Real clock time: the sessions' start times are real.
        let bench = Bench(start: Date())
        let collector = ClaudeCodeCollector()

        let started = Date()
        let batch = collector.collect(at: bench.now)
        let seconds = Date().timeIntervalSince(started)
        bench.feed(batch.readings)
        batch.issues.forEach(bench.model.report)
        let again = Date()
        _ = collector.collect(at: bench.now.addingTimeInterval(2))
        let repeatSeconds = Date().timeIntervalSince(again)

        print(
            "first pass \(String(format: "%.2f", seconds)) s, next \(String(format: "%.3f", repeatSeconds)) s, \(batch.readings.count) readings"
        )
        batch.issues.forEach { print("ISSUE", $0.source, $0.message) }
        for slot in PK4.slots {
            let key = bench.model.slots.key(in: slot)?.rawValue.prefix(8) ?? "--------"
            let row = AnnunciatorRow.allCases.map { row in
                bench.lamp(row, slot) == .off ? "." : String(row.rawValue.prefix(1)).uppercased()
            }.joined()
            print("S\(slot) \(key) \(row) pencil=\(bench.snap.pencil(slot: slot))")
        }
        let snap = bench.snap
        print(
            "running", snap.nixie(PK4.sessionsRunning), "busy", snap.nixie(PK4.sessionsBusy),
            "build", snap.programBuild ?? "-")
        for slot in PK4.slots where bench.model.slots.key(in: slot) != nil {
            bench.send(.selectorGoTo(slot))
            bench.run(for: 1)
            let s = bench.snap
            let lit = s.lamps.keys.map(\.rawValue).filter { $0.hasPrefix("b.") }.sorted()
            print(
                "B for S\(slot): ctx", String(format: "%.2f", s.meter(PK4.contextMeter)), "used",
                s.nixie(PK4.contextUsed), "out", s.nixie(PK4.outputTokens), "cost",
                s.nixie(PK4.cost), "tools", s.nixie(PK4.toolCalls), "uptime", s.nixie(PK4.uptime),
                lit)
        }
        #expect(batch.issues.isEmpty)
    }

    /// Twenty seconds of the real feed, file events and all, with the CPU it cost —
    /// the `claude` runs it spawned included.
    @Test func theFeedForTwentySeconds() async throws {
        var batches = 0
        var readings = 0
        var gaps: [TimeInterval] = []
        var last = Date()
        let feed = ClaudeCodeFeed { batch in
            batches += 1
            readings += batch.readings.count
            gaps.append(Date().timeIntervalSince(last))
            last = Date()
        }
        feed.start()
        // The first pass reads every transcript from the top; that is not the steady state.
        try await Task.sleep(for: .seconds(4))
        batches = 0
        readings = 0
        gaps = []
        let before = Self.cpuSeconds()
        let wall = Date()
        try await Task.sleep(for: .seconds(20))
        feed.stop()
        let cpu = Self.cpuSeconds() - before
        let elapsed = Date().timeIntervalSince(wall)
        print(
            "feed: \(batches) batches, \(readings / max(1, batches)) readings each, "
                + "shortest gap \(String(format: "%.2f", gaps.dropFirst().min() ?? 0)) s, "
                + "CPU \(String(format: "%.2f", cpu)) s in \(String(format: "%.1f", elapsed)) s "
                + "= \(String(format: "%.1f", 100 * cpu / elapsed))% of a core")
        #expect(batches >= 9)
    }

    /// This process and every child it has waited for.
    static func cpuSeconds() -> Double {
        var own = rusage()
        var children = rusage()
        getrusage(RUSAGE_SELF, &own)
        getrusage(RUSAGE_CHILDREN, &children)
        func seconds(_ time: timeval) -> Double { Double(time.tv_sec) + Double(time.tv_usec) / 1e6 }
        return seconds(own.ru_utime) + seconds(own.ru_stime) + seconds(children.ru_utime)
            + seconds(children.ru_stime)
    }
}

#endif
