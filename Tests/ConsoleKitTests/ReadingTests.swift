import Foundation
import Testing

@testable import ConsoleKit
@testable import TelemetryKit

/// Time-to-live, defensive reads, and what panel B shows for the selected slot.
@MainActor
@Suite struct ReadingTests {

    @Test func aSlotThatStopsReportingGoesDarkAndRaisesDataStaleWhenSelected() {
        let bench = Bench()
        bench.feed(
            bench.poll(["a"], status: "busy")
                + [bench.reading("a", .contextUsed, .count(1234))])
        #expect(bench.lamp(.run, 1) == .on)
        #expect(bench.snap.nixie(PK4.contextUsed) == "00001234")

        // Nothing for longer than the poll's lifetime.
        bench.run(for: 7)
        #expect(bench.lamp(.run, 1) == .off)
        #expect(bench.lamp(.busy, 1) == .off)
        #expect(bench.lamp(PK4.warning(.stale)) == .flash)
        #expect(bench.snap.buzzer)
        // A stale number is never left standing.
        #expect(bench.snap.nixie(PK4.contextUsed) == "        ")
        // The slot is still held: stale is not the same as gone.
        #expect(bench.slot(of: "a") == 1)

        // Reporting again clears it.
        bench.feed(bench.poll(["a"]))
        #expect(bench.lamp(.run, 1) == .on)
        #expect(bench.lamp(PK4.warning(.stale)) == .off)
    }

    @Test func dataStaleIsOnlyForTheSelectedSlot() {
        let bench = Bench()
        bench.feed(bench.poll(["a"]))
        bench.send(.selectorStep(1))
        bench.run(for: 7)
        #expect(bench.lamp(.run, 1) == .off)
        #expect(bench.lamp(PK4.warning(.stale)) == .off)

        // Turning back to it raises the alarm.
        bench.send(.selectorStep(-1))
        #expect(bench.lamp(PK4.warning(.stale)) == .flash)
    }

    @Test func hookEventsLiveForTheirOwnTimeToLive() {
        let bench = Bench()
        bench.feed(
            bench.poll(["a"]) + [
                bench.hook("a", .turnDone, ttl: TTL.turnDone),
                bench.hook("a", .waiting, ttl: TTL.waiting),
            ])
        bench.keepPolling(["a"], for: 10 * 60 + 2)
        #expect(bench.lamp(.done, 1) == .off)
        #expect(bench.lamp(.wait, 1) != .off)

        bench.keepPolling(["a"], for: 20 * 60)
        #expect(bench.lamp(.wait, 1) == .off)
    }

    @Test func subagentActivityLightsForThirtySeconds() {
        let bench = Bench()
        bench.feed(
            bench.poll(["a"])
                + [bench.hook("a", .subagentActivity, ttl: TTL.subagentActivity)])
        #expect(bench.lamp(PK4.warning(.subagent)) == .on)
        bench.keepPolling(["a"], for: 32)
        #expect(bench.lamp(PK4.warning(.subagent)) == .off)
    }

    @Test func compactingLightsOnPreCompactAndClearsAtTheBoundary() {
        let bench = Bench()
        bench.feed(bench.poll(["a"]) + [bench.hook("a", .preCompact, ttl: TTL.preCompact)])
        #expect(bench.lamp(.cmpct, 1) == .on)
        #expect(bench.lamp(PK4.warning(.precompact)) == .on)

        bench.feed(bench.poll(["a"]) + [bench.reading("a", .compactBoundary, .time(bench.now))])
        #expect(bench.lamp(.cmpct, 1) == .off)
        #expect(bench.lamp(PK4.warning(.precompact)) == .off)
    }

    @Test func anOldBoundaryDoesNotClearANewCompaction() {
        let bench = Bench()
        let earlier = bench.now.addingTimeInterval(-3600)
        bench.feed(
            bench.poll(["a"]) + [
                bench.reading("a", .compactBoundary, .time(earlier)),
                bench.hook("a", .preCompact, ttl: TTL.preCompact),
            ])
        #expect(bench.lamp(.cmpct, 1) == .on)
    }

    @Test func aMissingFieldDarkensOnlyItsOwnInstrument() {
        let bench = Bench()
        bench.feed(
            bench.poll(["a"]) + [
                bench.reading("a", .outputTokens, .count(391_400)),
                bench.reading("a", .costUSD, .amount(42.17)),
            ])
        #expect(bench.snap.nixie(PK4.outputTokens) == "00391400")
        #expect(bench.snap.nixie(PK4.cost) == "0042.17")
        #expect(bench.snap.nixie(PK4.inputTokens) == "        ")
        #expect(bench.snap.meter(PK4.contextMeter) == Needle.leftStop)
    }

    @Test func aMistypedFieldDarkensItsInstrumentAndWritesOneLine() {
        let bench = Bench()
        bench.feed(
            bench.poll(["a"]) + [
                bench.reading("a", .outputTokens, .text("lots")),
                bench.reading("a", .inputTokens, .count(10)),
            ])
        bench.feed([bench.reading("a", .outputTokens, .text("lots"))])

        #expect(bench.snap.nixie(PK4.outputTokens) == "        ")
        #expect(bench.snap.nixie(PK4.inputTokens) == "00000010")
        #expect(bench.log.events(.sourceError).count == 1)
    }

    @Test func anEmptySlotReadsZeroWithTheNeedlesOnTheStop() {
        let bench = Bench()
        #expect(bench.snap.nixie(PK4.contextUsed) == "00000000")
        #expect(bench.snap.nixie(PK4.lastTurn) == "0000:00")
        #expect(bench.snap.nixie(PK4.cost) == "0000.00")
        #expect(bench.snap.meter(PK4.contextMeter) == Needle.leftStop)
        #expect(PK4.Permission.allCases.allSatisfy { bench.lamp(PK4.permission($0)) == .off })
    }

    @Test func panelBFollowsTheSelectedSession() {
        let bench = Bench()
        let started = bench.now.addingTimeInterval(-(3 * 3600 + 41 * 60))
        bench.feed(
            bench.agent("a", status: "busy", started: started) + bench.agent("b")
                + [
                    bench.reading("a", .contextUsed, .count(380_000)),
                    bench.reading("a", .contextWindow, .count(1_000_000)),
                    bench.reading("a", .cacheReadTokens, .count(261_000_999)),
                    bench.reading("a", .turnDuration, .seconds(125)),
                    bench.reading("a", .totalDuration, .seconds(1000)),
                    bench.reading("a", .apiDuration, .seconds(500)),
                    bench.reading("a", .toolDuration, .seconds(300)),
                    bench.reading("a", .permissionMode, .text("auto")),
                    bench.reading("a", .effort, .text("xhigh")),
                    bench.reading("a", .model, .text("claude-opus-5-5")),
                    bench.reading("a", .mode, .text("normal")),
                    bench.reading("a", .serviceTier, .text("standard")),
                    bench.reading("b", .contextUsed, .count(151_000)),
                    bench.reading("b", .contextWindow, .count(200_000)),
                    bench.roster(["a", "b"]),
                ])

        #expect(abs(bench.snap.meter(PK4.contextMeter) - 0.62) < 1e-9)
        #expect(bench.lamp(PK4.window1M) == .on)
        #expect(bench.lamp(PK4.window200K) == .off)
        #expect(bench.snap.nixie(PK4.cacheRead) == "00261000")
        #expect(bench.snap.nixie(PK4.lastTurn) == "0002:05")
        #expect(bench.snap.nixie(PK4.uptime) == "0003:41")
        #expect(bench.snap.meter(PK4.apiShareMeter) == 0.5)
        #expect(bench.snap.meter(PK4.toolShareMeter) == 0.3)
        #expect(bench.lamp(PK4.permission(.auto)) == .on)
        #expect(bench.lamp(PK4.effort(.xhigh)) == .on)
        #expect(bench.lamp(PK4.model(.opus)) == .on)
        #expect(bench.lamp(PK4.mode(.normal)) == .on)
        #expect(bench.lamp(PK4.kind(.interactive)) == .on)
        #expect(bench.lamp(PK4.tier(.standard)) == .on)

        bench.send(.selectorStep(1))
        #expect(abs(bench.snap.meter(PK4.contextMeter) - 0.245) < 1e-9)
        #expect(bench.lamp(PK4.window200K) == .on)
        #expect(bench.lamp(PK4.window1M) == .off)
        #expect(bench.lamp(PK4.permission(.auto)) == .off)
    }

    @Test func toolCallsAdvanceLiveBetweenTranscriptReads() {
        let bench = Bench()
        bench.feed(bench.poll(["a"]) + [bench.reading("a", .toolCalls, .count(600))])
        bench.feed([
            bench.reading("a", .toolUsed, .text("Bash"), ttl: TTL.instant),
            bench.reading("a", .toolUsed, .text("Read"), ttl: TTL.instant),
        ])
        bench.run(for: 0.3)
        #expect(bench.snap.nixie(PK4.toolCalls) == "000602")

        // The transcript's own count takes over again.
        bench.feed(bench.poll(["a"]) + [bench.reading("a", .toolCalls, .count(602))])
        bench.run(for: 0.3)
        #expect(bench.snap.nixie(PK4.toolCalls) == "000602")
    }

    @Test func theProgramBuildIsTheHighestAmongRunningSessions() {
        let bench = Bench()
        bench.feed(
            bench.agent("a") + bench.agent("b")
                + [
                    bench.reading("a", .version, .text("2.1.99")),
                    bench.reading("b", .version, .text("2.1.280")),
                    bench.roster(["a", "b"]),
                ])
        #expect(bench.snap.programBuild == "2.1.280")
    }
}
