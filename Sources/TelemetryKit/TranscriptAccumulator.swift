import Foundation

/// Reads a transcript one record at a time and keeps the newest of everything the console
/// shows.
///
/// Pure: it never touches the file system. The tail that feeds it lines is a separate
/// concern, so this can be tested on a handful of records instead of a 26 MB file.
///
/// Nothing in a transcript is an API. Every field is optional, a record this build does not
/// recognise is skipped, and a malformed line costs that line only.
public struct TranscriptAccumulator: Sendable, Equatable {

    /// The id actually answering, from the newest assistant record. Never sizes the window:
    /// it says `claude-opus-5` when the session is really `claude-opus-5[1m]`.
    public private(set) var model: String?
    public private(set) var serviceTier: String?
    public private(set) var effort: String?
    /// Ultracode is xhigh effort with workflows standing by. The records say `xhigh`; the
    /// session's `ultra_effort_enter` and `_exit` markers say which it is.
    public private(set) var ultracode = false
    public private(set) var permissionMode: String?
    public private(set) var mode: String?
    public private(set) var aiTitle: String?
    public private(set) var lastPrompt: String?
    public private(set) var gitBranch: String?
    /// Remote Control, from the session's `bridge-session` record: written with the
    /// bridge's id while it is on, again and again, and once more with an empty id when it
    /// is turned off. `nil` until one turns up. Only whether the id is empty is kept.
    public private(set) var remoteControl: Bool?

    /// Everything occupying the window on the last turn: fresh input, cache writes and
    /// cache reads.
    public private(set) var contextUsed: Int?
    /// Fresh input only. Cache reads are the same tokens shown to the model again.
    public private(set) var inputTokens = 0
    public private(set) var outputTokens = 0
    public private(set) var thinkingTokens = 0
    public private(set) var cacheReadTokens = 0
    public private(set) var cacheCreationTokens = 0

    public private(set) var queueDepth = 0
    public private(set) var toolCalls = 0
    public private(set) var toolMix: [String: Int] = [:]

    public private(set) var turnDuration: TimeInterval?
    public private(set) var turnMessages: Int?
    public private(set) var compactedAt: Date?
    /// A subagent's record, when one turns up in this file. They normally live in their own
    /// files under `subagents/`, so the tail watches that folder too.
    public private(set) var lastSidechainAt: Date?

    public private(set) var checkpoint: CostCheckpoint?

    /// The model id that sizes the context window: the newest of the session's model
    /// identity record and its checkpoint's billed model. Both carry the `[1m]` suffix the
    /// assistant record leaves off. The identity record is written when a session starts
    /// and again on a model switch, so the window is known long before the first
    /// checkpoint — which in a session that has not compacted may never come.
    public private(set) var windowModel: String?

    /// 1M for the long-context variants, 200K otherwise; `nil` until a record names the
    /// model. Never guessed from the assistant record.
    public var contextWindow: Int? {
        windowModel.map { $0.contains("[1m]") ? 1_000_000 : 200_000 }
    }

    /// One API request is written as several assistant records — a text block and each
    /// tool call are separate lines — and every one repeats that request's usage. Counting
    /// per record inflated the totals by 2.4×.
    private var countedRequests: Set<String> = []
    private var countedTools: Set<String> = []
    /// Records of a kind this build reads. Until one arrives the file says nothing, and
    /// reporting its zeroed counters would claim a reading nobody took.
    private var recognised = 0

    private static let known: Set<String> = [
        "assistant", "cost-state", "permission-mode", "mode", "ai-title", "last-prompt",
        "queue-operation", "system", "bridge-session",
    ]

    public init() {}

    /// True once anything the console can show has been read.
    public var hasReading: Bool { recognised > 0 }

    // MARK: - Reading records

    /// Records arrive oldest first and the newest of each kind wins.
    public mutating func consume(_ line: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        else { return }

        // A subagent's work is not the session's own: it is excluded from every counter.
        if json["isSidechain"] as? Bool == true {
            lastSidechainAt = Self.timestamp(json["timestamp"]) ?? lastSidechainAt
            return
        }

        if let branch = json["gitBranch"] as? String, !branch.isEmpty { gitBranch = branch }

        if let type = json["type"] as? String, Self.known.contains(type) { recognised += 1 }

        switch json["type"] as? String {
        case "assistant": consumeAssistant(json)
        case "cost-state":
            let cost = CostCheckpoint(json: json)
            checkpoint = cost
            windowModel = cost.billedModel ?? windowModel
        case "attachment":
            guard let attachment = json["attachment"] as? [String: Any] else { return }
            switch attachment["type"] as? String {
            case "ultra_effort_enter":
                recognised += 1
                ultracode = true
                return
            case "ultra_effort_exit":
                recognised += 1
                ultracode = false
                return
            default: break
            }
            guard attachment["type"] as? String == "model",
                let identity = attachment["identity"] as? [String: Any],
                let id = identity["modelId"] as? String, !id.isEmpty
            else { return }
            recognised += 1
            windowModel = id
        case "permission-mode": permissionMode = json["permissionMode"] as? String ?? permissionMode
        case "mode": mode = json["mode"] as? String ?? mode
        case "ai-title": aiTitle = json["aiTitle"] as? String ?? aiTitle
        case "last-prompt": lastPrompt = json["lastPrompt"] as? String ?? lastPrompt
        case "bridge-session":
            guard let bridge = json["bridgeSessionId"] as? String else { return }
            remoteControl = !bridge.isEmpty
        case "queue-operation":
            switch json["operation"] as? String {
            case "enqueue": queueDepth += 1
            case "dequeue", "remove": queueDepth = max(0, queueDepth - 1)
            default: break
            }
        case "system":
            switch json["subtype"] as? String {
            case "turn_duration":
                if let milliseconds = json["durationMs"] as? Double {
                    turnDuration = milliseconds / 1000
                }
                turnMessages = json["messageCount"] as? Int ?? turnMessages
            case "compact_boundary":
                compactedAt = Self.timestamp(json["timestamp"]) ?? compactedAt
            case "bridge_status":
                // "/remote-control is active", written as it comes on.
                remoteControl = true
            default:
                break
            }
        default:
            break
        }
    }

    private mutating func consumeAssistant(_ json: [String: Any]) {
        guard let message = json["message"] as? [String: Any] else { return }

        // A synthetic record is Claude Code talking, not a model: an error, an interruption.
        if let id = message["model"] as? String, id != "<synthetic>" { model = id }
        if let level = json["effort"] as? String { effort = level }

        for block in message["content"] as? [[String: Any]] ?? [] {
            guard block["type"] as? String == "tool_use" else { continue }
            let id = block["id"] as? String ?? UUID().uuidString
            guard countedTools.insert(id).inserted else { continue }
            toolCalls += 1
            if let name = block["name"] as? String { toolMix[name, default: 0] += 1 }
        }

        guard let usage = message["usage"] as? [String: Any] else { return }
        let fresh = usage["input_tokens"] as? Int ?? 0
        let written = usage["cache_creation_input_tokens"] as? Int ?? 0
        let read = usage["cache_read_input_tokens"] as? Int ?? 0
        contextUsed = fresh + written + read
        if let tier = usage["service_tier"] as? String { serviceTier = tier }

        let request =
            (json["requestId"] as? String) ?? (message["id"] as? String)
            ?? (json["uuid"] as? String)
        if let request, !countedRequests.insert(request).inserted { return }

        inputTokens += fresh
        cacheCreationTokens += written
        cacheReadTokens += read
        outputTokens += usage["output_tokens"] as? Int ?? 0
        let details = usage["output_tokens_details"] as? [String: Any]
        thinkingTokens += details?["thinking_tokens"] as? Int ?? 0
    }

    // MARK: - Readings

    /// What this transcript says right now, as readings about `key`.
    public func readings(
        for key: SessionKey, at moment: Date, ttl: TimeInterval
    ) -> [Reading] {
        let subject = Subject.session(key)
        var out: [Reading] = []
        func add(_ field: Field, _ value: Value?) {
            if let value { out.append(Reading(subject, field, value, at: moment, ttl: ttl)) }
        }

        add(.model, model.map(Value.text))
        add(.serviceTier, serviceTier.map(Value.text))
        add(.effort, (ultracode ? "ultracode" : effort).map(Value.text))
        add(.permissionMode, permissionMode.map(Value.text))
        add(.mode, mode.map(Value.text))
        add(.aiTitle, aiTitle.map(Value.text))
        add(.lastPrompt, lastPrompt.map(Value.text))
        add(.gitBranch, gitBranch.map(Value.text))
        add(.remoteControl, remoteControl.map(Value.flag))
        add(.contextUsed, contextUsed.map(Value.count))
        add(.inputTokens, .count(inputTokens))
        add(.outputTokens, .count(outputTokens))
        add(.thinkingTokens, .count(thinkingTokens))
        add(.cacheReadTokens, .count(cacheReadTokens))
        add(.cacheCreationTokens, .count(cacheCreationTokens))
        add(.queueDepth, .count(queueDepth))
        add(.toolCalls, .count(toolCalls))
        add(.toolMix, .tally(toolMix))
        add(.turnDuration, turnDuration.map(Value.seconds))
        add(.turnMessages, turnMessages.map(Value.count))
        add(.compactBoundary, compactedAt.map(Value.time))
        add(.contextWindow, contextWindow.map(Value.count))
        return out
    }

    // MARK: - Timestamps

    static func timestamp(_ raw: Any?) -> Date? {
        guard let string = raw as? String else { return nil }
        return fractional.date(from: string) ?? whole.date(from: string)
    }

    // ISO8601DateFormatter is documented as thread safe.
    private nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let whole = ISO8601DateFormatter()
}

/// A session's `cost-state` record.
///
/// It is a checkpoint, written when a session starts, compacts and exits, so the figures
/// are the newest ones on disk rather than the figures this second.
public struct CostCheckpoint: Sendable, Equatable {
    public var totalCostUSD: Double?
    public var linesAdded: Int?
    public var linesRemoved: Int?
    public var totalDuration: TimeInterval?
    public var apiDuration: TimeInterval?
    public var toolDuration: TimeInterval?
    public var unknownModelCost: Bool?
    /// The id cost is billed against. Unlike the assistant record's model it carries the
    /// `[1m]` suffix, so it is the one that sizes the context window.
    public var billedModel: String?
    /// One line per model, for the text log.
    public var modelUsage: [String] = []

    public init() {}

    init(json: [String: Any]) {
        totalCostUSD = json["totalCostUSD"] as? Double
        linesAdded = json["totalLinesAdded"] as? Int
        linesRemoved = json["totalLinesRemoved"] as? Int
        totalDuration = (json["totalDuration"] as? Double).map { $0 / 1000 }
        apiDuration = (json["totalAPIDuration"] as? Double).map { $0 / 1000 }
        toolDuration = (json["totalToolDuration"] as? Double).map { $0 / 1000 }
        unknownModelCost = json["hasUnknownModelCost"] as? Bool

        let usage = json["modelUsage"] as? [String: Any] ?? [:]
        var busiest = -1
        for (model, entry) in usage.sorted(by: { $0.key < $1.key }) {
            guard let entry = entry as? [String: Any] else { continue }
            let output = entry["outputTokens"] as? Int ?? 0
            // A session also bills a little Haiku for side work; the model whose window
            // matters is the one doing the talking.
            if output > busiest {
                busiest = output
                billedModel = model
            }
            let input = entry["inputTokens"] as? Int ?? 0
            let cost = entry["costUSD"] as? Double
            modelUsage.append(
                "\(model) IN \(input) OUT \(output)"
                    + (cost.map { String(format: " COST %.2f", $0) } ?? ""))
        }
    }

    /// 1M for the long-context variants, 200K otherwise. `nil` until a checkpoint names a
    /// model: the window is never guessed from the assistant record.
    public var contextWindow: Int? {
        billedModel.map { $0.contains("[1m]") ? 1_000_000 : 200_000 }
    }

    public func readings(
        for key: SessionKey, at moment: Date, ttl: TimeInterval
    ) -> [Reading] {
        let subject = Subject.session(key)
        var out: [Reading] = []
        func add(_ field: Field, _ value: Value?) {
            if let value { out.append(Reading(subject, field, value, at: moment, ttl: ttl)) }
        }
        add(.costUSD, totalCostUSD.map(Value.amount))
        add(.linesAdded, linesAdded.map(Value.count))
        add(.linesRemoved, linesRemoved.map(Value.count))
        add(.totalDuration, totalDuration.map(Value.seconds))
        add(.apiDuration, apiDuration.map(Value.seconds))
        add(.toolDuration, toolDuration.map(Value.seconds))
        add(.unknownModelCost, unknownModelCost.map(Value.flag))
        if !modelUsage.isEmpty { add(.modelUsage, .lines(modelUsage)) }
        return out
    }
}
