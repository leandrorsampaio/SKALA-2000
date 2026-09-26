import Foundation

/// Turns one Claude Code hook's input into readings.
///
/// The hooks pipe their input unchanged to `POST /v1/events/claude`, so everything here
/// is read from the shape Claude Code 2.1.280 was seen to send: `session_id` and
/// `hook_event_name` on every event, `agent_id` when a subagent is the one acting. Hooks
/// report moments rather than states, so each reading carries the lifetime the console
/// gives that kind of moment.
///
/// Pure, and in both builds: a hook reaches the local server even under the sandbox.
public enum ClaudeHooks {

    /// The events the installer registers. Anything else that arrives is ignored.
    public static let events = [
        "SessionStart", "SessionEnd", "UserPromptSubmit", "Stop", "SubagentStart",
        "SubagentStop", "Notification", "PermissionRequest", "PostToolUse",
        "PostToolUseFailure", "PreCompact", "PostCompact",
    ]

    /// Notifications that mean the operator is needed. The others — a login that
    /// succeeded, a background agent that finished, quota housekeeping — light nothing.
    public static let waitingKinds: Set<String> = [
        "permission_prompt", "idle_prompt", "elicitation_dialog", "elicitation_url_dialog",
        "agent_needs_input",
    ]

    /// Readings for one hook's input, or none when it says nothing the console shows or
    /// cannot be read. The prompt text of `UserPromptSubmit` is looked at only to tell a
    /// person from a machine; it is never kept.
    public static func readings(from body: Data, at moment: Date) -> [Reading] {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let id = json["session_id"] as? String, !id.isEmpty,
            let event = json["hook_event_name"] as? String
        else { return [] }

        let subject = Subject.session(SessionKey(id))
        // A subagent's own tool calls are not the session's: they neither answer the
        // operator nor count toward the session's tools.
        let fromSubagent = (json["agent_id"] as? String).map { !$0.isEmpty } ?? false
        func reading(_ field: Field, _ value: Value = .event, ttl: TimeInterval) -> [Reading] {
            [Reading(subject, field, value, at: moment, ttl: ttl)]
        }

        switch event {
        case "SessionStart":
            return reading(.sessionStarted, ttl: TTL.sessionStarted)
        case "SessionEnd":
            return reading(.sessionEnded, ttl: TTL.instant)
        case "UserPromptSubmit":
            // A background task finishing is delivered as a prompt Claude Code writes
            // itself. It is not the operator answering, so it clears nothing.
            let prompt = json["prompt"] as? String ?? ""
            if prompt.hasPrefix("<task-notification>") { return [] }
            return reading(.promptSubmitted, ttl: TTL.instant)
        case "Stop":
            return reading(.turnDone, ttl: TTL.turnDone)
        case "SubagentStart":
            return reading(.subagentActivity, ttl: TTL.subagentActivity)
        case "SubagentStop":
            return reading(.agentDone, ttl: TTL.agentDone)
        case "Notification":
            // Older builds sent no type; then every notification was a wait.
            guard let kind = json["notification_type"] as? String else {
                return reading(.waiting, ttl: TTL.waiting)
            }
            return waitingKinds.contains(kind) ? reading(.waiting, ttl: TTL.waiting) : []
        case "PermissionRequest":
            // Whoever asks — the session or one of its subagents — the operator must act.
            return reading(.waiting, ttl: TTL.waiting)
        case "PostToolUse", "PostToolUseFailure":
            guard !fromSubagent else { return [] }
            return reading(.toolUsed, .text(json["tool_name"] as? String ?? "?"), ttl: TTL.instant)
        case "PreCompact":
            return reading(.preCompact, ttl: TTL.preCompact)
        case "PostCompact":
            // The same thing the transcript's `compact_boundary` says, sooner.
            return reading(.compactBoundary, .time(moment), ttl: TTL.preCompact)
        default:
            return []
        }
    }
}
