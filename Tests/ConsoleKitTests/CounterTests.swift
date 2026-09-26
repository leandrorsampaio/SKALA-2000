import Foundation
import Testing

@testable import ConsoleKit
@testable import TelemetryKit

/// Drum counters, hours in service and what survives a relaunch.
@MainActor
@Suite struct CounterTests {

    @Test func drumsSumPositiveDeltasAcrossASessionRestart() {
        let bench = Bench()
        for cost in [10.0, 12.5, 0.4, 3.0] {
            bench.feed([bench.reading("a", .costUSD, .amount(cost))])
        }
        // 10 + 2.5, then the figure restarted: 0.4 is not subtracted, and 2.6 more counts.
        #expect(abs(bench.model.saved.totals.costUSD - 15.1) < 1e-9)
        #expect(bench.snap.drum(PK4.totalCost) == 15)
    }

    @Test func drumsAddUpEverySessionAndOnlyMoveForward() {
        let bench = Bench()
        bench.feed([
            bench.reading("a", .outputTokens, .count(391_400)),
            bench.reading("b", .outputTokens, .count(88_200)),
            bench.reading("a", .linesAdded, .count(1366)),
            bench.reading("a", .linesRemoved, .count(31)),
        ])
        #expect(bench.snap.drum(PK4.totalOutput) == 479)
        #expect(bench.snap.drum(PK4.linesAdded) == 1366)
        #expect(bench.snap.drum(PK4.linesRemoved) == 31)

        bench.feed([bench.reading("a", .outputTokens, .count(1000))])
        #expect(bench.snap.drum(PK4.totalOutput) == 479)
    }

    @Test func aRelaunchDoesNotCountARunningSessionTwice() {
        let bench = Bench()
        bench.feed([bench.reading("a", .costUSD, .amount(42))])
        bench.model.flush()

        let relaunched = Bench(saved: bench.store.state)
        relaunched.feed([relaunched.reading("a", .costUSD, .amount(42))])
        #expect(relaunched.snap.drum(PK4.totalCost) == 42)
        relaunched.feed([relaunched.reading("a", .costUSD, .amount(43))])
        #expect(relaunched.snap.drum(PK4.totalCost) == 43)
    }

    @Test func storedTotalsShowFromTheFirstFrameEvenWithMainsOff() {
        var saved = PersistedConsole()
        saved.totals.costUSD = 418.7
        saved.totals.outputTokens = 3_914_000
        saved.totals.linesAdded = 1366
        saved.serviceSeconds = 4127 * 3600 + 5

        let bench = Bench(saved: saved, poweredOn: false)
        #expect(!bench.snap.mains)
        #expect(bench.snap.drum(PK4.totalCost) == 418)
        #expect(bench.snap.drum(PK4.totalOutput) == 3914)
        #expect(bench.snap.drum(PK4.linesAdded) == 1366)
        #expect(bench.snap.drum(PK4.hoursInService) == 4127)
    }

    @Test func hoursInServiceCountOnlyWhileMainsIsOn() {
        let bench = Bench()
        bench.run(for: 3600)
        #expect(bench.snap.drum(PK4.hoursInService) == 1)

        bench.send(.mains(false))
        bench.run(for: 7200)
        #expect(bench.snap.drum(PK4.hoursInService) == 1)

        bench.send(.mains(true))
        bench.run(for: 3600)
        #expect(bench.snap.drum(PK4.hoursInService) == 2)
    }

    @Test func everythingTheDeskRemembersSurvivesARelaunch() {
        let bench = Bench()
        bench.send(.selectorStep(1))
        bench.send(.pencil(slot: 3, text: "familyhub"))
        bench.send(.guard(PK4.f10, open: true))
        bench.send(.key(PK4.f10, armed: true))
        bench.model.setFinish(.graphite)
        bench.model.setBuzzerMuted(true)
        bench.run(for: 2)

        let relaunched = Bench(saved: bench.store.state)
        #expect(relaunched.snap.selector == 2)
        #expect(relaunched.snap.pencil(slot: 3) == "familyhub")
        #expect(relaunched.snap.keysArmed.contains(PK4.f10))
        #expect(relaunched.snap.finish == .graphite)
        #expect(relaunched.model.saved.buzzerMuted)
    }

    @Test func aDamagedStoreKeepsWhatItCanRead() throws {
        let json =
            #"{"totals":{"costUSD":418.5,"lastSeen":"not a map"},"selector":9,"finish":"chrome"}"#
        let saved = try JSONDecoder().decode(PersistedConsole.self, from: Data(json.utf8))
        #expect(saved.totals.costUSD == 418.5)
        #expect(saved.totals.lastSeen.isEmpty)
        #expect(saved.selector == 4)
        #expect(saved.finish == .greyGreen)
        #expect(saved.pencils == ["", "", "", ""])
    }
}
