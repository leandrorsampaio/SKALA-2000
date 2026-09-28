import Foundation
import Testing

@testable import ConsoleKit
@testable import TelemetryKit

/// Unknown values light OTHER where the group has one, and darken the group with one log
/// line where it does not. A wrong window is never left lit.
@MainActor
@Suite struct EnumTests {

    func selected(_ readings: (Bench) -> [Reading]) -> Bench {
        let bench = Bench()
        bench.feed(bench.poll(["a"]) + readings(bench))
        return bench
    }

    /// `max` is real — it turns up in transcripts — and has a window of its own.
    @Test func maxEffortLightsMax() {
        let bench = selected { [$0.reading("a", .effort, .text("max"))] }
        #expect(bench.lamp(PK4.effort(.max)) == .on)
        #expect(bench.lamp(PK4.effort(.xhigh)) == .off)
        #expect(bench.log.events(.sourceError).isEmpty)

        bench.tap(PK4.printText)
        #expect(bench.log.lines.contains("S1 EFFORT max"))
    }

    @Test func ultracodeLightsItsOwnWindow() {
        let bench = selected { [$0.reading("a", .effort, .text("ultracode"))] }
        #expect(bench.lamp(PK4.effort(.ultracode)) == .on)
    }

    @Test func anUnknownEffortDarkensTheGroupAndIsLoggedOnce() {
        let bench = selected { [$0.reading("a", .effort, .text("hyper"))] }
        bench.keepPolling(["a"], for: 4)
        bench.feed([bench.reading("a", .effort, .text("hyper"))])

        #expect(PK4.Effort.allCases.allSatisfy { bench.lamp(PK4.effort($0)) == .off })
        let lines = bench.log.events(.sourceError).filter { $0.detail?.contains("effort") == true }
        #expect(lines.count == 1)
        #expect(lines.first?.session == "a")
    }

    @Test func anUnknownPermissionModeDarkensTheGroup() {
        let bench = selected { [$0.reading("a", .permissionMode, .text("dontAsk"))] }
        #expect(PK4.Permission.allCases.allSatisfy { bench.lamp(PK4.permission($0)) == .off })
        #expect(bench.log.events(.sourceError).count == 1)
    }

    @Test func aChangedValueSwitchesWindowsWithoutLeavingTheOldOneLit() {
        let bench = selected { [$0.reading("a", .permissionMode, .text("plan"))] }
        #expect(bench.lamp(PK4.permission(.plan)) == .on)
        bench.feed([bench.reading("a", .permissionMode, .text("bypassPermissions"))])
        #expect(bench.lamp(PK4.permission(.plan)) == .off)
        #expect(bench.lamp(PK4.permission(.bypass)) == .on)
    }

    @Test func unknownValuesLightOtherWhereTheGroupHasOne() {
        let bench = selected {
            [
                $0.reading("a", .model, .text("claude-lyric-9")),
                $0.reading("a", .mode, .text("fast")),
                $0.reading("a", .serviceTier, .text("priority")),
            ]
        }
        #expect(bench.lamp(PK4.model(.other)) == .on)
        #expect(bench.lamp(PK4.mode(.other)) == .on)
        #expect(bench.lamp(PK4.tier(.other)) == .on)
        #expect(bench.log.events(.sourceError).isEmpty)
    }

    @Test func modelWindowsMatchOnTheIdAndIgnoreTheSuffix() {
        // Opus by its window: 1M when the session reports one, else its standard 200K.
        #expect(ConsoleModel.modelWindow("claude-opus-5-5", contextWindow: 1_000_000) == .opus1m)
        #expect(ConsoleModel.modelWindow("claude-opus-5-5", contextWindow: 200_000) == .opus200k)
        #expect(ConsoleModel.modelWindow("claude-opus-5-5[1m]") == .opus200k)
        #expect(ConsoleModel.modelWindow("claude-sonnet-5") == .sonnet)
        #expect(ConsoleModel.modelWindow("claude-haiku-4-5-20251001") == .haiku)
        #expect(ConsoleModel.modelWindow("claude-fable-5-1") == .fable)
        #expect(ConsoleModel.modelWindow("") == nil)
        #expect(ConsoleModel.modelWindow(nil) == nil)
    }

    @Test func anUnknownWindowSizeIsLoggedAndOpusShowsItsStandardWindow() {
        let bench = selected {
            [
                $0.reading("a", .model, .text("claude-opus-5-5")),
                $0.reading("a", .contextWindow, .count(500_000)),
            ]
        }
        #expect(bench.lamp(PK4.model(.opus200k)) == .on)
        #expect(bench.lamp(PK4.model(.opus1m)) == .off)
        #expect(bench.log.events(.sourceError).count == 1)
    }

    @Test func anUnknownStatusChangesNothing() {
        let bench = Bench()
        bench.feed(bench.poll(["a"], status: "busy"))
        bench.feed(bench.poll(["a"], status: "thinking"))
        #expect(bench.lamp(.busy, 1) == .on)
        #expect(bench.log.events(.sourceError).count == 1)
    }

    @Test func anythingButInteractiveIsDetached() {
        let bench = Bench()
        bench.feed(bench.agent("a", kind: "background") + [bench.roster(["a"])])
        #expect(bench.lamp(PK4.kind(.detached)) == .on)
        #expect(bench.lamp(PK4.kind(.interactive)) == .off)
    }
}
