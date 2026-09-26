#if !APP_STORE

import Darwin
import Foundation

/// Puts the Claude Code sources together into one pass.
///
/// `claude agents --json` decides which sessions exist; everything else is read only for
/// sessions it lists. It is not run on every pass — one run costs a tenth of a second of
/// CPU, and every two seconds that is a steady 5% of a core. It runs when something under
/// `sessions/` or `jobs/` changes (a session file is rewritten the moment its status
/// flips, and removed when it ends), when a listed process exits, and every thirty seconds
/// regardless, as a safety net for anything those miss. Between runs the
/// last good answer is reported again: nothing that could change it has happened. After a
/// failed run nothing about any session is reported, so the console shows it as stale.
///
/// Not thread safe: `ClaudeCodeFeed` calls it from one queue.
public final class ClaudeCodeCollector {

    /// Everything is reported this often, so a reading lives three of these.
    public static let tick: TimeInterval = 2
    /// Measured: every ten seconds this was two thirds of the console's idle CPU.
    public static let heartbeat: TimeInterval = 30
    /// A burst of file events runs the CLI once, not once per event.
    public static let minimumGap: TimeInterval = 1
    public static let ttl = TTL.polled(every: tick)

    public struct Trigger: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// Something under `sessions/` changed.
        public static let sessions = Trigger(rawValue: 1)
        /// Something under `jobs/` changed.
        public static let jobs = Trigger(rawValue: 2)
    }

    private let home: ClaudeHome
    private let runner: CommandRunning
    private let isAlive: (Int) -> Bool
    private let locateExecutable: () -> URL?

    private var executable: URL?
    private var lastLocate = Date.distantPast
    private var records: [AgentRecord]?
    /// Processes already gone when the CLI last ran. A record the CLI still lists for a
    /// dead process must not make it run again on every pass.
    private var deadAtLastRun: Set<Int> = []
    private var lastRun: Date?
    private var pendingRun = false
    private var versions: [SessionKey: String] = [:]
    private var jobs: [SessionKey: JobsSource.Job] = [:]
    private var transcripts: [SessionKey: TranscriptSource] = [:]

    public init(
        home: ClaudeHome = ClaudeHome(),
        runner: CommandRunning = ProcessRunner(),
        isAlive: @escaping (Int) -> Bool = ClaudeCodeCollector.processIsAlive,
        locateExecutable: (() -> URL?)? = nil
    ) {
        self.home = home
        self.runner = runner
        self.isAlive = isAlive
        self.locateExecutable = locateExecutable ?? { ClaudeExecutable.locate(runner: runner) }
    }

    /// When the CLI next has to run because a run was asked for too soon after the last.
    public var deferredRun: Date? {
        guard pendingRun, let lastRun else { return nil }
        return lastRun.addingTimeInterval(Self.minimumGap)
    }

    public func collect(at moment: Date, trigger: Trigger = []) -> TelemetryBatch {
        var batch = TelemetryBatch()

        if trigger.contains(.sessions) || trigger.contains(.jobs) || needsRun(at: moment) {
            pendingRun = true
        }
        if pendingRun {
            if let lastRun, moment.timeIntervalSince(lastRun) < Self.minimumGap {
                // Too soon: the feed comes back at `deferredRun`.
            } else {
                runAgents(at: moment, into: &batch)
            }
        } else if trigger.contains(.jobs), let records {
            refreshJobs(for: records)
        }

        guard let records else { return batch }
        let ttl = Self.ttl
        batch.readings += AgentsSource.readings(records, at: moment, ttl: ttl)
        for record in records {
            let key = record.key
            let subject = Subject.session(key)
            if let version = versions[key] {
                batch.readings.append(
                    Reading(subject, .version, .text(version), at: moment, ttl: ttl))
            }
            if let job = jobs[key] {
                batch.readings += JobsSource.readings(job, for: key, at: moment, ttl: ttl)
            }
            let transcript = transcripts[key] ?? TranscriptSource(key: key, projects: home.projects)
            transcripts[key] = transcript
            batch.readings += transcript.poll(at: moment, ttl: ttl)
        }
        return batch
    }

    // MARK: - The CLI

    private func needsRun(at moment: Date) -> Bool {
        guard let lastRun else { return true }
        if moment.timeIntervalSince(lastRun) >= Self.heartbeat { return true }
        // A session that crashed leaves its file behind; its process is the tell.
        return deadPids().subtracting(deadAtLastRun).isEmpty == false
    }

    private func deadPids() -> Set<Int> {
        Set((records ?? []).compactMap(\.pid).filter { !isAlive($0) })
    }

    private func runAgents(at moment: Date, into batch: inout TelemetryBatch) {
        pendingRun = false
        lastRun = moment

        if executable == nil, moment.timeIntervalSince(lastLocate) >= 60 {
            lastLocate = moment
            executable = locateExecutable()
        }

        switch AgentsSource.run(executable, runner: runner) {
        case .success(let result):
            records = result.records
            deadAtLastRun = deadPids()
            if result.unreadable > 0 {
                batch.issues.append(
                    TelemetryIssue(
                        source: "agents",
                        message: "\(result.unreadable) record(s) without a session id",
                        at: moment))
            }
            versions = SessionFilesSource.versions(in: home.sessions)
            refreshJobs(for: result.records)
            let listed = Set(result.records.map(\.key))
            transcripts = transcripts.filter { listed.contains($0.key) }

        case .failure(let failure):
            // Nothing is believed until a run succeeds again. Saying nothing is what
            // turns into DATA STALE; saying the last answer again would be lying.
            records = nil
            if failure == .notInstalled { executable = nil }
            batch.issues.append(
                TelemetryIssue(source: "agents", message: failure.description, at: moment))
        }
    }

    private func refreshJobs(for records: [AgentRecord]) {
        let background = records.filter { $0.kind != "interactive" }.map(\.key)
        guard !background.isEmpty else {
            jobs = [:]
            return
        }
        let all = JobsSource.jobs(in: home.jobs)
        // Not `uniqueKeysWithValues`: a roster that lists a session twice must not crash.
        jobs = Dictionary(
            background.compactMap { key in all[key].map { (key, $0) } },
            uniquingKeysWith: { first, _ in first })
    }

    /// `kill` with signal 0 checks for the process without touching it.
    public static func processIsAlive(_ pid: Int) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid_t(pid), 0) == 0 || errno == EPERM
    }
}

#endif
