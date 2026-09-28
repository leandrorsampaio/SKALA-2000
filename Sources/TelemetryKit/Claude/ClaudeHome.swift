#if !APP_STORE

import Foundation

/// Where Claude Code keeps its files.
///
/// Nothing here is read that the inventory does not name. In particular `ide/*.lock` holds
/// an auth token and `sessions/*.key` holds per-session keys; neither is ever opened.
public struct ClaudeHome: Sendable, Equatable {
    public let root: URL

    public init(root: URL? = nil) {
        self.root =
            root
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
    }

    /// `<pid>.json` per running interactive session.
    public var sessions: URL { root.appendingPathComponent("sessions", isDirectory: true) }
    /// `<id>/state.json` per background job, kept long after the job ends.
    public var jobs: URL { root.appendingPathComponent("jobs", isDirectory: true) }
    /// `<project>/<sessionId>.jsonl` transcripts, and `<sessionId>/subagents/` beside them.
    public var projects: URL { root.appendingPathComponent("projects", isDirectory: true) }
}

/// Runs a program and hands back what it printed.
public protocol CommandRunning: Sendable {
    /// `nil` when the program could not be started at all.
    func run(_ executable: URL, arguments: [String], timeout: TimeInterval) -> CommandOutput?
}

public struct CommandOutput: Sendable, Equatable {
    public var status: Int32
    public var stdout: Data
    public var timedOut: Bool

    public init(status: Int32, stdout: Data, timedOut: Bool = false) {
        self.status = status
        self.stdout = stdout
        self.timedOut = timedOut
    }
}

/// `Process`, with a timeout, so a wedged CLI cannot stall the sources.
public struct ProcessRunner: CommandRunning {

    public init() {}

    public func run(_ executable: URL, arguments: [String], timeout: TimeInterval) -> CommandOutput?
    {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }

        // Read while the program runs: a full pipe would otherwise stop it from exiting.
        // Read as it arrives rather than by a thread blocked until end of file, which a
        // grandchild still holding the pipe would keep blocked for good.
        let collected = Collected()
        let drained = DispatchSemaphore(value: 0)
        let reader = output.fileHandleForReading
        reader.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                drained.signal()
            } else {
                collected.append(data)
            }
        }

        let timedOut = exited.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            // One that ignores SIGTERM is killed: until it exits its pipe stays open, and
            // the reader above waits on it, a thread lost at every timeout.
            if exited.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
        }
        _ = drained.wait(timeout: .now() + 1)
        reader.readabilityHandler = nil
        try? reader.close()
        return CommandOutput(
            status: timedOut ? -1 : process.terminationStatus, stdout: collected.data,
            timedOut: timedOut)
    }

    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Data()

        var data: Data {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func append(_ data: Data) {
            lock.lock()
            value.append(data)
            lock.unlock()
        }
    }
}

/// Finds `claude`.
///
/// An app started from the Finder gets a bare `PATH` without Homebrew or `~/.local/bin`,
/// so the usual install locations are tried first and a login shell is asked only when
/// none of them has it.
public enum ClaudeExecutable {

    public static func candidates(home: URL) -> [URL] {
        [
            home.appendingPathComponent(".local/bin/claude"),
            home.appendingPathComponent(".claude/local/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
            home.appendingPathComponent(".npm-global/bin/claude"),
            home.appendingPathComponent(".bun/bin/claude"),
        ]
    }

    public static func locate(
        candidates: [URL] = candidates(home: FileManager.default.homeDirectoryForCurrentUser),
        runner: CommandRunning = ProcessRunner()
    ) -> URL? {
        if let found = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) {
            return found
        }
        guard
            let output = runner.run(
                URL(fileURLWithPath: "/bin/zsh"), arguments: ["-lc", "command -v claude"],
                timeout: 5),
            output.status == 0,
            let path = String(data: output.stdout, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            path.hasPrefix("/"),
            FileManager.default.isExecutableFile(atPath: path)
        else { return nil }
        return URL(fileURLWithPath: path)
    }
}

#endif
