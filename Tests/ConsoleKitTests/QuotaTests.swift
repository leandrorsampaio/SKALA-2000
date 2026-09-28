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

    @Test func theMetersShowTheShareUsedAndTheTubesTheTimeLeft() {
        let bench = Bench()
        #expect(bench.snap.meter(PK4.quotaMeter(.session)) == Needle.leftStop)
        #expect(bench.snap.nixie(PK4.sessionResets) == "     ")
        #expect(bench.snap.nixie(PK4.weekResetDays) == "  ")

        quota(bench, session: 0.06, week: 0.725)
        #expect(bench.snap.meter(PK4.quotaMeter(.session)) == 0.06)
        #expect(bench.snap.meter(PK4.quotaMeter(.week)) == 0.725)
        #expect(bench.snap.nixie(PK4.sessionResets) == "01:10")
        // 108 h 30 min, rounded up to 109 hours: 4 days 13 hours.
        #expect(bench.snap.nixie(PK4.weekResetDays) == "04")
        #expect(bench.snap.nixie(PK4.weekResetHours) == "13")

        // A minute on, the countdowns have turned over by themselves.
        bench.run(for: 61)
        #expect(bench.snap.nixie(PK4.sessionResets) == "01:09")
    }

    /// Past the reset, the old share is wrong: the meter drops to its stop.
    @Test func aWindowThatResetsGoesDark() {
        let bench = Bench()
        quota(bench, session: 0.5, resetsIn: 30)
        #expect(bench.snap.meter(PK4.quotaMeter(.session)) == 0.5)
        bench.run(for: 31)
        #expect(bench.snap.meter(PK4.quotaMeter(.session)) == Needle.leftStop)
        #expect(bench.snap.nixie(PK4.sessionResets) == "     ")
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

    /// Already past 80% when the desk first hears of it: lit, but not announced.
    @Test func theFirstReadingIsTakenAsItIs() {
        let bench = Bench()
        quota(bench, week: 0.9)
        #expect(bench.lamp(PK4.quotaNear(.week)) == .on)
        #expect(bench.snap.cues.count(.quota) == 0)
    }
}
