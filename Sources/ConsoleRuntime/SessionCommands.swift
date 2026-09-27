#if !APP_STORE

import AppKit
import ConsoleKit
import Darwin
import Foundation
import LocalAuthentication
import TelemetryKit

/// What the session commands need from the operating system, so they can be tested
/// without stopping real processes.
public protocol SessionSystem: Sendable {
    func signal(_ pid: Int32, _ signal: Int32) -> Bool
    /// `nil` when the process cannot be found.
    func isStopped(_ pid: Int32) -> Bool?
    /// That this process is the Claude Code session it is claimed to be: its session file
    /// names that session, and was written by this very process. A pid from a stale
    /// reading could by now be anything.
    func isSession(_ pid: Int32, _ key: SessionKey) -> Bool
    /// Asks whoever is at the Mac to prove it is them, with the login password or Touch ID.
    /// `reason` completes the system's "SKALA-2000 is trying to …". A prompt still open
    /// after `timeout` is taken down and answers no.
    func authorize(
        _ reason: String, within timeout: TimeInterval,
        _ done: @escaping @Sendable (Bool) -> Void)
}

public struct LiveSessionSystem: SessionSystem {
    public let home: ClaudeHome

    public init(home: ClaudeHome = ClaudeHome()) {
        self.home = home
    }

    public func signal(_ pid: Int32, _ signal: Int32) -> Bool {
        kill(pid, signal) == 0
    }

    public func isStopped(_ pid: Int32) -> Bool? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_proc.p_stat == SSTOP
    }

    public func isSession(_ pid: Int32, _ key: SessionKey) -> Bool {
        let file = home.sessions.appendingPathComponent("\(pid).json")
        guard let data = try? Data(contentsOf: file),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return Self.describes(json, key: key, processStartedAt: Self.processStart(pid))
    }

    /// That a session file names `key` and was written by the process now running under its
    /// pid. A session that crashed leaves its file behind, and its pid can be reused.
    ///
    /// Claude Code writes its process's start time into `procStart`, as `ps -o lstart`
    /// prints it: in UTC on the Macs measured, so local time is accepted too. A file without
    /// it has `startedAt`, which its process cannot have started after. A file with neither
    /// proves nothing, and nothing is sent.
    static func describes(_ json: [String: Any], key: SessionKey, processStartedAt: Date?) -> Bool {
        guard json["sessionId"] as? String == key.rawValue, let started = processStartedAt else {
            return false
        }
        if let text = json["procStart"] as? String {
            let words = text.split(separator: " ").joined(separator: " ")
            return [lstartUTC, lstartLocal].contains { format in
                format.date(from: words).map { abs($0.timeIntervalSince(started)) < 2 } ?? false
            }
        }
        if let milliseconds = json["startedAt"] as? Double {
            return started.timeIntervalSince1970 <= milliseconds / 1000 + 5
        }
        return false
    }

    static func processStart(_ pid: Int32) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(
            timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1e6)
    }

    private static func lstart(_ zone: TimeZone) -> DateFormatter {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = zone
        format.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return format
    }
    static let lstartUTC = lstart(TimeZone(identifier: "UTC")!)
    static let lstartLocal = lstart(.current)

    public func authorize(
        _ reason: String, within timeout: TimeInterval,
        _ done: @escaping @Sendable (Bool) -> Void
    ) {
        let context = LAContext()
        var unavailable: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &unavailable) else {
            return done(false)
        }
        // By then the desk has shown no answer: the prompt is taken down, so a password
        // typed later cannot end the session.
        let expiry = DispatchWorkItem { context.invalidate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: expiry)
        // The context is held by the closure until the answer comes back.
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
            _ = context
            expiry.cancel()
            done(ok)
        }
    }
}

/// What the operator can do to the selected session.
///
/// The routine keys open things: F1 the session's folder, F2 a Terminal there, F4 the
/// safety log, F5 the transcript; F3 puts the command that resumes the session on the
/// clipboard. F10, behind its guard and its key, ends the session with `SIGTERM`, which
/// Claude Code exits cleanly on and which F3's command undoes.
///
/// F6 to F9 are left unassigned, on purpose. Freezing a session with `SIGSTOP` looked
/// right for F8 and F9 and is not: a session in a terminal is the terminal's foreground
/// job, so the shell takes the terminal back and `SIGCONT` resumes it in the background,
/// where it stops again the moment it reads a key. A key that half works is worse than
/// one that says it does nothing.
///
/// None of them is confirmed by being sent: each reports what it observed afterwards, and
/// F10 checks first that the pid still belongs to that session.
public enum SessionCommands {

    public static func actions(
        details: @escaping @MainActor (SessionKey) -> SessionDetails?,
        system: SessionSystem = LiveSessionSystem(),
        home: ClaudeHome = ClaudeHome(),
        safetyLog: URL,
        passwordTimeout: TimeInterval = SessionCommands.passwordTimeout
    ) -> [InstrumentID: CommandAction] {
        [
            PK4.function(1): CommandAction { request, reply in
                guard let cwd = cwd(of: request, details) else { return reply(false) }
                reply(NSWorkspace.shared.open(URL(fileURLWithPath: cwd, isDirectory: true)))
            },
            PK4.function(2): CommandAction { request, reply in
                guard let cwd = cwd(of: request, details),
                    let terminal = NSWorkspace.shared.urlForApplication(
                        withBundleIdentifier: "com.apple.Terminal")
                else { return reply(false) }
                NSWorkspace.shared.open(
                    [URL(fileURLWithPath: cwd, isDirectory: true)], withApplicationAt: terminal,
                    configuration: NSWorkspace.OpenConfiguration()
                ) { _, error in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { reply(error == nil) }
                    }
                }
            },
            PK4.function(3): CommandAction { request, reply in
                guard let key = request.session, let cwd = cwd(of: request, details) else {
                    return reply(false)
                }
                NSPasteboard.general.clearContents()
                reply(
                    NSPasteboard.general.setString(
                        resumeCommand(cwd: cwd, session: key), forType: .string))
            },
            PK4.function(4): CommandAction { _, reply in
                reply(NSWorkspace.shared.open(safetyLog))
            },
            PK4.function(5): CommandAction { request, reply in
                guard let key = request.session, let transcript = transcript(of: key, in: home)
                else {
                    return reply(false)
                }
                NSWorkspace.shared.activateFileViewerSelecting([transcript])
                reply(true)
            },
            PK4.f10: process(
                SIGTERM, details: details, system: system, passwordTimeout: passwordTimeout,
                asking: { place in
                    place.map { "end the Claude Code session in “\($0)”" }
                        ?? "end the selected Claude Code session"
                }
            ) { pid in
                system.isStopped(pid) == nil
            },
        ]
    }

    /// What resumes a session: in its own folder, by its id. Single-quoted, so a folder
    /// name cannot become a command.
    public static func resumeCommand(cwd: String, session: SessionKey) -> String {
        let quoted = "'" + cwd.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "cd \(quoted) && claude --resume \(session.rawValue)"
    }

    static func transcript(of key: SessionKey, in home: ClaudeHome) -> URL? {
        let folders =
            (try? FileManager.default.contentsOfDirectory(
                at: home.projects, includingPropertiesForKeys: nil)) ?? []
        return folders.map { $0.appendingPathComponent(key.rawValue + ".jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    @MainActor
    private static func cwd(
        of request: CommandRequest, _ details: (SessionKey) -> SessionDetails?
    ) -> String? {
        guard let key = request.session, let cwd = details(key)?.cwd, !cwd.isEmpty else {
            return nil
        }
        return cwd
    }

    /// Long enough to type a password; a prompt left open longer shows as no answer.
    public static let passwordTimeout: TimeInterval = 90

    /// Sends one signal to the session's own process, then watches for up to 2.5 s for the
    /// state it should have produced. With `asking`, the Mac's password comes first: a
    /// wrong one, or Cancel, sends nothing and shows as no answer. So does one given after
    /// `passwordTimeout`, when the desk has already shown no answer.
    ///
    /// The prompt names the session by its folder, or by its name; never by its id.
    private static func process(
        _ signal: Int32, details: @escaping @MainActor (SessionKey) -> SessionDetails?,
        system: SessionSystem, passwordTimeout: TimeInterval = SessionCommands.passwordTimeout,
        asking: ((String?) -> String)? = nil,
        reached: @escaping @Sendable (Int32) -> Bool
    ) -> CommandAction {
        let timeout = asking == nil ? ConsoleTiming.noAnswer : passwordTimeout + 3
        return CommandAction(timeout: timeout) { request, reply in
            guard let key = request.session, let found = details(key), !found.isJob,
                let number = found.pid, number > 0
            else { return reply(false) }
            let pid = Int32(number)
            let send = {
                sendAndWatch(pid, key, signal, system: system, reached: reached, reply: reply)
            }
            guard let asking else { return send() }
            let place =
                found.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
                ?? found.name.flatMap { $0.isEmpty ? nil : $0 }
            // The continuous clock counts a Mac asleep with the prompt open, as the desk does.
            let asked = ContinuousClock.now
            system.authorize(asking(place), within: passwordTimeout) { allowed in
                let inTime = asked.duration(to: .now) <= .seconds(passwordTimeout)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { allowed && inTime ? send() : reply(false) }
                }
            }
        }
    }

    @MainActor
    private static func sendAndWatch(
        _ pid: Int32, _ key: SessionKey, _ signal: Int32, system: SessionSystem,
        reached: @escaping @Sendable (Int32) -> Bool,
        reply: @escaping @MainActor (Bool) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let sent = system.isSession(pid, key) && system.signal(pid, signal)
            var observed = false
            if sent {
                for _ in 0..<25 {
                    if reached(pid) {
                        observed = true
                        break
                    }
                    usleep(100_000)
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { reply(observed) }
            }
        }
    }
}

#endif
