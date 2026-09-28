import Foundation
import TelemetryKit

/// A scripted working day of telemetry, so the whole desk runs without Claude Code.
///
/// Ten hours from 08:00, in the shapes the real sources emit: a roster and per-session
/// fields every two seconds, `cost-state` checkpoints, hook events at every transition,
/// and the Mac's power. Deterministic for a given seed, so a test can replay it and a demo
/// looks the same every time.
///
/// What happens, so every rule on the desk gets exercised:
///
/// | When  | What |
/// | ----- | ---- |
/// | 08:00 | FAMILYHUB starts: Opus, 1M window, x-high, auto |
/// | 08:10 | TAX starts: Sonnet, 200K, medium, accept edits |
/// | 08:30 | A background job starts; it blocks at 09:00 and is answered at 09:20 |
/// | 08:40 | PK4 starts: Sonnet, plan mode; its effort turns to `max` at 10:20 |
/// | 08:50 | A fifth session starts and waits for a slot; it gets TAX's at 09:30 |
/// | 09:10 | FAMILYHUB compacts |
/// | 09:40 | `claude agents` fails for two minutes: every slot goes stale |
/// | 10:00 | The Mac is unplugged; the battery runs below 20% before 10:30 |
/// | 10:10 | FAMILYHUB's cost figure restarts from zero, as a resumed session's does |
/// | 17:00 | Everything has ended by 18:00 |
public struct FakeDay: Sendable {

    public static let tick: TimeInterval = 2
    public static let length: TimeInterval = 10 * 3600
    public static let pollTTL = TTL.polled(every: tick)
    public static let checkpointTTL = TTL.polled(every: 5)

    public let start: Date
    public private(set) var elapsed: TimeInterval = 0
    public var now: Date { start.addingTimeInterval(elapsed) }
    public var isOver: Bool { elapsed >= Self.length }

    private var rng: SplitMix
    private var sessions: [SimSession]
    private var battery = 0.86

    /// - Parameters:
    ///   - start: the day's midnight, as the day's clock reads it.
    ///   - seed: the randomness, the same every time for the same seed.
    ///   - keySuffix: appended to every session's id. A demo gives each day its own, so the
    ///     desk counts a new day's sessions from zero instead of taking them for
    ///     yesterday's, whose figures it remembers.
    public init(start: Date, seed: UInt64 = 1972, keySuffix: String = "") {
        self.start = start
        rng = SplitMix(seed: seed)
        sessions = SimSession.cast()
        if !keySuffix.isEmpty {
            for index in sessions.indices {
                sessions[index].key = SessionKey(sessions[index].key.rawValue + keySuffix)
            }
        }
    }

    /// When a demo opens the day: 08:55, five minutes before the first alarm.
    public static let opensAt: TimeInterval = 55 * 60

    /// The day as a demo plays it. Everything before 08:55 has already happened, unseen,
    /// and the day's clock is set so that 08:55 is `moment`: its readings are stamped with
    /// the real time, and nothing downstream can tell them from Claude Code's. It stops
    /// one tick short, so the first catch-up has the whole desk to report.
    public static func opening(at moment: Date, seed: UInt64 = 1972) -> FakeDay {
        let suffix = "-" + String(Int(moment.timeIntervalSince1970) / 60, radix: 36)
        var day = FakeDay(start: moment.addingTimeInterval(-opensAt), seed: seed, keySuffix: suffix)
        while day.elapsed + tick < opensAt { _ = day.step() }
        return day
    }

    /// Every tick due by `moment`, so a day played on a timer keeps to the wall clock
    /// rather than drifting from it.
    public mutating func catchUp(to moment: Date) -> [Reading] {
        var out: [Reading] = []
        while !isOver, now.addingTimeInterval(Self.tick) <= moment { out += step() }
        return out
    }

    /// Advances one tick and returns everything the sources would have reported in it.
    public mutating func step() -> [Reading] {
        elapsed += Self.tick
        let t = elapsed
        let moment = now
        var out: [Reading] = []

        for index in sessions.indices {
            sessions[index].advance(to: t, at: moment, rng: &rng, into: &out)
        }

        // `claude agents` fails: no roster, and nothing that keys off it.
        let agentsDown = (6000..<6120).contains(t)
        if !agentsDown {
            let listed = sessions.filter(\.isRunning)
            out.append(
                Reading(.machine, .roster, .keys(listed.map(\.key)), at: moment, ttl: Self.pollTTL))
            for session in listed { out += session.polled(at: moment, day: t) }
        }

        let onMains = !(7200..<9000).contains(t)
        // Unplugged at 40%, it crosses 20% about twenty minutes later.
        battery = onMains ? min(1, battery + 0.0004) : max(0.02, battery - 0.0003)
        if t == 7200 { battery = 0.4 }
        out += [
            Reading(.machine, .batteryFraction, .amount(battery), at: moment, ttl: 30),
            Reading(.machine, .onMains, .flag(onMains), at: moment, ttl: 30),
            Reading(.machine, .charging, .flag(onMains && battery < 0.999), at: moment, ttl: 30),
            Reading(.machine, .displayAsleep, .flag(false), at: moment, ttl: 30),
            Reading(.machine, .systemAsleep, .flag(false), at: moment, ttl: 30),
        ]
        out += quota(at: moment, day: t)
        out += load(at: moment, day: t)
        return out
    }

    /// What the Mac is doing, as the load source reports it: busier the more sessions work,
    /// warm through the compaction at 09:10, short of memory for ten minutes at 10:10. Worked
    /// out from the clock alone, never the day's randomness, so the rest of the day plays as
    /// it always has; and in whole units, so a replay is not a stream of tiny changes.
    func load(at moment: Date, day t: TimeInterval) -> [Reading] {
        let working = Double(sessions.filter(\.isWorking).count)
        let wave = sin(t / 97)
        let gigabyte = 1_073_741_824.0
        func percent(_ share: Double) -> Double { min(1, max(0, (share * 100).rounded() / 100)) }
        func reading(_ field: Field, _ value: Value) -> Reading {
            Reading(.machine, field, value, at: moment, ttl: Self.pollTTL)
        }
        let soc = (41 + 7 * working + 3 * wave).rounded()
        let fan = soc >= 60 ? (2300 + (soc - 60) * 180).rounded() : 0
        return [
            reading(.cpuLoad, .amount(percent(0.07 + 0.12 * working + 0.03 * wave))),
            reading(.gpuLoad, .amount(percent(0.04 + 0.03 * working))),
            reading(.systemPower, .amount((7 + 9 * working + 2 * wave).rounded())),
            reading(.thermalState, .text((4200..<4800).contains(t) ? "fair" : "nominal")),
            reading(.memoryPressure, .text((7800..<8400).contains(t) ? "warning" : "normal")),
            reading(.memoryTotal, .amount(24 * gigabyte)),
            reading(.memoryUsed, .amount((14.2 + 0.8 * working) * gigabyte)),
            reading(.memoryWired, .amount(3.1 * gigabyte)),
            reading(.memoryCompressed, .amount((1.4 + 0.3 * working) * gigabyte)),
            reading(.swapUsed, .amount(0.9 * gigabyte)),
            reading(.diskFree, .amount((33_000 - (t / 60).rounded(.down)) * 1_000_000)),
            reading(.diskRead, .amount((0.4 + 2.5 * working).rounded() * 1_000_000)),
            reading(.diskWrite, .amount((0.2 + 1.5 * working).rounded() * 1_000_000)),
            reading(.networkIn, .amount((0.3 + 0.6 * working).rounded() * 100_000)),
            reading(.networkOut, .amount((0.1 + 0.2 * working).rounded() * 100_000)),
            reading(.socTemperature, .amount(soc)),
            reading(.ssdTemperature, .amount(33)),
            reading(.batteryTemperature, .amount(30)),
            reading(.fan1Speed, .amount(fan)),
            reading(.fan2Speed, .amount(fan)),
        ]
    }

    /// The plan's usage, as the status line reports it: the five-hour window fills through
    /// each window to 88% and starts again; the week creeps from 62% to 75% over the day.
    /// In whole points, as Claude Code's figures move.
    func quota(at moment: Date, day t: TimeInterval) -> [Reading] {
        let window: TimeInterval = 5 * 3600
        let into = t.truncatingRemainder(dividingBy: window)
        let sessionReset = moment.addingTimeInterval(window - into)
        let weekReset = start.addingTimeInterval(3 * 86_400 + 4 * 3600)
        func points(_ share: Double) -> Double { (share * 100).rounded(.down) / 100 }
        return [
            Reading(
                .machine, .quotaSession, .amount(points(0.08 + 0.8 * into / window)), at: moment,
                ttl: sessionReset.timeIntervalSince(moment)),
            Reading(
                .machine, .quotaSessionResets, .time(sessionReset), at: moment,
                ttl: sessionReset.timeIntervalSince(moment)),
            Reading(
                .machine, .quotaWeek, .amount(points(0.62 + 0.13 * t / Self.length)), at: moment,
                ttl: weekReset.timeIntervalSince(moment)),
            Reading(
                .machine, .quotaWeekResets, .time(weekReset), at: moment,
                ttl: weekReset.timeIntervalSince(moment)),
        ]
    }
}

// MARK: - One simulated session

struct SimSession: Sendable {

    enum Phase: Sendable, Equatable {
        case notStarted
        case idle(answerAt: TimeInterval)
        case working(until: TimeInterval, since: TimeInterval)
        case done(since: TimeInterval, answerAt: TimeInterval, notified: Bool)
        case ended
    }

    var key: SessionKey
    let name: String
    let cwd: String
    let title: String
    let kind: String
    let model: String
    let billed: String
    let version: String
    let startsAt: TimeInterval
    let endsAt: TimeInterval
    var effort: String
    var permission: String
    /// A background job: blocks at the first time, is answered at the second.
    var blocked: ClosedRange<TimeInterval>?
    var compactsAt: TimeInterval?
    var costRestartsAt: TimeInterval?
    var effortChange: (at: TimeInterval, to: String)?
    /// Remote Control on for this stretch of the day, and off either side of it.
    var remote: ClosedRange<TimeInterval>?

    var phase = Phase.notStarted
    var pid: Int
    var context = 24_000
    var window: Int { billed.contains("[1m]") ? 1_000_000 : 200_000 }
    var input = 0
    var output = 0
    var thinking = 0
    var cacheRead = 0
    var cacheWritten = 0
    var tools = 0
    var mix: [String: Int] = [:]
    var queue = 0
    var cost = 0.0
    var added = 0
    var removed = 0
    var apiSeconds = 0.0
    var toolSeconds = 0.0
    var lastTurn: TimeInterval?
    var turnMessages: Int?
    var compactedAt: Date?

    var isRunning: Bool {
        switch phase {
        case .notStarted, .ended: false
        default: true
        }
    }

    var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    mutating func advance(
        to t: TimeInterval, at moment: Date, rng: inout SplitMix, into out: inout [Reading]
    ) {
        let subject = Subject.session(key)
        func hook(_ field: Field, _ value: Value = .event, ttl: TimeInterval) {
            out.append(Reading(subject, field, value, at: moment, ttl: ttl))
        }

        if phase == .notStarted {
            guard t >= startsAt else { return }
            hook(.sessionStarted, ttl: TTL.sessionStarted)
            phase = .idle(answerAt: t + 20)
            return
        }
        if phase == .ended { return }
        if t >= endsAt {
            if isWorking { hook(.turnDone, ttl: TTL.turnDone) }
            hook(.sessionEnded, ttl: TTL.instant)
            phase = .ended
            return
        }

        if let change = effortChange, t >= change.at { effort = change.to }

        if let blocked, kind == "background" {
            if t == blocked.lowerBound { hook(.turnDone, ttl: TTL.turnDone) }
            if t == blocked.upperBound { hook(.promptSubmitted, ttl: TTL.instant) }
        }

        if let at = compactsAt, t == at {
            hook(.preCompact, ttl: TTL.preCompact)
        }
        if let at = compactsAt, t == at + 30 {
            compactedAt = moment
            context = window * 18 / 100
        }
        if let at = costRestartsAt, t == at { cost = 0 }

        switch phase {
        case .idle(let answerAt):
            guard t >= answerAt else { return }
            hook(.promptSubmitted, ttl: TTL.instant)
            queue = Int(rng.next() % 3)
            phase = .working(until: t + 60 + Double(rng.next() % 540), since: t)

        case .working(let until, let since):
            let produced = 80 + Int(rng.next() % 820)
            output += produced
            thinking += produced * 2 / 5
            input += Int(rng.next() % 120)
            cacheRead += 40_000 + Int(rng.next() % 90_000)
            cacheWritten += Int(rng.next() % 1_500)
            context = min(window, context + produced * 3 / 5)
            cost += Double(produced) * 0.000_02
            apiSeconds += 1.3
            if rng.next() % 4 == 0 {
                let tool = ["Bash", "Read", "Edit", "Grep"][Int(rng.next() % 4)]
                tools += 1
                mix[tool, default: 0] += 1
                toolSeconds += 0.6
                hook(.toolUsed, .text(tool), ttl: TTL.instant)
                if tool == "Edit" {
                    added += Int(rng.next() % 40)
                    removed += Int(rng.next() % 4)
                }
            }
            if rng.next() % 40 == 0 {
                hook(.subagentActivity, ttl: TTL.subagentActivity)
                if rng.next() % 2 == 0 { hook(.agentDone, ttl: TTL.agentDone) }
            }
            guard t >= until else { return }
            hook(.turnDone, ttl: TTL.turnDone)
            lastTurn = t - since
            turnMessages = 4 + Int(rng.next() % 30)
            queue = max(0, queue - 1)
            phase = .done(since: t, answerAt: t + 30 + Double(rng.next() % 870), notified: false)

        case .done(let since, let answerAt, let notified):
            // Claude Code notifies after a minute of waiting on the operator.
            if !notified, t >= since + 60, kind == "interactive" {
                hook(.waiting, ttl: TTL.waiting)
                phase = .done(since: since, answerAt: answerAt, notified: true)
            }
            guard t >= answerAt else { return }
            hook(.promptSubmitted, ttl: TTL.instant)
            phase = .working(until: t + 60 + Double(rng.next() % 540), since: t)

        case .notStarted, .ended:
            return
        }
    }

    /// What the agents poll, the transcript tail, the checkpoint and the jobs file report.
    func polled(at moment: Date, day t: TimeInterval) -> [Reading] {
        let subject = Subject.session(key)
        var out: [Reading] = []
        func add(_ field: Field, _ value: Value, ttl: TimeInterval = FakeDay.pollTTL) {
            out.append(Reading(subject, field, value, at: moment, ttl: ttl))
        }
        let started = moment.addingTimeInterval(startsAt - t)

        add(.name, .text(name))
        add(.cwd, .text(cwd))
        add(.startedAt, .time(started))
        add(.kind, .text(kind))
        add(.pid, .count(pid))
        add(.version, .text(version))
        add(.status, .text(isWorking ? "busy" : "idle"))

        add(.model, .text(model))
        add(.serviceTier, .text("standard"))
        add(.effort, .text(effort))
        add(.permissionMode, .text(permission))
        add(.mode, .text("normal"))
        add(.aiTitle, .text(title))
        add(.gitBranch, .text("main"))
        add(.lastPrompt, .text("carry on"))
        add(.contextUsed, .count(context))
        add(.inputTokens, .count(input))
        add(.outputTokens, .count(output))
        add(.thinkingTokens, .count(thinking))
        add(.cacheReadTokens, .count(cacheRead))
        add(.cacheCreationTokens, .count(cacheWritten))
        add(.queueDepth, .count(queue))
        add(.toolCalls, .count(tools))
        add(.toolMix, .tally(mix))
        if let lastTurn { add(.turnDuration, .seconds(lastTurn)) }
        if let turnMessages { add(.turnMessages, .count(turnMessages)) }
        if let compactedAt { add(.compactBoundary, .time(compactedAt)) }
        if let remote { add(.remoteControl, .flag(remote.contains(t))) }
        // What its processes cost the Mac; a background job has none of its own.
        if kind != "background" {
            let gigabyte = 1_073_741_824.0
            add(.processCPU, .amount(isWorking ? Double(4 + pid % 5) / 100 : 0))
            add(.processMemory, .amount(Double(4 + pid % 5) / 10 * gigabyte))
        }

        let checkpoint = FakeDay.checkpointTTL
        add(.costUSD, .amount(cost), ttl: checkpoint)
        add(.linesAdded, .count(added), ttl: checkpoint)
        add(.linesRemoved, .count(removed), ttl: checkpoint)
        add(.totalDuration, .seconds(max(1, apiSeconds + toolSeconds) * 1.6), ttl: checkpoint)
        add(.apiDuration, .seconds(apiSeconds), ttl: checkpoint)
        add(.toolDuration, .seconds(toolSeconds), ttl: checkpoint)
        add(.unknownModelCost, .flag(!model.contains("claude")), ttl: checkpoint)
        add(.contextWindow, .count(window), ttl: checkpoint)
        add(.modelUsage, .lines(["\(billed) IN \(input) OUT \(output)"]), ttl: checkpoint)

        if kind == "background" {
            add(.jobState, .text("working"))
            add(.jobName, .text(title))
            add(.jobBackend, .text("daemon"))
            add(.jobDetail, .text("reading the markdown"))
            if let blocked, t >= blocked.lowerBound, t < blocked.upperBound {
                add(.jobTempo, .text("blocked"))
                add(.jobNeeds, .text("send a prompt to start"))
            }
        }
        return out
    }

    static func cast() -> [SimSession] {
        [
            SimSession(
                key: "5d2c-familyhub", name: "familyhub-3",
                cwd: "/Users/operator/Projects/familyhub",
                title: "FamilyHub auth", kind: "interactive", model: "claude-opus-5-5",
                billed: "claude-opus-5-5[1m]", version: "2.1.280", startsAt: 0, endsAt: 9 * 3600,
                effort: "xhigh", permission: "auto", compactsAt: 4200, costRestartsAt: 7800,
                pid: 40_101),
            SimSession(
                key: "8e1f-tax", name: "tax-1", cwd: "/Users/operator/Projects/tax",
                title: "Tax return reply", kind: "interactive", model: "claude-sonnet-5",
                billed: "claude-sonnet-5", version: "2.1.280", startsAt: 600, endsAt: 5400,
                effort: "medium", permission: "acceptEdits", remote: 900...4500, pid: 40_202),
            SimSession(
                key: "00fb-review", name: "Review root project markdown files",
                cwd: "/Users/operator/Projects/pk4", title: "Review root project markdown files",
                kind: "background", model: "claude-haiku-4-5", billed: "claude-haiku-4-5",
                version: "2.1.280", startsAt: 1800, endsAt: 8 * 3600, effort: "low",
                permission: "default", blocked: 3600...4800, pid: 40_303),
            SimSession(
                key: "c3a9-pk4", name: "pk4-2", cwd: "/Users/operator/Projects/pk4",
                title: "PK-4 console logic", kind: "interactive", model: "claude-sonnet-5",
                billed: "claude-sonnet-5", version: "2.1.280", startsAt: 2400,
                endsAt: 10 * 3600 - 60,
                effort: "high", permission: "plan", effortChange: (8400, "max"), pid: 40_404),
            SimSession(
                key: "f7b0-fifth", name: "notes-1", cwd: "/Users/operator/Notes",
                title: "Weekly notes", kind: "interactive", model: "claude-fable-5-1",
                billed: "claude-fable-5-1", version: "2.1.281", startsAt: 3000, endsAt: 7 * 3600,
                effort: "high", permission: "dontAsk", pid: 40_505),
        ]
    }
}

// MARK: - Deterministic randomness

/// SplitMix64: small, fast, and the same numbers on every machine.
struct SplitMix: Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
