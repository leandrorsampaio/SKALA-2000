import Foundation
import Testing

@testable import TelemetryKit

/// Shaped like the payloads Claude Code 2.1.280 actually sent: the same keys in the same
/// order, with made-up ids and text.
@Suite struct ClaudeHooksTests {

    let moment = Date(timeIntervalSince1970: 1_800_000_000)

    func event(_ name: String, _ extra: String = "", agent: Bool = false) -> Data {
        let subagent =
            agent ? #","agent_id":"ae4d83aa696053298","agent_type":"general-purpose""# : ""
        return Data(
            (#"{"session_id":"25adbe1d-0000","transcript_path":"/tmp/t.jsonl","cwd":"/tmp","prompt_id":"p1","permission_mode":"default""#
                + subagent + #","hook_event_name":""# + name + #"""# + extra + "}").utf8)
    }

    func fields(_ body: Data) -> [Field] {
        ClaudeHooks.readings(from: body, at: moment).map(\.field)
    }

    @Test func eachEventBecomesTheMomentTheConsoleShows() {
        #expect(fields(event("SessionStart", #","source":"startup""#)) == [.sessionStarted])
        #expect(fields(event("SessionEnd", #","reason":"other""#)) == [.sessionEnded])
        #expect(fields(event("UserPromptSubmit", #","prompt":"carry on""#)) == [.promptSubmitted])
        #expect(fields(event("Stop", #","stop_hook_active":false"#)) == [.turnDone])
        #expect(fields(event("SubagentStart", agent: true)) == [.subagentActivity])
        #expect(fields(event("SubagentStop", agent: true)) == [.agentDone])
        #expect(fields(event("PreCompact", #","trigger":"auto""#)) == [.preCompact])
        #expect(fields(event("PostCompact")) == [.compactBoundary])
        #expect(fields(event("PermissionRequest", #","tool_name":"Bash""#)) == [.waiting])
    }

    @Test func readingsCarryTheSessionAndTheirLifetimes() throws {
        let stop = try #require(ClaudeHooks.readings(from: event("Stop"), at: moment).first)
        #expect(stop.subject == .session("25adbe1d-0000"))
        #expect(stop.ttl == TTL.turnDone)
        #expect(stop.observedAt == moment)

        let waiting = try #require(
            ClaudeHooks.readings(
                from: event("Notification", #","notification_type":"permission_prompt""#),
                at: moment
            ).first)
        #expect(waiting.ttl == TTL.waiting)
    }

    /// A background task finishing comes back as a prompt Claude Code wrote itself.
    @Test func aPromptClaudeCodeWroteItselfClearsNothing() {
        let injected = event(
            "UserPromptSubmit", #","prompt":"<task-notification>\n<task-id>ae4d</task-id>""#)
        #expect(fields(injected).isEmpty)
    }

    @Test func onlyNotificationsThatNeedTheOperatorLightWaiting() {
        for kind in ["permission_prompt", "idle_prompt", "elicitation_dialog", "agent_needs_input"]
        {
            #expect(
                fields(event("Notification", #","notification_type":""# + kind + #"""#)) == [
                    .waiting
                ])
        }
        for kind in ["auth_success", "agent_completed", "quota_auto_resume_fired"] {
            #expect(
                fields(event("Notification", #","notification_type":""# + kind + #"""#)).isEmpty)
        }
        // An older build that sends no type: every notification was a wait.
        #expect(
            fields(event("Notification", #","message":"Claude needs your permission""#)) == [
                .waiting
            ])
    }

    /// A subagent's tools are not the session's: they neither answer the operator nor count.
    @Test func onlyTheMainAgentsToolsCount() throws {
        let main = event("PostToolUse", #","tool_name":"Bash","tool_input":{},"tool_response":{}"#)
        let reading = try #require(ClaudeHooks.readings(from: main, at: moment).first)
        #expect(reading.field == .toolUsed)
        #expect(reading.value == .text("Bash"))

        let failed = event("PostToolUseFailure", #","tool_name":"Edit""#)
        #expect(fields(failed) == [.toolUsed])

        let sub = event("PostToolUse", #","tool_name":"Bash""#, agent: true)
        #expect(fields(sub).isEmpty)
    }

    @Test func anythingElseSaysNothing() {
        #expect(fields(event("PreToolUse", #","tool_name":"Bash""#)).isEmpty)
        #expect(fields(event("StopFailure", #","error_type":"rate_limit""#)).isEmpty)
        #expect(fields(Data(#"{"hook_event_name":"Stop"}"#.utf8)).isEmpty)
        #expect(fields(Data("not json".utf8)).isEmpty)
        #expect(fields(Data()).isEmpty)
    }

    @Test func theInstallerRegistersExactlyTheEventsThisReads() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/claude-hooks.json")
        let json = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let hooks = try #require(json["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == Set(ClaudeHooks.events))
        for (event, groups) in hooks {
            let hook = try #require(
                ((groups as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first)
            #expect(hook["async"] as? Bool == true, "\(event) must never make Claude Code wait")
            #expect((hook["command"] as? String)?.contains("/v1/events/claude") == true)
        }
    }
}

@Suite struct MachineSourceTests {

    @Test func aBatteryDescriptionBecomesReadings() {
        let info: [String: Any] = [
            "Power Source State": "Battery Power", "Current Capacity": 15, "Max Capacity": 100,
            "Is Charging": false,
        ]
        let readings = MachineSource.readings(from: info, at: Date())
        #expect(readings.first { $0.field == .onMains }?.value == .flag(false))
        #expect(readings.first { $0.field == .batteryFraction }?.value == .amount(0.15))
        #expect(readings.first { $0.field == .charging }?.value == .flag(false))
    }

    @Test func mainsWithoutABatteryReportsNoCharge() {
        let readings = MachineSource.readings(from: ["Power Source State": "AC Power"], at: Date())
        #expect(readings.map(\.field) == [.onMains])
        #expect(readings.first?.value == .flag(true))
    }
}
