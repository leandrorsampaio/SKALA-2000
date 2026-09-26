#if !APP_STORE

import Foundation

/// One entry of `claude agents --json`: a running session, interactive or background.
public struct AgentRecord: Sendable, Equatable {
    public var key: SessionKey
    public var pid: Int?
    public var cwd: String?
    /// `interactive`, `background` or anything a later build adds.
    public var kind: String?
    public var startedAt: Date?
    public var name: String?
    /// What an interactive session reports: `busy` or `idle`.
    public var status: String?
    /// What a background session reports instead of a status.
    public var state: String?

    public init(key: SessionKey) {
        self.key = key
    }
}

/// `claude agents --json`: the only published surface, and therefore the only authority on
/// which sessions exist. A session it does not list has ended; a run that fails says
/// nothing at all, which the console shows as stale rather than as ended.
public enum AgentsSource {

    public static let arguments = ["agents", "--json"]
    public static let timeout: TimeInterval = 5

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notInstalled
        case couldNotStart
        case timedOut
        case exited(Int32)
        case notAList

        public var description: String {
            switch self {
            case .notInstalled: "claude was not found"
            case .couldNotStart: "claude agents could not be started"
            case .timedOut: "claude agents did not answer in \(Int(AgentsSource.timeout)) s"
            case .exited(let status): "claude agents exited with status \(status)"
            case .notAList: "claude agents --json did not print a list"
            }
        }
    }

    public static func run(
        _ executable: URL?, runner: CommandRunning
    ) -> Result<(records: [AgentRecord], unreadable: Int), Failure> {
        guard let executable else { return .failure(.notInstalled) }
        guard let output = runner.run(executable, arguments: arguments, timeout: timeout) else {
            return .failure(.couldNotStart)
        }
        if output.timedOut { return .failure(.timedOut) }
        guard output.status == 0 else { return .failure(.exited(output.status)) }
        guard let parsed = parse(output.stdout) else { return .failure(.notAList) }
        return .success(parsed)
    }

    /// Records without a `sessionId` are counted and skipped: the console cannot join them
    /// to anything.
    public static func parse(_ data: Data) -> (records: [AgentRecord], unreadable: Int)? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return nil
        }
        var records: [AgentRecord] = []
        var unreadable = 0
        for entry in list {
            guard let json = entry as? [String: Any],
                let id = json["sessionId"] as? String, !id.isEmpty
            else {
                unreadable += 1
                continue
            }
            var record = AgentRecord(key: SessionKey(id))
            record.pid = json["pid"] as? Int
            record.cwd = json["cwd"] as? String
            record.kind = json["kind"] as? String
            // Milliseconds since the epoch, the way the CLI prints them.
            record.startedAt = (json["startedAt"] as? Double).map {
                Date(timeIntervalSince1970: $0 / 1000)
            }
            record.name = json["name"] as? String
            record.status = json["status"] as? String
            record.state = json["state"] as? String
            records.append(record)
        }
        return (records, unreadable)
    }

    /// The roster, then each record's fields.
    public static func readings(
        _ records: [AgentRecord], at moment: Date, ttl: TimeInterval
    ) -> [Reading] {
        var out = [Reading(.machine, .roster, .keys(records.map(\.key)), at: moment, ttl: ttl)]
        for record in records {
            let subject = Subject.session(record.key)
            func add(_ field: Field, _ value: Value?) {
                if let value { out.append(Reading(subject, field, value, at: moment, ttl: ttl)) }
            }
            add(.pid, record.pid.map(Value.count))
            add(.cwd, record.cwd.map(Value.text))
            add(.kind, record.kind.map(Value.text))
            add(.startedAt, record.startedAt.map(Value.time))
            add(.name, record.name.map(Value.text))
            add(.status, record.status.map(Value.text))
            add(.jobState, record.state.map(Value.text))
        }
        return out
    }
}

/// `sessions/<pid>.json`, for the one thing `claude agents` does not print: the build.
///
/// The `.key` files that sit beside them are never opened.
public enum SessionFilesSource {

    public static func versions(in directory: URL) -> [SessionKey: String] {
        let entries =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)) ?? []
        var versions: [SessionKey: String] = [:]
        for url in entries where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let id = json["sessionId"] as? String,
                let version = json["version"] as? String
            else { continue }
            versions[SessionKey(id)] = version
        }
        return versions
    }
}

/// `jobs/<id>/state.json`: what a background agent needs and what it last said.
///
/// These files outlive their jobs — one written in July still said "working, blocked" in
/// September for a job `claude agents --all` reported as failed — so they are only ever
/// read for jobs the roster lists. They also carry a `providerEnv` block that may hold
/// credentials: it is never taken out of the parsed record, stored or logged.
public enum JobsSource {

    public struct Job: Sendable, Equatable {
        public var tempo: String?
        public var needs: String?
        public var detail: String?
        public var name: String?
        public var backend: String?

        public init() {}
    }

    /// Keyed by both the job's session and the one it resumed into, so either finds it.
    public static func jobs(in directory: URL) -> [SessionKey: Job] {
        let entries =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)) ?? []
        var jobs: [SessionKey: Job] = [:]
        for folder in entries {
            let url = folder.appendingPathComponent("state.json")
            guard let data = try? Data(contentsOf: url),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            var job = Job()
            job.tempo = json["tempo"] as? String
            job.needs = json["needs"] as? String
            job.detail = json["detail"] as? String
            job.name = json["name"] as? String
            job.backend = json["backend"] as? String

            for field in ["sessionId", "resumeSessionId"] {
                if let id = json[field] as? String, !id.isEmpty { jobs[SessionKey(id)] = job }
            }
        }
        return jobs
    }

    public static func readings(
        _ job: Job, for key: SessionKey, at moment: Date, ttl: TimeInterval
    ) -> [Reading] {
        let subject = Subject.session(key)
        var out: [Reading] = []
        func add(_ field: Field, _ value: String?) {
            if let value { out.append(Reading(subject, field, .text(value), at: moment, ttl: ttl)) }
        }
        add(.jobTempo, job.tempo)
        add(.jobNeeds, job.needs)
        add(.jobDetail, job.detail)
        add(.jobName, job.name)
        add(.jobBackend, job.backend)
        return out
    }
}

#endif
