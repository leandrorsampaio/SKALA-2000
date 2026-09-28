#if !APP_STORE

import Darwin
import Foundation
import Testing

@testable import ConsoleKit
@testable import ConsoleRuntime
@testable import TelemetryKit

/// A process table that obeys, for testing without signalling anything real.
final class FakeProcesses: SessionSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var alive: Set<Int32>
    private let owners: [Int32: SessionKey]
    private(set) var signals: [(Int32, Int32)] = []

    private let allows: Bool
    /// How long the person at the Mac takes to answer.
    private let answersAfter: TimeInterval
    private(set) var asked: [String] = []

    init(
        alive: Set<Int32>, owners: [Int32: SessionKey], allows: Bool = true,
        answersAfter: TimeInterval = 0
    ) {
        self.alive = alive
        self.owners = owners
        self.allows = allows
        self.answersAfter = answersAfter
    }

    func authorize(
        _ reason: String, within timeout: TimeInterval,
        _ done: @escaping @Sendable (Bool) -> Void
    ) {
        lock.lock()
        asked.append(reason)
        lock.unlock()
        guard answersAfter > 0 else { return done(allows) }
        let allows = allows
        DispatchQueue.global().asyncAfter(deadline: .now() + answersAfter) { done(allows) }
    }

    func signal(_ pid: Int32, _ signal: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        signals.append((pid, signal))
        if signal == SIGTERM { alive.remove(pid) }
        return true
    }

    func isStopped(_ pid: Int32) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return alive.contains(pid) ? false : nil
    }

    func isSession(_ pid: Int32, _ key: SessionKey) -> Bool { owners[pid] == key }

    var sent: [(Int32, Int32)] {
        lock.lock()
        defer { lock.unlock() }
        return signals
    }
}

@MainActor
@Suite struct SessionCommandTests {

    func request(_ id: InstrumentID, session: SessionKey?) -> CommandRequest {
        CommandRequest(button: id, ticket: 1, slot: 1, session: session, issuedAt: Date())
    }

    func run(_ action: CommandAction?, _ request: CommandRequest) async throws -> Bool? {
        var answer: Bool?
        action?.perform(request) { answer = $0 }
        for _ in 0..<40 where answer == nil { try await Task.sleep(for: .milliseconds(50)) }
        return answer
    }

    @Test func endSessionSignalsTheSessionsOwnProcessAndWaitsForItToGo() async throws {
        let processes = FakeProcesses(alive: [4242], owners: [4242: "s-1"])
        let actions = SessionCommands.actions(
            details: { _ in SessionDetails(cwd: "/tmp", pid: 4242, name: "x", isJob: false) },
            system: processes, safetyLog: URL(fileURLWithPath: "/tmp/none"))

        let answer = try await run(actions[PK4.f12], request(PK4.f12, session: "s-1"))
        #expect(answer == true)
        #expect(processes.sent.map(\.1) == [SIGTERM])
        #expect(processes.asked == ["end the Claude Code session in “tmp”"])
        // Long enough to type a password in.
        #expect((actions[PK4.f12]?.timeout ?? 0) > 60)
    }

    /// A wrong password, or Cancel, ends nothing.
    @Test func endSessionNeedsTheMacsPassword() async throws {
        let processes = FakeProcesses(alive: [4242], owners: [4242: "s-1"], allows: false)
        let actions = SessionCommands.actions(
            details: { _ in SessionDetails(cwd: "/tmp", pid: 4242, name: "x", isJob: false) },
            system: processes, safetyLog: URL(fileURLWithPath: "/tmp/none"))

        let answer = try await run(actions[PK4.f12], request(PK4.f12, session: "s-1"))
        #expect(answer == false)
        #expect(processes.sent.isEmpty)
    }

    /// A pid from a stale reading could by now be any process: nothing is sent to it.
    @Test func aPidThatIsNoLongerTheSessionIsLeftAlone() async throws {
        let processes = FakeProcesses(alive: [4242], owners: [4242: "someone-else"])
        let actions = SessionCommands.actions(
            details: { _ in SessionDetails(cwd: "/tmp", pid: 4242, name: "x", isJob: false) },
            system: processes, safetyLog: URL(fileURLWithPath: "/tmp/none"))

        let answer = try await run(actions[PK4.f12], request(PK4.f12, session: "s-1"))
        #expect(answer == false)
        #expect(processes.sent.isEmpty)
    }

    /// Past the deadline the desk has shown no answer; a password typed then ends nothing.
    @Test func aPasswordGivenTooLateEndsNothing() async throws {
        let processes = FakeProcesses(
            alive: [4242], owners: [4242: "s-1"], answersAfter: 0.3)
        let actions = SessionCommands.actions(
            details: { _ in SessionDetails(cwd: "/tmp", pid: 4242, name: "x", isJob: false) },
            system: processes, safetyLog: URL(fileURLWithPath: "/tmp/none"),
            passwordTimeout: 0.1)

        let answer = try await run(actions[PK4.f12], request(PK4.f12, session: "s-1"))
        #expect(answer == false)
        #expect(processes.sent.isEmpty)
    }

    /// The password prompt names the session by its folder or its name, never by its id.
    @Test func thePromptNeverShowsTheSessionID() async throws {
        let processes = FakeProcesses(alive: [4242], owners: [4242: "s-1"], allows: false)
        var name: String? = "familyhub-3"
        let actions = SessionCommands.actions(
            details: { _ in SessionDetails(cwd: nil, pid: 4242, name: name, isJob: false) },
            system: processes, safetyLog: URL(fileURLWithPath: "/tmp/none"))
        _ = try await run(actions[PK4.f12], request(PK4.f12, session: "s-1"))
        name = nil
        _ = try await run(actions[PK4.f12], request(PK4.f12, session: "s-1"))
        #expect(
            processes.asked == [
                "end the Claude Code session in “familyhub-3”",
                "end the selected Claude Code session",
            ])
    }

    /// A session file left by a crash names the session, but a new process has its pid.
    @Test func aSessionFileMustHaveBeenWrittenByTheProcessNowRunning() {
        let started = Date(timeIntervalSince1970: 1_790_330_400.35)
        let file: [String: Any] = [
            "sessionId": "s-1", "procStart": "Fri Sep 25 10:00:00 2026",
            "startedAt": 1_790_330_401_000.0,
        ]
        func describes(_ json: [String: Any], _ start: Date?, _ key: SessionKey = "s-1") -> Bool {
            LiveSessionSystem.describes(json, key: key, processStartedAt: start)
        }
        #expect(describes(file, started))
        #expect(!describes(file, started, "s-2"))
        #expect(!describes(file, started.addingTimeInterval(40)))
        #expect(!describes(file, nil))
        // In local time as well as UTC; the day padded as `ps` pads it.
        let local = LiveSessionSystem.lstartLocal.string(from: started)
        #expect(describes(["sessionId": "s-1", "procStart": local], started))
        #expect(
            describes(
                ["sessionId": "s-1", "procStart": "Sat Sep  5 10:00:00 2026"],
                Date(timeIntervalSince1970: 1_788_602_400)))
        // Without procStart, the process cannot have started after the session did.
        let older: [String: Any] = ["sessionId": "s-1", "startedAt": 1_790_330_401_000.0]
        #expect(describes(older, started))
        #expect(!describes(older, started.addingTimeInterval(3600)))
        #expect(!describes(["sessionId": "s-1"], started))
    }

    @Test func aBackgroundJobOrAnEmptySlotHasNoProcessToEnd() async throws {
        let processes = FakeProcesses(alive: [4242], owners: [4242: "job"])
        let actions = SessionCommands.actions(
            details: { _ in SessionDetails(cwd: "/tmp", pid: 4242, name: "x", isJob: true) },
            system: processes, safetyLog: URL(fileURLWithPath: "/tmp/none"))

        #expect(try await run(actions[PK4.f12], request(PK4.f12, session: "job")) == false)
        #expect(try await run(actions[PK4.f12], request(PK4.f12, session: nil)) == false)
        #expect(processes.sent.isEmpty)
    }

    @Test func f6AndF7AreLeftUnassigned() {
        let actions = SessionCommands.actions(
            details: { _ in nil }, system: FakeProcesses(alive: [], owners: [:]),
            safetyLog: URL(fileURLWithPath: "/tmp/none"))
        #expect(PK4.routine == (1...7).map(PK4.function))
        for id in [6, 7].map(PK4.function) {
            #expect(actions[id] == nil)
        }
        // The guarded keys are F12 alone.
        #expect(PK4.guarded == [PK4.f12])
    }

    /// An id that is not a plain one never becomes a path or a shell word.
    @Test func anOddSessionIDIsNeverAPathOrAShellWord() {
        #expect(SessionKey("5d2c-familyhub_1.x").isPathSafe)
        for odd in ["../../etc/passwd", "..", ".", "", "a b", "a;b", "a/b"] {
            #expect(!SessionKey(odd).isPathSafe, "\(odd)")
        }
        #expect(
            SessionCommands.resumeCommand(cwd: "/tmp", session: "a; rm -rf ~")
                == "cd '/tmp' && claude --resume 'a; rm -rf ~'")
        let home = ClaudeHome(root: URL(fileURLWithPath: "/tmp/skala-none"))
        #expect(SessionCommands.transcript(of: "../x", in: home) == nil)
        // A pid too large for the system's type is no process, not a crash.
        #expect(!ClaudeCodeCollector.processIsAlive(5_000_000_000))
    }

    /// Single-quoted, so a folder called `x; rm -rf ~` stays a folder name.
    @Test func theResumeCommandQuotesTheFolder() {
        #expect(
            SessionCommands.resumeCommand(cwd: "/tmp/it's here", session: "abc")
                == "cd '/tmp/it'\\''s here' && claude --resume abc")
    }
}

#endif
