import Foundation
import Testing

@testable import TelemetryKit

/// Built on hand-written records shaped like Claude Code 2.1.280's, never on the real
/// `~/.claude`: a test that passes only on the machine that wrote it is not a test.
@Suite struct TranscriptAccumulatorTests {

    func read(_ lines: [String]) -> TranscriptAccumulator {
        var accumulator = TranscriptAccumulator()
        lines.forEach { accumulator.consume(Data($0.utf8)) }
        return accumulator
    }

    func assistant(
        request: String, model: String = "claude-opus-5", output: Int, thinking: Int = 0,
        input: Int = 0, read: Int = 0, written: Int = 0, tool: (id: String, name: String)? = nil,
        sidechain: Bool = false
    ) -> String {
        let content =
            tool.map { #"[{"type":"tool_use","id":""# + $0.id + #"","name":""# + $0.name + #""}]"# }
            ?? #"[{"type":"text"}]"#
        return #"{"type":"assistant","isSidechain":"# + String(sidechain)
            + #","requestId":""# + request
            + #"","effort":"xhigh","gitBranch":"main","message":{"model":""#
            + model + #"","content":"# + content + #","usage":{"input_tokens":"# + String(input)
            + #","cache_creation_input_tokens":"# + String(written)
            + #","cache_read_input_tokens":"# + String(read) + #","output_tokens":"#
            + String(output) + #","output_tokens_details":{"thinking_tokens":"#
            + String(thinking) + #"},"service_tier":"standard"}}}"#
    }

    /// One request is written as several records — text, then each tool call — and every
    /// one repeats that request's usage. Counting per record inflated totals by 2.4×.
    @Test func cumulativeFiguresCountEachRequestOnce() {
        let accumulator = read([
            assistant(
                request: "req_a", output: 100, thinking: 40, input: 5, read: 900, written: 100),
            assistant(
                request: "req_a", output: 100, thinking: 40, input: 5, read: 900, written: 100,
                tool: ("toolu_1", "Bash")),
            assistant(
                request: "req_a", output: 100, thinking: 40, input: 5, read: 900, written: 100,
                tool: ("toolu_2", "Read")),
            assistant(request: "req_b", output: 30, thinking: 10, input: 2, read: 1000, written: 5),
        ])

        #expect(accumulator.outputTokens == 130)
        #expect(accumulator.thinkingTokens == 50)
        #expect(accumulator.inputTokens == 7)
        #expect(accumulator.cacheReadTokens == 1900)
        #expect(accumulator.cacheCreationTokens == 105)
        // The window holds what the *last* request sent, not a sum.
        #expect(accumulator.contextUsed == 1007)
        #expect(accumulator.toolCalls == 2)
        #expect(accumulator.toolMix == ["Bash": 1, "Read": 1])
        #expect(accumulator.effort == "xhigh")
        #expect(accumulator.serviceTier == "standard")
        #expect(accumulator.gitBranch == "main")
    }

    /// The assistant record says `claude-opus-5`; only `cost-state` says `[1m]`. Sizing the
    /// window off the assistant record shows an 80%-full gauge that should say 20%.
    @Test func theWindowComesFromTheBilledModelInCostState() throws {
        let checkpoint =
            #"{"type":"cost-state","totalCostUSD":169.49,"totalLinesAdded":1366,"totalLinesRemoved":31,"totalDuration":4000,"totalAPIDuration":2000,"totalToolDuration":1000,"hasUnknownModelCost":false,"modelUsage":{"claude-haiku-4-5-20251001":{"inputTokens":10,"outputTokens":50,"costUSD":0.01},"claude-opus-5[1m]":{"inputTokens":5130,"outputTokens":783272,"costUSD":169.48}}}"#
        let accumulator = read([assistant(request: "r", output: 1), checkpoint])

        #expect(accumulator.model == "claude-opus-5")
        let cost = try #require(accumulator.checkpoint)
        #expect(cost.billedModel == "claude-opus-5[1m]")
        #expect(cost.contextWindow == 1_000_000)
        #expect(cost.totalCostUSD == 169.49)
        #expect(cost.linesAdded == 1366)
        #expect(cost.totalDuration == 4)
        #expect(cost.apiDuration == 2)
        #expect(cost.modelUsage.count == 2)
    }

    @Test func withNothingNamingTheModelThereIsNoWindowRatherThanAGuess() {
        let accumulator = read([assistant(request: "r", model: "claude-opus-5", output: 1)])
        #expect(accumulator.contextWindow == nil)
        let readings = accumulator.readings(for: "s", at: Date(), ttl: 6)
        #expect(!readings.contains { $0.field == .contextWindow })
    }

    static func identity(_ model: String) -> String {
        #"{"type":"attachment","attachment":{"type":"model","identity":{"modelId":""# + model
            + #"","marketingName":"x"}}}"#
    }

    /// Written when a session starts, so the window is known before any checkpoint.
    @Test func theModelIdentityRecordSizesTheWindowBeforeAnyCheckpoint() {
        let accumulator = read([
            Self.identity("claude-opus-5-5[1m]"),
            assistant(request: "r", model: "claude-opus-5-5", output: 1),
        ])
        #expect(accumulator.checkpoint == nil)
        #expect(accumulator.contextWindow == 1_000_000)
        let readings = accumulator.readings(for: "s", at: Date(), ttl: 6)
        #expect(readings.contains { $0.field == .contextWindow && $0.value == .count(1_000_000) })
    }

    /// Remote Control: the `bridge-session` record carries the bridge's id while it is on,
    /// and an empty one once it is turned off. Nothing is said until a record turns up.
    @Test func remoteControlFollowsTheBridgeRecord() {
        let on =
            #"{"type":"bridge-session","sessionId":"s","bridgeSessionId":"cse_01abc","lastSequenceNum":0}"#
        let off =
            #"{"type":"bridge-session","sessionId":"s","bridgeSessionId":"","lastSequenceNum":0}"#
        let active =
            #"{"type":"system","subtype":"bridge_status","content":"/remote-control is active","url":"https://claude.ai/code/x","timestamp":"2026-09-25T11:34:18.627Z"}"#
        #expect(read([assistant(request: "r", output: 1)]).remoteControl == nil)
        #expect(read([on]).remoteControl == true)
        #expect(read([active]).remoteControl == true)
        #expect(read([on, active, on, off]).remoteControl == false)
        #expect(read([on, active, on, off, on]).remoteControl == true)

        let readings = read([on, active]).readings(for: "s", at: Date(), ttl: 6)
        #expect(readings.contains { $0.field == .remoteControl && $0.value == .flag(true) })
        // Whether it is on, and nothing more: the bridge's id and its link go nowhere.
        #expect(
            !readings.contains {
                "\($0.value)".contains("cse_") || "\($0.value)".contains("claude.ai")
            })
    }

    /// After a `/model` switch the newer record wins, whichever kind it is.
    @Test func theNewestRecordNamingTheModelWins() {
        let checkpoint =
            #"{"type":"cost-state","modelUsage":{"claude-opus-5[1m]":{"outputTokens":10}}}"#
        #expect(read([Self.identity("claude-sonnet-5"), checkpoint]).contextWindow == 1_000_000)
        #expect(read([checkpoint, Self.identity("claude-sonnet-5")]).contextWindow == 200_000)
    }

    @Test func subagentRecordsAreLeftOutOfTheSessionsCounters() {
        let accumulator = read([
            assistant(request: "main", output: 10),
            assistant(request: "side", output: 9000, tool: ("toolu_9", "Bash"), sidechain: true),
        ])
        #expect(accumulator.outputTokens == 10)
        #expect(accumulator.toolCalls == 0)
    }

    @Test func theQueueCountsEnqueuesAgainstDequeuesAndRemovals() {
        let op = { (name: String) in #"{"type":"queue-operation","operation":""# + name + #""}"# }
        let accumulator = read([
            op("enqueue"), op("enqueue"), op("enqueue"), op("dequeue"), op("remove"), op("remove"),
            op("remove"), op("somethingNew"),
        ])
        #expect(accumulator.queueDepth == 0)
    }

    @Test func readsTheSmallRecords() throws {
        let accumulator = read([
            #"{"type":"permission-mode","permissionMode":"auto"}"#,
            #"{"type":"mode","mode":"normal"}"#,
            #"{"type":"ai-title","aiTitle":"Mac command center panel"}"#,
            #"{"type":"last-prompt","lastPrompt":"carry on"}"#,
            #"{"type":"system","subtype":"turn_duration","durationMs":125000,"messageCount":14}"#,
            #"{"type":"system","subtype":"compact_boundary","timestamp":"2026-09-25T10:00:00.250Z"}"#,
        ])
        #expect(accumulator.permissionMode == "auto")
        #expect(accumulator.mode == "normal")
        #expect(accumulator.aiTitle == "Mac command center panel")
        #expect(accumulator.lastPrompt == "carry on")
        #expect(accumulator.turnDuration == 125)
        #expect(accumulator.turnMessages == 14)
        let compacted = try #require(accumulator.compactedAt)
        #expect(abs(compacted.timeIntervalSince1970 - 1_790_330_400.25) < 0.001)
    }

    @Test func aSyntheticRecordDoesNotReplaceTheModel() {
        let accumulator = read([
            assistant(request: "a", model: "claude-opus-5-5", output: 1),
            assistant(request: "b", model: "<synthetic>", output: 0),
        ])
        #expect(accumulator.model == "claude-opus-5-5")
    }

    /// A record this build does not understand must cost one line, not the file.
    @Test func survivesLinesItCannotRead() {
        let accumulator = read([
            "not json at all",
            #"{"type":"assistant","message":"a string, not an object"}"#,
            #"{"type":"frame-link","path":"x"}"#,
            assistant(request: "ok", output: 5),
        ])
        #expect(accumulator.outputTokens == 5)
        #expect(accumulator.hasReading)
    }

    /// Ultracode's records say `xhigh`; its markers say ultracode, until it is left.
    @Test func ultracodeIsReadFromItsMarkers() {
        func effort(_ accumulator: TranscriptAccumulator) -> Value? {
            accumulator.readings(for: "a", at: Date(), ttl: 6).first { $0.field == .effort }?.value
        }
        let enter =
            #"{"type":"attachment","attachment":{"type":"ultra_effort_enter","reminderType":"full"}}"#
        let exit = #"{"type":"attachment","attachment":{"type":"ultra_effort_exit"}}"#

        #expect(effort(read([assistant(request: "r", output: 1)])) == .text("xhigh"))
        #expect(
            effort(read([enter, assistant(request: "r", output: 1)])) == .text("ultracode"))
        #expect(
            effort(read([enter, assistant(request: "r", output: 1), exit])) == .text("xhigh"))
    }

    @Test func readingsCarryTheSessionAndTheLifetime() {
        let accumulator = read([assistant(request: "r", output: 7)])
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        let readings = accumulator.readings(for: "abc", at: moment, ttl: 6)
        let output = readings.first { $0.field == .outputTokens }
        #expect(output?.subject == .session("abc"))
        #expect(output?.value == .count(7))
        #expect(output?.expiresAt == moment.addingTimeInterval(6))
        #expect(readings.allSatisfy { $0.value.kind == $0.field.kind })
    }
}
