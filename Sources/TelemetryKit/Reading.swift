import Foundation

/// A Claude Code session, interactive or background, by its `sessionId`.
///
/// It is the join key between `claude agents --json`, the transcript, `cost-state` and the
/// hooks. It goes into the safety log and never onto the console.
public struct SessionKey: RawRepresentable, Hashable, Sendable, Codable, Comparable,
    ExpressibleByStringLiteral, CustomStringConvertible
{
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public var description: String { rawValue }

    /// Whether the id can name a file: letters, digits, `.`, `_` and `-`, and not `.` or
    /// `..`. Claude Code's ids always can; one that cannot, from a damaged record or a
    /// hook body, never becomes a path or a shell word.
    public var isPathSafe: Bool {
        !rawValue.isEmpty && rawValue != "." && rawValue != ".."
            && rawValue.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
                    || byte == 45 || byte == 46 || byte == 95
            }
    }

    public static func < (lhs: SessionKey, rhs: SessionKey) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Who a reading is about.
public enum Subject: Hashable, Sendable {
    case session(SessionKey)
    /// The Mac itself: power, display, sleep, and the list of running sessions.
    case machine
}

/// Everything a source can report. The names follow the telemetry inventory.
///
/// A field says what the value *means*; `kind` says what shape it must arrive in. A reading
/// whose value has the wrong shape is a mistyped field and costs its own instrument only.
public enum Field: String, Sendable, CaseIterable, Codable {

    // A · identity and presence
    /// Every session `claude agents --json` lists, on `.machine`. Absence from a roster is
    /// how a session is known to have ended; a roster that does not arrive is staleness.
    case roster
    case name, cwd, startedAt, kind, pid, version, gitBranch

    // B · what it is doing
    case status, aiTitle, permissionMode, mode, queueDepth, lastPrompt, toolCalls, toolMix
    /// A subagent wrote something. Lives 30 s, which is what SUBAGENT ACTIVE means.
    case subagentActivity

    // C · context and tokens
    case contextUsed, contextWindow
    case inputTokens, outputTokens, thinkingTokens, cacheReadTokens, cacheCreationTokens
    case model, serviceTier
    /// When the transcript's last `compact_boundary` was written.
    case compactBoundary

    // D · cost and effort
    case costUSD, modelUsage, effort, linesAdded, linesRemoved, unknownModelCost

    // E · timing
    case turnDuration, turnMessages, totalDuration, apiDuration, toolDuration

    // F · background agents
    case jobState, jobTempo, jobNeeds, jobDetail, jobName, jobBackend

    // G · hook events: moments, not states
    case waiting, turnDone, agentDone, promptSubmitted, toolUsed
    case sessionStarted, sessionEnded, preCompact

    // I · the Mac
    case batteryFraction, onMains, charging, displayAsleep, systemAsleep
    /// Mac Command Center's own Keep Awake modes, which FC1 and FC2 switch.
    case keepAwakeDisplayOn, keepAwakeDisplayOff

    public var kind: Value.Kind {
        switch self {
        case .roster: .keys
        case .name, .cwd, .kind, .version, .gitBranch, .status, .aiTitle, .permissionMode, .mode,
            .lastPrompt, .model, .serviceTier, .effort, .jobState, .jobTempo, .jobNeeds,
            .jobDetail, .jobName, .jobBackend, .toolUsed:
            .text
        case .pid, .queueDepth, .toolCalls, .contextUsed, .contextWindow, .inputTokens,
            .outputTokens, .thinkingTokens, .cacheReadTokens, .cacheCreationTokens, .linesAdded,
            .linesRemoved, .turnMessages:
            .count
        case .costUSD, .batteryFraction: .amount
        case .turnDuration, .totalDuration, .apiDuration, .toolDuration: .seconds
        case .startedAt, .compactBoundary: .time
        case .toolMix: .tally
        case .modelUsage: .lines
        case .unknownModelCost, .onMains, .charging, .displayAsleep, .systemAsleep,
            .keepAwakeDisplayOn, .keepAwakeDisplayOff:
            .flag
        case .subagentActivity, .waiting, .turnDone, .agentDone, .promptSubmitted,
            .sessionStarted, .sessionEnded, .preCompact:
            .event
        }
    }
}

/// A reading's payload.
public enum Value: Sendable, Equatable {
    case flag(Bool)
    case count(Int)
    case amount(Double)
    case seconds(TimeInterval)
    case text(String)
    case time(Date)
    /// Calls per tool name.
    case tally([String: Int])
    /// Pre-formatted lines for the text log, such as per-model usage.
    case lines([String])
    case keys([SessionKey])
    /// A moment with nothing to say beyond that it happened.
    case event

    public enum Kind: String, Sendable {
        case flag, count, amount, seconds, text, time, tally, lines, keys, event
    }

    public var kind: Kind {
        switch self {
        case .flag: .flag
        case .count: .count
        case .amount: .amount
        case .seconds: .seconds
        case .text: .text
        case .time: .time
        case .tally: .tally
        case .lines: .lines
        case .keys: .keys
        case .event: .event
        }
    }

    public var flag: Bool? {
        if case .flag(let value) = self { return value }
        return nil
    }

    public var count: Int? {
        if case .count(let value) = self { return value }
        return nil
    }

    public var amount: Double? {
        switch self {
        case .amount(let value): value
        case .count(let value): Double(value)
        default: nil
        }
    }

    public var seconds: TimeInterval? {
        if case .seconds(let value) = self { return value }
        return nil
    }

    public var text: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    public var time: Date? {
        if case .time(let value) = self { return value }
        return nil
    }

    public var tally: [String: Int]? {
        if case .tally(let value) = self { return value }
        return nil
    }

    public var lines: [String]? {
        if case .lines(let value) = self { return value }
        return nil
    }

    public var keys: [SessionKey]? {
        if case .keys(let value) = self { return value }
        return nil
    }
}

/// One thing a source observed, and how long it is to be believed.
///
/// This is the only thing a source emits. It says nothing about instruments: which window
/// a reading lights is the console's business.
public struct Reading: Sendable, Equatable {
    public var subject: Subject
    public var field: Field
    public var value: Value
    public var observedAt: Date
    /// Seconds from `observedAt`. A source that stops reporting stops lighting its lamp
    /// instead of lying until the next launch.
    public var ttl: TimeInterval

    public init(
        _ subject: Subject, _ field: Field, _ value: Value, at observedAt: Date,
        ttl: TimeInterval
    ) {
        self.subject = subject
        self.field = field
        self.value = value
        self.observedAt = observedAt
        self.ttl = max(0, ttl)
    }

    public var expiresAt: Date { observedAt.addingTimeInterval(ttl) }

    public func isFresh(at moment: Date) -> Bool { moment < expiresAt }
}

/// How long each kind of reading is believed. Sources use these; the console never guesses.
public enum TTL {
    /// A polled field is believed for three of its intervals, so one missed poll is not
    /// an outage but three are.
    public static func polled(every interval: TimeInterval) -> TimeInterval { 3 * interval }

    public static let waiting: TimeInterval = 30 * 60
    public static let turnDone: TimeInterval = 10 * 60
    public static let agentDone: TimeInterval = 10 * 60
    public static let preCompact: TimeInterval = 5 * 60
    public static let subagentActivity: TimeInterval = 30
    /// A session announced by the SessionStart hook, before the next poll confirms it.
    public static let sessionStarted: TimeInterval = 10
    /// An event that acts once, on arrival: a prompt submitted, a tool used.
    public static let instant: TimeInterval = 0
}

/// What one pass over the sources produced.
public struct TelemetryBatch: Sendable, Equatable {
    public var readings: [Reading]
    public var issues: [TelemetryIssue]

    public init(readings: [Reading] = [], issues: [TelemetryIssue] = []) {
        self.readings = readings
        self.issues = issues
    }
}

/// Something a source could not read. It goes to the safety log; it never reaches the
/// console except as the instrument it darkens.
public struct TelemetryIssue: Sendable, Equatable {
    public var source: String
    public var subject: Subject?
    public var field: Field?
    public var message: String
    public var observedAt: Date

    public init(
        source: String, subject: Subject? = nil, field: Field? = nil, message: String,
        at observedAt: Date
    ) {
        self.source = source
        self.subject = subject
        self.field = field
        self.message = message
        self.observedAt = observedAt
    }
}
