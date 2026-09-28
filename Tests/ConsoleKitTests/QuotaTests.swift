import Foundation
import Testing

@testable import ConsoleKit
@testable import TelemetryKit

/// Panel E's plan usage: two meters, their reset countdowns, and the lamps that warn.
@MainActor
@Suite struct QuotaTests {

    func quota(
        _ bench: Bench, session: Double? = nil, week: Double? = nil, resetsIn: TimeInterval = 4200
    ) {
        var readings: [Reading] = []
        if let session {
            readings += [
                bench.machine(.quotaSession, .amount(session), ttl: resetsIn),
                bench.machine(
                    .quotaSessionResets, .time(bench.now.addingTimeInterval(resetsIn)),
                    ttl: resetsIn),
            ]
        }
        if let week {
            readings += [
                bench.machine(.quotaWeek, .amount(week), ttl: 400_000),
                bench.machine(
                    .quotaWeekResets, .time(bench.now.addingTimeInterval(390_600)), ttl: 400_000),
            ]
        }
        bench.feed(readings)
    }

    /// The three readouts of a window's countdown, days, hours and minutes.
    func resets(_ bench: Bench, _ quota: PK4.Quota) -> String {
        PK4.ResetPart.allCases.map { bench.snap.nixie(PK4.quotaReset(quota, $0)) }
            .joined(separator: " ")
    }

    @Test func theMetersShowTheShareUsedAndTheTubesTheTimeLeft() {
        let bench = Bench()
        #expect(bench.snap.meter(PK4.quotaMeter(.session)) == Needle.leftStop)
        #expect(resets(bench, .session) == "        ")
        #expect(resets(bench, .week) == "        ")

        quota(bench, session: 0.06, week: 0.725)
        #expect(bench.snap.meter(PK4.quotaMeter(.session)) == 0.06)
        #expect(bench.snap.meter(PK4.quotaMeter(.week)) == 0.725)
        #expect(resets(bench, .session) == "00 01 10")
        // 108 h 30 min: 4 days, 12 hours and 30 minutes.
        #expect(resets(bench, .week) == "04 12 30")

        // A minute on, the countdowns have turned over by themselves, rounded up: 68
        // minutes and 59 seconds read 69 minutes.
        bench.run(for: 61)
        #expect(resets(bench, .session) == "00 01 09")
        #expect(resets(bench, .week) == "04 12 29")
    }

    /// Past the reset, the old share is wrong: the meter drops to its stop.
    @Test func aWindowThatResetsGoesDark() {
        let bench = Bench()
        quota(bench, session: 0.5, resetsIn: 30)
        #expect(bench.snap.meter(PK4.quotaMeter(.session)) == 0.5)
        bench.run(for: 31)
        #expect(bench.snap.meter(PK4.quotaMeter(.session)) == Needle.leftStop)
        #expect(resets(bench, .session) == "        ")
    }

    @Test func amberFromEightyRedFromNinetyFiveEachWithABeep() {
        let bench = Bench()
        quota(bench, session: 0.5, week: 0.5)
        #expect(bench.lamp(PK4.quotaNear(.session)) == .off)

        quota(bench, session: 0.82, week: 0.5)
        #expect(bench.lamp(PK4.quotaNear(.session)) == .on)
        #expect(bench.lamp(PK4.quotaLimit(.session)) == .off)
        #expect(bench.snap.cues.count(.quota) == 1)

        quota(bench, session: 0.96, week: 0.5)
        #expect(bench.lamp(PK4.quotaNear(.session)) == .on)
        // AT LIMIT flashes for as long as it holds.
        #expect(bench.lamp(PK4.quotaLimit(.session)) == .flash)
        #expect(bench.snap.cues.count(.quota) == 2)

        // Still past 95%: nothing more to say.
        quota(bench, session: 0.97, week: 0.5)
        #expect(bench.snap.cues.count(.quota) == 2)
        #expect(bench.lamp(PK4.quotaNear(.week)) == .off)
    }

    /// A relaunch shows the last figures at once, until their window resets.
    @Test func theLastFiguresSurviveARelaunchUntilTheyReset() {
        let bench = Bench()
        quota(bench, session: 0.4, week: 0.7, resetsIn: 3600)
        bench.model.flush()

        let relaunched = Bench(saved: bench.store.state)
        #expect(relaunched.snap.meter(PK4.quotaMeter(.session)) == 0.4)
        #expect(relaunched.snap.meter(PK4.quotaMeter(.week)) == 0.7)
        #expect(resets(relaunched, .session) == "00 01 00")

        // Launched after the session window reset: only the week comes back.
        var later = bench.store.state
        later?.quota["session"]?.resets = Date(timeIntervalSince1970: 0)
        let afterReset = Bench(saved: later)
        #expect(afterReset.snap.meter(PK4.quotaMeter(.session)) == Needle.leftStop)
        #expect(afterReset.snap.meter(PK4.quotaMeter(.week)) == 0.7)
    }

    /// Already past 80% when the desk first hears of it: lit, but not announced.
    @Test func theFirstReadingIsTakenAsItIs() {
        let bench = Bench()
        quota(bench, week: 0.9)
        #expect(bench.lamp(PK4.quotaNear(.week)) == .on)
        #expect(bench.snap.cues.count(.quota) == 0)
    }
}
