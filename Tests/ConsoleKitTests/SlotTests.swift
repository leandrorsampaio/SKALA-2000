import Foundation
import Testing

@testable import ConsoleKit
@testable import TelemetryKit

@MainActor
@Suite struct SlotTests {

    @Test func aNewSessionTakesTheLowestFreeSlotAndKeepsIt() {
        let bench = Bench()
        bench.feed(bench.poll(["a"]))
        bench.feed(bench.poll(["a", "b"]))
        #expect(bench.slot(of: "a") == 1)
        #expect(bench.slot(of: "b") == 2)

        // A leaves; B does not move down into its column.
        bench.feed(bench.poll(["b"]))
        #expect(bench.slot(of: "a") == nil)
        #expect(bench.slot(of: "b") == 2)
        #expect(bench.lamp(.run, 1) == .off)
        #expect(bench.lamp(.run, 2) == .on)

        // The next newcomer takes the lowest free slot, which is A's old one.
        bench.feed(bench.poll(["b", "c"]))
        #expect(bench.slot(of: "c") == 1)
        #expect(bench.log.events(.slotReleased).count == 1)
    }

    /// After a relaunch every session sits in its own slot again, under its own strip,
    /// rather than in the order the sessions started.
    @Test func aRelaunchSeatsEverySessionWhereItSat() {
        let bench = Bench()
        bench.feed(bench.poll(["a"]))
        bench.feed(bench.poll(["a", "b"]))
        bench.feed(bench.poll(["b"]))
        bench.feed(bench.poll(["b", "c"]))
        #expect(bench.slot(of: "c") == 1)
        #expect(bench.slot(of: "b") == 2)
        bench.model.flush()

        let relaunched = Bench(saved: bench.store.state)
        let now = relaunched.now
        relaunched.feed(
            relaunched.agent("b", started: now.addingTimeInterval(-600))
                + relaunched.agent("c", started: now.addingTimeInterval(-60))
                + [relaunched.roster(["b", "c"])])
        #expect(relaunched.slot(of: "c") == 1)
        #expect(relaunched.slot(of: "b") == 2)
    }

    /// The wall clock set back an hour: the desk goes on showing what arrives.
    @Test func aClockSetBackDoesNotHoldTheDeskBack() {
        let bench = Bench()
        bench.clock.now = bench.now.addingTimeInterval(-3600)
        bench.feed(bench.poll(["a"]))
        bench.run(for: 0.2)
        #expect(bench.lamp(.run, 1) == .on)
    }

    @Test func newcomersInOnePollAreSeatedOldestFirst() {
        let bench = Bench()
        let early = bench.now.addingTimeInterval(-600)
        let late = bench.now.addingTimeInterval(-60)
        bench.feed(
            bench.agent("late", started: late) + bench.agent("early", started: early)
                + [bench.roster(["late", "early"])])
        #expect(bench.slot(of: "early") == 1)
        #expect(bench.slot(of: "late") == 2)
    }

    @Test func aFifthSessionIsIgnoredAndLoggedOnceUntilASlotFrees() {
        let bench = Bench()
        let five: [SessionKey] = ["s1", "s2", "s3", "s4", "s5"]
        var readings: [Reading] = []
        for (index, key) in five.enumerated() {
            readings += bench.agent(key, started: bench.now.addingTimeInterval(Double(index)))
        }
        bench.feed(readings + [bench.roster(five)])

        #expect(bench.slot(of: "s5") == nil)
        #expect((1...4).allSatisfy { bench.lamp(.run, $0) == .on })
        // SESSIONS RUNNING counts records, so it reads 5 while only four columns light.
        #expect(bench.snap.nixie(PK4.sessionsRunning) == "5")

        bench.keepPolling(five, for: 6)
        let refused = bench.log.events(.slotRefused)
        #expect(refused.count == 1)
        #expect(refused.first?.session == "s5")

        // s2 ends: the waiting session gets its column.
        bench.feed(bench.poll(["s1", "s3", "s4", "s5"]))
        #expect(bench.slot(of: "s5") == 2)
    }

    @Test func theSessionStartHookSeatsASessionBeforeTheRosterCatchesUp() {
        let bench = Bench()
        bench.feed([bench.hook("new", .sessionStarted, ttl: TTL.sessionStarted)])
        #expect(bench.slot(of: "new") == 1)
        #expect(bench.lamp(.run, 1) == .on)

        // A roster read before `claude agents` lists it does not throw it out.
        bench.run(for: 2)
        bench.feed([bench.roster([])])
        #expect(bench.slot(of: "new") == 1)

        // One that is still without it after the grace period does.
        bench.run(for: ConsoleTiming.hookGrace)
        bench.feed([bench.roster([])])
        #expect(bench.slot(of: "new") == nil)
    }

    @Test func theSessionEndHookFreesTheSlotAndALaggingRosterDoesNotRetakeIt() {
        let bench = Bench()
        bench.feed(bench.poll(["a"]))
        bench.feed([bench.reading("a", .sessionEnded, .event, ttl: TTL.instant)])
        #expect(bench.slot(of: "a") == nil)

        bench.feed(bench.poll(["a"]))
        #expect(bench.slot(of: "a") == nil)

        // Once the roster has caught up, a session with that id may start again.
        bench.feed(bench.poll([]))
        bench.feed(bench.poll(["a"]))
        #expect(bench.slot(of: "a") == 1)
    }

    @Test func theSelectorIsPersistedAndDoesNotFollowSessions() {
        let bench = Bench()
        bench.send(.selectorStep(1))
        bench.send(.selectorStep(1))
        bench.feed(bench.poll(["a"]))
        #expect(bench.snap.selector == 3)
        #expect(bench.snap.nixie(PK4.selected) == "3")
        #expect(bench.snap.nixie(PK4.targetC) == "3")

        bench.run(for: 2)
        #expect(bench.store.state?.selector == 3)

        let relaunched = Bench(saved: bench.store.state)
        #expect(relaunched.snap.selector == 3)
    }

    @Test func theSelectorIsPinnedAtBothEnds() {
        let bench = Bench()
        bench.send(.selectorStep(-1))
        #expect(bench.snap.selector == 1)
        for _ in 0..<6 { bench.send(.selectorStep(1)) }
        #expect(bench.snap.selector == 4)
    }

    @Test func goingToANumeralPassesThroughEveryDetentOnTheWay() {
        let bench = Bench()
        bench.send(.selectorGoTo(4))
        #expect(bench.snap.selector == 2)
        bench.run(for: ConsoleTiming.selectorDetent)
        #expect(bench.snap.selector == 3)
        bench.run(for: ConsoleTiming.selectorDetent)
        #expect(bench.snap.selector == 4)
        bench.run(for: 1)
        #expect(bench.snap.selector == 4)
    }

    @Test func thePencilStripIsPrefilledOnceAndThenBelongsToTheOperator() {
        let bench = Bench()
        bench.feed(
            bench.agent("a", cwd: "/Users/operator/Projects/maccommandcenter-extra")
                + [bench.roster(["a"])])
        // Twelve characters, then the strip is full.
        #expect(bench.snap.pencil(slot: 1) == "maccommandce")

        bench.send(.pencil(slot: 1, text: "reactor"))
        bench.keepPolling(["a"], for: 4)
        #expect(bench.snap.pencil(slot: 1) == "reactor")

        // A new session in a slot whose strip is written on keeps what is written.
        bench.feed(bench.poll([]))
        bench.feed(bench.agent("b", cwd: "/tmp/other") + [bench.roster(["b"])])
        #expect(bench.slot(of: "b") == 1)
        #expect(bench.snap.pencil(slot: 1) == "reactor")
    }

    @Test func aBackgroundJobIsPrefilledWithItsTaskName() {
        let bench = Bench()
        bench.feed(
            bench.agent("job", kind: "background")
                + [
                    bench.reading("job", .jobName, .text("Review root project markdown files")),
                    bench.roster(["job"]),
                ])
        #expect(bench.snap.pencil(slot: 1) == "Review root ")
        #expect(bench.lamp(.bkgd, 1) == .on)
        #expect(bench.lamp(PK4.kind(.detached)) == .on)
    }
}
