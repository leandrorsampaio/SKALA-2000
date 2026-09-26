import Foundation
import Testing

@testable import ConsoleKit
@testable import TelemetryKit

/// MAINS, the power-up sequence, and how often the snapshot is allowed to change.
@MainActor
@Suite struct MainsTests {

    @Test func mainsOffDarkensEverythingButTheDrums() {
        let bench = Bench()
        bench.feed(
            bench.poll(["a"], status: "busy") + [
                bench.hook("a", .waiting, ttl: TTL.waiting),
                bench.reading("a", .costUSD, .amount(7)),
                bench.reading("a", .contextUsed, .count(1000)),
                bench.reading("a", .contextWindow, .count(200_000)),
            ])
        #expect(bench.snap.buzzer)

        bench.send(.mains(false))
        #expect(!bench.model.isPowered)
        #expect(!bench.snap.mains)
        #expect(bench.snap.lamps.isEmpty)
        #expect(!bench.snap.buzzer)
        #expect(bench.snap.nixie(PK4.contextUsed) == "        ")
        #expect(bench.snap.nixie(PK4.selected) == " ")
        #expect(bench.snap.meter(PK4.contextMeter) == Needle.leftStop)
        #expect(bench.snap.drum(PK4.totalCost) == 7)
        #expect(bench.log.events(.mainsOff).count == 1)

        // Nothing is read and nothing is sent.
        bench.feed([bench.reading("a", .costUSD, .amount(20))])
        #expect(bench.snap.drum(PK4.totalCost) == 7)
        bench.tap(PK4.function(1))
        #expect(bench.log.events(.commandSent).isEmpty)
    }

    @Test func mainsOnRunsThePowerUpSequenceBeforeLiveData() {
        let bench = Bench(poweredOn: false)
        bench.send(.mains(true))
        let start = bench.now
        func at(_ offset: TimeInterval) {
            bench.clock.now = start.addingTimeInterval(offset)
            bench.model.advance()
        }

        at(0.2)
        #expect(bench.lamp(PK4.powerOn) == .off)
        at(0.26)
        #expect(bench.lamp(PK4.powerOn) == .on)
        // The first row strikes on all eights; the next has not yet.
        #expect(bench.snap.nixie(PK4.targetC) == "8")
        #expect(bench.snap.nixie(PK4.selected) == " ")
        at(0.30)
        #expect(bench.snap.nixie(PK4.selected) == "8")
        at(0.34)
        #expect(bench.snap.nixie(PK4.contextUsed) == "88888888")
        #expect(bench.snap.nixie(PK4.queueDepth) == "888888")
        #expect(bench.snap.nixie(PK4.cost) == "       ")
        at(0.42)
        #expect(bench.snap.nixie(PK4.lastTurn) == "8888:88")
        #expect(bench.snap.nixie(PK4.targetC) == " ")
        // Needles on the stop until the last row has struck.
        #expect(bench.snap.meter(PK4.contextMeter) == Needle.leftStop)

        let schedule = PowerUp(since: start)
        at(schedule.lampTestStart.timeIntervalSince(start) + 0.01)
        #expect(PK4.allLamps.allSatisfy { bench.lamp($0) == .test })
        #expect(bench.snap.cues.chirp == 1)
        #expect(!bench.snap.buzzer)

        at(schedule.liveAt.timeIntervalSince(start) + 0.01)
        #expect(bench.lamp(PK4.batteryLow) == .off)
        #expect(bench.lamp(PK4.powerOn) == .on)
        #expect(bench.snap.nixie(PK4.selected) == "1")
        #expect(bench.snap.cues.chirp == 1)
    }

    @Test func alarmsStillTrueAreRaisedAgainAfterPowerUp() {
        let bench = Bench()
        bench.feed(bench.poll(["a"]) + [bench.hook("a", .waiting, ttl: TTL.waiting)])
        bench.tap(PK4.acknowledge)
        #expect(bench.lamp(.wait, 1) == .on)

        bench.send(.mains(false))
        bench.send(.mains(true))
        bench.keepPolling(["a"], for: 3)
        #expect(bench.lamp(.wait, 1) == .flash)
    }

    @Test func telemetryPublishesAtMostTenTimesASecond() {
        let bench = Bench()
        bench.feed(bench.poll(["a"]))
        let before = bench.snap

        bench.model.ingest([bench.hook("a", .turnDone, ttl: TTL.turnDone)])
        bench.clock.advance(by: 0.05)
        bench.model.ingest([bench.hook("a", .agentDone, ttl: TTL.agentDone)])
        #expect(bench.snap == before)

        bench.clock.advance(by: 0.06)
        bench.model.advance()
        #expect(bench.lamp(.done, 1) == .on)
        #expect(bench.lamp(.agent, 1) == .on)
    }

    @Test func eachNixieChangesAtMostFourTimesASecond() {
        let bench = Bench()
        bench.feed(bench.poll(["a"]) + [bench.reading("a", .queueDepth, .count(1))])
        #expect(bench.snap.nixie(PK4.queueDepth) == "000001")

        bench.feed([bench.reading("a", .queueDepth, .count(2))])
        #expect(bench.snap.nixie(PK4.queueDepth) == "000001")
        bench.run(for: 0.2)
        #expect(bench.snap.nixie(PK4.queueDepth) == "000002")
    }

    @Test func aSelectorTurnSwapsEveryReadoutAtOnce() {
        let bench = Bench()
        bench.feed(bench.poll(["a", "b"]) + [bench.reading("b", .queueDepth, .count(3))])
        bench.feed([bench.reading("a", .queueDepth, .count(1))])
        bench.send(.selectorStep(1))
        #expect(bench.snap.nixie(PK4.queueDepth) == "000003")
    }

    @Test func theNextDeadlineIsNilOnlyWhenNothingWillChange() {
        let bench = Bench(poweredOn: false)
        bench.run(for: 2)
        #expect(bench.model.nextDeadline == nil)
    }
}
