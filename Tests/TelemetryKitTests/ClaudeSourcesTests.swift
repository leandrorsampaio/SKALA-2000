#if !APP_STORE

import Foundation
import Testing

@testable import TelemetryKit

/// A `~/.claude` in a temporary folder.
final class FakeHome {
    let home: ClaudeHome
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pk4-" + UUID().uuidString, isDirectory: true)
        home = ClaudeHome(root: url)
        for folder in [home.sessions, home.jobs, home.projects] {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func write(_ text: String, to relative: String) {
        let file = url.appendingPathComponent(relative)
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: file)
    }

    func append(_ text: String, to relative: String) {
        let file = url.appendingPathComponent(relative)
        guard let handle = try? FileHandle(forWritingTo: file) else {
            write(text, to: relative)
            return
        }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(text.utf8))
        try? handle.close()
    }
}

/// `claude agents --json`, answering whatever the test says.
final class FakeCLI: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var answer: CommandOutput? = CommandOutput(status: 0, stdout: Data("[]".utf8))
    private(set) var runs = 0

    func say(_ json: String) { set(CommandOutput(status: 0, stdout: Data(json.utf8))) }
    func fail(status: Int32) { set(CommandOutput(status: status, stdout: Data())) }

    private func set(_ output: CommandOutput?) {
        lock.lock()
        answer = output
        lock.unlock()
    }

    func run(_ executable: URL, arguments: [String], timeout: TimeInterval) -> CommandOutput? {
        lock.lock()
        defer { lock.unlock() }
        runs += 1
        return answer
    }
}

@Suite struct ClaudeSourcesTests {

    static let interactive =
        #"{"pid":40101,"cwd":"/Users/operator/familyhub","kind":"interactive","startedAt":1790330400000,"sessionId":"s-1","name":"familyhub-3","status":"busy"}"#
    static let background =
        #"{"id":"00fbe7e6","cwd":"/Users/operator/pk4","kind":"background","startedAt":1790330000000,"sessionId":"job-1","name":"Review root project markdown files","state":"working"}"#

    // MARK: - claude agents --json

    @Test func parsesInteractiveAndBackgroundRecords() throws {
        let data = Data(("[" + Self.interactive + "," + Self.background + #",{"pid":1}]"#).utf8)
        let parsed = try #require(AgentsSource.parse(data))

        #expect(parsed.unreadable == 1)
        #expect(parsed.records.map(\.key) == ["s-1", "job-1"])
        let session = parsed.records[0]
        #expect(session.pid == 40101)
        #expect(session.status == "busy")
        #expect(session.startedAt == Date(timeIntervalSince1970: 1_790_330_400))
        #expect(parsed.records[1].state == "working")
        #expect(parsed.records[1].pid == nil)
    }

    @Test func somethingThatIsNotAListIsAFailureNotAnEmptyRoster() {
        #expect(AgentsSource.parse(Data(#"{"sessions":[]}"#.utf8)) == nil)
        #expect(AgentsSource.parse(Data("Update available".utf8)) == nil)
        #expect(AgentsSource.parse(Data("[]".utf8))?.records.isEmpty == true)
    }

    @Test func readingsStartWithTheRoster() throws {
        let parsed = try #require(AgentsSource.parse(Data(("[" + Self.interactive + "]").utf8)))
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        let readings = AgentsSource.readings(parsed.records, at: moment, ttl: 6)

        #expect(readings.first?.field == .roster)
        #expect(readings.first?.value == .keys(["s-1"]))
        #expect(readings.contains { $0.field == .status && $0.value == .text("busy") })
        #expect(readings.allSatisfy { $0.value.kind == $0.field.kind })
    }

    // MARK: - Session and job files

    @Test func versionsComeFromTheSessionFilesAndKeyFilesAreNeverOpened() {
        let fake = FakeHome()
        fake.write(
            #"{"pid":40101,"sessionId":"s-1","version":"2.1.280"}"#, to: "sessions/40101.json")
        fake.write("not json, and not ours to read", to: "sessions/40101.abcdef.key")

        #expect(SessionFilesSource.versions(in: fake.home.sessions) == ["s-1": "2.1.280"])
    }

    @Test func jobsAreFoundByEitherSessionAndTheirSecretsGoNowhere() {
        let fake = FakeHome()
        fake.write(
            #"{"state":"working","tempo":"blocked","needs":"send a prompt to start","detail":"reading","name":"Review root project markdown files","backend":"daemon","sessionId":"job-1","resumeSessionId":"job-1b","providerEnv":{"ANTHROPIC_API_KEY":"sk-secret-value"}}"#,
            to: "jobs/00fbe7e6/state.json")

        let jobs = JobsSource.jobs(in: fake.home.jobs)
        #expect(jobs["job-1"]?.tempo == "blocked")
        #expect(jobs["job-1b"]?.needs == "send a prompt to start")

        let readings = JobsSource.readings(
            jobs["job-1"]!, for: "job-1", at: Date(), ttl: 6)
        let everything = readings.map { "\($0.value)" }.joined()
        #expect(!everything.contains("sk-secret"))
        #expect(
            Set(readings.map(\.field)) == [.jobTempo, .jobNeeds, .jobDetail, .jobName, .jobBackend])
    }

    // MARK: - The transcript

    @Test func theTranscriptIsFollowedAndAPartialLineWaitsForTheRest() {
        let fake = FakeHome()
        let path = "projects/-Users-operator-familyhub/s-1.jsonl"
        let record =
            #"{"type":"assistant","requestId":"r1","message":{"model":"claude-opus-5","usage":{"output_tokens":100}}}"#
        fake.write(record + "\n" + String(record.prefix(40)), to: path)

        let source = TranscriptSource(key: "s-1", projects: fake.home.projects)
        let first = source.poll(at: Date(), ttl: 6)
        #expect(first.first { $0.field == .outputTokens }?.value == .count(100))

        // The rest of the half-written line, then a new request.
        let second =
            #"{"type":"assistant","requestId":"r2","message":{"model":"claude-opus-5","usage":{"output_tokens":5}}}"#
        fake.append(String(record.dropFirst(40)) + "\n" + second + "\n", to: path)
        let next = source.poll(at: Date(), ttl: 6)
        #expect(next.first { $0.field == .outputTokens }?.value == .count(105))
    }

    @Test func aReplacedTranscriptIsReadAgainFromTheTop() {
        let fake = FakeHome()
        let path = "projects/p/s-1.jsonl"
        let line = { (request: String, output: Int) in
            #"{"type":"assistant","requestId":""# + request
                + #"","message":{"model":"m","usage":{"output_tokens":"# + String(output) + "}}}\n"
        }
        fake.write(line("a", 100) + line("b", 100), to: path)
        let source = TranscriptSource(key: "s-1", projects: fake.home.projects)
        _ = source.poll(at: Date(), ttl: 6)

        fake.write(line("c", 7), to: path)
        let readings = source.poll(at: Date(), ttl: 6)
        #expect(readings.first { $0.field == .outputTokens }?.value == .count(7))
    }

    @Test func theCheckpointComesFromTheSameFile() {
        let fake = FakeHome()
        fake.write(
            #"{"type":"cost-state","totalCostUSD":9.4,"totalLinesAdded":12,"modelUsage":{"claude-sonnet-5":{"outputTokens":10}}}"#
                + "\n", to: "projects/p/s-1.jsonl")
        let readings = TranscriptSource(key: "s-1", projects: fake.home.projects)
            .poll(at: Date(), ttl: 6)
        #expect(readings.first { $0.field == .costUSD }?.value == .amount(9.4))
        #expect(readings.first { $0.field == .contextWindow }?.value == .count(200_000))
    }

    @Test func aSubagentWritingLightsActivityDatedWhenItWrote() throws {
        let fake = FakeHome()
        fake.write(#"{"type":"mode","mode":"normal"}"# + "\n", to: "projects/p/s-1.jsonl")
        fake.write("{}\n", to: "projects/p/s-1/subagents/agent-a1.jsonl")

        let source = TranscriptSource(key: "s-1", projects: fake.home.projects)
        let activity = try #require(
            source.poll(at: Date(), ttl: 6).first { $0.field == .subagentActivity })
        #expect(activity.ttl == TTL.subagentActivity)
        #expect(abs(activity.observedAt.timeIntervalSinceNow) < 5)

        // A minute later that write is old news.
        let later = source.poll(at: Date().addingTimeInterval(60), ttl: 6)
        #expect(!later.contains { $0.field == .subagentActivity })
    }

    @Test func aTranscriptThatIsNotThereYetIsLookedForAgainLater() {
        let fake = FakeHome()
        let source = TranscriptSource(key: "s-1", projects: fake.home.projects)
        let start = Date()
        #expect(source.poll(at: start, ttl: 6).isEmpty)

        fake.write(#"{"type":"mode","mode":"normal"}"# + "\n", to: "projects/p/s-1.jsonl")
        #expect(source.poll(at: start.addingTimeInterval(2), ttl: 6).isEmpty)
        #expect(!source.poll(at: start.addingTimeInterval(11), ttl: 6).isEmpty)
    }

    // MARK: - The collector

    func collector(
        _ fake: FakeHome, _ cli: FakeCLI, alive: Set<Int> = [40101]
    ) -> ClaudeCodeCollector {
        ClaudeCodeCollector(
            home: fake.home, runner: cli, isAlive: { alive.contains($0) },
            locateExecutable: { URL(fileURLWithPath: "/usr/local/bin/claude") })
    }

    @Test func theCLIRunsOnChangesAndTheHeartbeatNotOnEveryPass() {
        let fake = FakeHome()
        let cli = FakeCLI()
        cli.say("[" + Self.interactive + "]")
        let collector = collector(fake, cli)
        let start = Date()

        let first = collector.collect(at: start)
        #expect(cli.runs == 1)
        #expect(first.readings.first?.field == .roster)

        // Passes in between report the last answer again, without running anything.
        for second in [2.0, 4, 6, 8] {
            let batch = collector.collect(at: start.addingTimeInterval(second))
            #expect(batch.readings.first?.value == .keys(["s-1"]))
        }
        #expect(cli.runs == 1)

        // A session file changed: run now.
        _ = collector.collect(at: start.addingTimeInterval(9), trigger: .sessions)
        #expect(cli.runs == 2)
        // Nothing changed: not until the heartbeat.
        _ = collector.collect(at: start.addingTimeInterval(9 + ClaudeCodeCollector.heartbeat - 1))
        #expect(cli.runs == 2)
        _ = collector.collect(at: start.addingTimeInterval(9 + ClaudeCodeCollector.heartbeat))
        #expect(cli.runs == 3)
    }

    @Test func aBurstOfChangesRunsTheCLIOnce() {
        let fake = FakeHome()
        let cli = FakeCLI()
        let collector = collector(fake, cli)
        let start = Date()
        _ = collector.collect(at: start)
        _ = collector.collect(at: start.addingTimeInterval(0.2), trigger: .sessions)
        _ = collector.collect(at: start.addingTimeInterval(0.4), trigger: .sessions)
        #expect(cli.runs == 1)
        #expect(collector.deferredRun == start.addingTimeInterval(ClaudeCodeCollector.minimumGap))

        _ = collector.collect(at: start.addingTimeInterval(1))
        #expect(cli.runs == 2)
        #expect(collector.deferredRun == nil)
    }

    @Test func aProcessThatDiesRunsTheCLIOnceNotEveryPass() {
        let fake = FakeHome()
        let cli = FakeCLI()
        cli.say("[" + Self.interactive + "]")
        let start = Date()
        var alive: Set<Int> = [40101]
        let collector = ClaudeCodeCollector(
            home: fake.home, runner: cli, isAlive: { alive.contains($0) },
            locateExecutable: { URL(fileURLWithPath: "/usr/local/bin/claude") })
        _ = collector.collect(at: start)

        alive = []
        _ = collector.collect(at: start.addingTimeInterval(2))
        #expect(cli.runs == 2)
        // The CLI still lists it: that is its answer, and asking again every pass would
        // cost what the heartbeat exists to save.
        _ = collector.collect(at: start.addingTimeInterval(4))
        _ = collector.collect(at: start.addingTimeInterval(6))
        #expect(cli.runs == 2)
    }

    @Test func aFailedRunReportsNothingAboutAnySession() {
        let fake = FakeHome()
        let cli = FakeCLI()
        cli.say("[" + Self.interactive + "]")
        let collector = collector(fake, cli)
        let start = Date()
        _ = collector.collect(at: start)

        cli.fail(status: 1)
        let failed = collector.collect(at: start.addingTimeInterval(10), trigger: .sessions)
        #expect(failed.readings.isEmpty)
        #expect(failed.issues.first?.message == "claude agents exited with status 1")

        // Nor on the passes after it, until a run succeeds.
        #expect(collector.collect(at: start.addingTimeInterval(12)).readings.isEmpty)
    }

    @Test func noClaudeInstalledIsAnIssueNotACrash() {
        let fake = FakeHome()
        let collector = ClaudeCodeCollector(
            home: fake.home, runner: FakeCLI(), locateExecutable: { nil })
        let batch = collector.collect(at: Date())
        #expect(batch.readings.isEmpty)
        #expect(batch.issues.first?.message == "claude was not found")
    }

    @Test func jobFilesAreReadOnlyForBackgroundSessionsTheRosterLists() {
        let fake = FakeHome()
        fake.write(
            #"{"tempo":"blocked","needs":"send a prompt to start","sessionId":"job-1"}"#,
            to: "jobs/a/state.json")
        fake.write(
            #"{"tempo":"blocked","needs":"long gone","sessionId":"dead-job"}"#,
            to: "jobs/b/state.json")
        let cli = FakeCLI()
        cli.say("[" + Self.interactive + "," + Self.background + "]")
        let batch = collector(fake, cli).collect(at: Date())

        let tempos = batch.readings.filter { $0.field == .jobTempo }
        #expect(tempos.map(\.subject) == [.session("job-1")])
        #expect(!batch.readings.contains { $0.subject == .session("dead-job") })
        #expect(batch.readings.contains { $0.field == .jobState && $0.value == .text("working") })
    }

    @Test func everyListedSessionGetsItsTranscriptAndItsBuild() {
        let fake = FakeHome()
        fake.write(#"{"sessionId":"s-1","version":"2.1.280"}"#, to: "sessions/40101.json")
        fake.write(
            #"{"type":"permission-mode","permissionMode":"auto"}"# + "\n",
            to: "projects/p/s-1.jsonl")
        let cli = FakeCLI()
        cli.say("[" + Self.interactive + "]")
        let batch = collector(fake, cli).collect(at: Date())

        #expect(batch.readings.contains { $0.field == .version && $0.value == .text("2.1.280") })
        #expect(
            batch.readings.contains { $0.field == .permissionMode && $0.value == .text("auto") })
        #expect(
            batch.readings.allSatisfy {
                $0.ttl == ClaudeCodeCollector.ttl || $0.field == .subagentActivity
            })
    }

    @Test func aLoginShellFindsClaudeWhenNoKnownLocationHasIt() {
        let fake = FakeHome()
        let shell = FakeCLI()
        shell.say("/bin/ls\n")
        let found = ClaudeExecutable.locate(
            candidates: [fake.url.appendingPathComponent("nowhere/claude")], runner: shell)
        #expect(found?.path == "/bin/ls")
    }
}

#endif
