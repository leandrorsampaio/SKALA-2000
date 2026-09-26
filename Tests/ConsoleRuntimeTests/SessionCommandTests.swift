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
    private(set) var asked: [String] = []

    init(alive: Set<Int32>, owners: [Int32: SessionKey], allows: Bool = true) {
        self.alive = alive
        self.owners = owners
        self.allows = allows
    }

    func authorize(_ reason: String, _ done: @escaping @Sendable (Bool) -> Void) {
        lock.lock()
        asked.append(reason)
        lock.unlock()
        done(allows)
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

        let answer = try await run(actions[PK4.f10], request(PK4.f10, session: "s-1"))
        #expect(answer == true)
        #expect(processes.sent.map(\.1) == [SIGTERM])
        #expect(processes.asked == ["end the Claude Code session in “tmp”"])
        // Long enough to type a password in.
        #expect((actions[PK4.f10]?.timeout ?? 0) > 60)
    }

    /// A wrong password, or Cancel, ends nothing.
    @Test func endSessionNeedsTheMacsPassword() async throws {
        let processes = FakeProcesses(alive: [4242], owners: [4242: "s-1"], allows: false)
        let actions = SessionCommands.actions(
            details: { _ in SessionDetails(cwd: "/tmp", pid: 4242, name: "x", isJob: false) },
            system: processes, safetyLog: URL(fileURLWithPath: "/tmp/none"))

        let answer = try await run(actions[PK4.f10], request(PK4.f10, session: "s-1"))
        #expect(answer == false)
        #expect(processes.sent.isEmpty)
    }

    /// A pid from a stale reading could by now be any process: nothing is sent to it.
    @Test func aPidThatIsNoLongerTheSessionIsLeftAlone() async throws {
        let processes = FakeProcesses(alive: [4242], owners: [4242: "someone-else"])
        let actions = SessionCommands.actions(
            details: { _ in SessionDetails(cwd: "/tmp", pid: 4242, name: "x", isJob: false) },
            system: processes, safetyLog: URL(fileURLWithPath: "/tmp/none"))

        let answer = try await run(actions[PK4.f10], request(PK4.f10, session: "s-1"))
        #expect(answer == false)
        #expect(processes.sent.isEmpty)
    }

    @Test func aBackgroundJobOrAnEmptySlotHasNoProcessToEnd() async throws {
        let processes = FakeProcesses(alive: [4242], owners: [4242: "job"])
        let actions = SessionCommands.actions(
            details: { _ in SessionDetails(cwd: "/tmp", pid: 4242, name: "x", isJob: true) },
            system: processes, safetyLog: URL(fileURLWithPath: "/tmp/none"))

        #expect(try await run(actions[PK4.f10], request(PK4.f10, session: "job")) == false)
        #expect(try await run(actions[PK4.f10], request(PK4.f10, session: nil)) == false)
        #expect(processes.sent.isEmpty)
    }

    @Test func f6ToF9AreLeftUnassigned() {
        let actions = SessionCommands.actions(
            details: { _ in nil }, system: FakeProcesses(alive: [], owners: [:]),
            safetyLog: URL(fileURLWithPath: "/tmp/none"))
        for id in [PK4.function(6), PK4.function(7), PK4.f8, PK4.f9] { #expect(actions[id] == nil) }
    }

    /// Single-quoted, so a folder called `x; rm -rf ~` stays a folder name.
    @Test func theResumeCommandQuotesTheFolder() {
        #expect(
            SessionCommands.resumeCommand(cwd: "/tmp/it's here", session: "abc")
                == "cd '/tmp/it'\\''s here' && claude --resume abc")
    }
}

#endif
