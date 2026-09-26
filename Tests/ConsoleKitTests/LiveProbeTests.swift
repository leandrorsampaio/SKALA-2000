#if !APP_STORE

import Foundation
import HookServer
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

    /// One real Claude Code run, its hooks installed from the real snippet but pointed at a
    /// hook receiver on a socket of the test's own, and everything that arrives fed to the
    /// console. Costs one short Haiku call.
    @Test func realHooksReachTheConsole() async throws {
        let socket = URL(fileURLWithPath: "/tmp/skala-live-\(getpid()).sock")
        let bench = Bench(start: Date())
        final class Bodies: @unchecked Sendable {
            let lock = NSLock()
            var list: [Data] = []
        }
        let bodies = Bodies()
        let server = HookServer(socketURL: socket) { body in
            bodies.lock.withLock { bodies.list.append(body) }
        }
        try server.start()
        defer { server.stop() }

        // The snippet exactly as the installer writes it, on this test's port.
        let scripts = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(
                "scripts")
        let snippet = try String(
            contentsOf: scripts.appendingPathComponent("claude-hooks.json"), encoding: .utf8
        )
        .replacingOccurrences(
            of: "$HOME/Library/Application Support/SKALA-2000/hooks.sock", with: socket.path)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "skala-hooks-\(getpid())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let settings = folder.appendingPathComponent("settings.json")
        try snippet.write(to: settings, atomically: true, encoding: .utf8)

        let claude = try #require(ClaudeExecutable.locate())
        let process = Process()
        process.executableURL = claude
        process.currentDirectoryURL = folder
        process.arguments = [
            "-p", "--model", "haiku", "--settings", settings.path, "--allowedTools", "Bash(echo:*)",
            "--", "Use the Bash tool to run exactly: echo pk4-live. Then reply OK.",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        while process.isRunning { try await Task.sleep(for: .milliseconds(200)) }
        // The hooks are async: give the last curls a moment to land.
        try await Task.sleep(for: .seconds(2))
        var seen: [Field] = []
        for body in bodies.lock.withLock({ bodies.list }) {
            let readings = ClaudeHooks.readings(from: body, at: bench.now)
            seen += readings.map(\.field)
            bench.feed(readings)
        }

        print("hook readings in order:", seen.map(\.rawValue))
        let taken = bench.log.events(.slotTaken)
        let released = bench.log.events(.slotReleased)
        print("slot taken:", taken.first?.slot ?? 0, "released:", released.first?.detail ?? "-")
        #expect(seen.first == .sessionStarted)
        #expect(seen.contains(.promptSubmitted))
        #expect(seen.contains(.toolUsed))
        #expect(seen.contains(.turnDone))
        #expect(seen.last == .sessionEnded)
        #expect(taken.count == 1)
        #expect(released.first?.detail == "session end")
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
