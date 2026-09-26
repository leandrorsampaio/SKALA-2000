import FakeSources
import Foundation
import Testing

@testable import ConsoleKit
@testable import TelemetryKit

/// The whole scripted day through the console, the way the app will run it with no
/// Claude Code installed.
@MainActor
@Suite struct FakeDayTests {

    struct Replay {
        var bench: Bench
        var maxSlots = 0
        var drumsWentBack = false
        var sawFifthWaiting = false
        var fifthSlot: Int?
        var sawStale = false
        var sawBlocked = false
        var sawBatteryLow = false
        var sawCompacting = false
    }

    func replay(hours: Double = 10) -> Replay {
        let bench = Bench()
        var day = FakeDay(start: bench.now)
        var replay = Replay(bench: bench)
        var previous = bench.snap.drums

        while !day.isOver, day.elapsed < hours * 3600 {
            let readings = day.step()
            bench.clock.now = day.now
            bench.model.ingest(readings)
            bench.model.advance()

            let snap = bench.snap
            replay.maxSlots = max(replay.maxSlots, bench.model.slots.occupants.count)
            for (id, value) in snap.drums where value < previous[id] ?? 0 {
                replay.drumsWentBack = true
            }
            previous = snap.drums

            if bench.model.slots.occupants.count == 4, bench.slot(of: "f7b0-fifth") == nil,
                (bench.model.freshRosterKeys(bench.now) ?? []).contains("f7b0-fifth")
            {
                replay.sawFifthWaiting = true
            }
            if let slot = bench.slot(of: "f7b0-fifth") { replay.fifthSlot = slot }
            if (1...4).contains(where: { snap.lamp(PK4.annunciator(.block, slot: $0)) != .off }) {
                replay.sawBlocked = true
            }
            if (1...4).contains(where: { snap.lamp(PK4.annunciator(.cmpct, slot: $0)) == .on }) {
                replay.sawCompacting = true
            }
            if snap.lamp(PK4.warning(.stale)) != .off { replay.sawStale = true }
            if snap.lamp(PK4.batteryLow) != .off { replay.sawBatteryLow = true }
        }
        return replay
    }

    @Test func theWholeDayRunsWithinTheRules() {
        let replay = replay()
        let log = replay.bench.log

        #expect(replay.maxSlots <= 4)
        #expect(!replay.drumsWentBack)
        #expect(replay.sawFifthWaiting)
        // TAX's column goes to the session that was waiting for one.
        #expect(replay.fifthSlot == 2)
        #expect(replay.sawBlocked)
        #expect(log.lines.contains("S3 NEEDS send a prompt to start"))
        #expect(replay.sawStale)
        #expect(replay.sawBatteryLow)
        #expect(replay.sawCompacting)
        #expect(log.events(.slotRefused).count == 1)

        // `max` effort is known: it lights MAX and writes nothing. An unknown permission
        // mode is logged once, not every poll.
        let effort = log.events(.sourceError).filter { $0.detail?.contains("effort") == true }
        #expect(effort.isEmpty)
        let permission = log.events(.sourceError).filter {
            $0.detail?.contains("permissionMode") == true
        }
        #expect(permission.count == 1)

        // By evening every session has ended and every slot is free.
        #expect(replay.bench.model.slots.occupants.isEmpty)
        #expect(replay.bench.snap.drum(PK4.totalOutput) > 0)
        #expect(replay.bench.snap.drum(PK4.hoursInService) == 10)
    }

    /// A demo opens at 08:55 on the wall clock's time, and keeps to it.
    @Test func aDemoOpensAtFiveToNineAndKeepsToTheClock() {
        let moment = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var day = FakeDay.opening(at: moment)
        #expect(day.now == moment.addingTimeInterval(-FakeDay.tick))

        let first = day.catchUp(to: moment)
        #expect(day.now == moment)
        #expect(first.contains { $0.field == .roster })
        #expect(first.allSatisfy { $0.observedAt <= moment })

        // Three seconds on is one tick: the second is not due yet.
        _ = day.catchUp(to: moment.addingTimeInterval(3))
        #expect(day.now == moment.addingTimeInterval(2))
        // A timer that fired late catches up in one go.
        _ = day.catchUp(to: moment.addingTimeInterval(20))
        #expect(day.now == moment.addingTimeInterval(20))
    }

    @Test func theDayIsTheSameEveryTime() {
        let first = replay(hours: 2).bench.model.saved.totals
        let second = replay(hours: 2).bench.model.saved.totals
        #expect(first.costUSD == second.costUSD)
        #expect(first.outputTokens == second.outputTokens)
    }
}
