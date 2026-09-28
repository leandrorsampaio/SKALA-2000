import Foundation
import Testing

@testable import ConsoleKit
@testable import TelemetryKit

/// One test per row of the alarm table, plus the hook rules that feed it.
@MainActor
@Suite struct AlarmTests {

    /// Two sessions on the desk, polled.
    func twoSessions() -> Bench {
        let bench = Bench()
        bench.feed(bench.poll(["a", "b"]))
        return bench
    }

    @Test func aConditionBecomingTrueFlashesAndSounds() {
        let bench = twoSessions()
        bench.feed([bench.hook("a", .waiting, ttl: TTL.waiting)])

        #expect(bench.lamp(.wait, 1) == .flash)
        // Two quick buzzes, once: no buzzer left sounding.
        #expect(bench.snap.cues.count(.wait) == 1)
        #expect(!bench.snap.buzzer)
        let raised = bench.log.events(.alarmRaised)
        #expect(raised.count == 1)
        #expect(raised.first?.slot == 1)
        #expect(raised.first?.session == "a")
    }

    /// SILENCE is a mode: pressed, nothing sounds and its lamps burn; pressed again, the
    /// desk speaks again. Windows flash either way.
    @Test func silenceIsAModeAndItsLampsBurn() {
        let bench = twoSessions()
        bench.tap(PK4.silence)
        bench.run(for: 1)
        #expect(bench.lamp(PK4.silenced) == .on)
        #expect(bench.snap.button(PK4.silence).lamp == .on)

        bench.feed([bench.hook("a", .waiting, ttl: TTL.waiting)])
        #expect(bench.lamp(.wait, 1) == .flash)
        #expect(bench.snap.cues.count(.wait) == 0)

        bench.tap(PK4.silence)
        bench.run(for: 1)
        #expect(bench.lamp(PK4.silenced) == .off)
        #expect(bench.snap.button(PK4.silence).lamp == .off)
        #expect(bench.log.events(.alarmSilenced).map(\.detail) == ["on", "off"])

        bench.feed([bench.reading("b", .jobTempo, .text("blocked"))])
        #expect(bench.lamp(.block, 2) == .flash)
        #expect(bench.snap.cues.count(.block) == 1)
    }

    /// Each state speaks once, as it begins: DONE one buzz, CMPCT three, LOW CONTEXT a
    /// beep. Still true a moment later, it says nothing more.
    @Test func eachStateSignalsOnceAsItBegins() {
        let bench = twoSessions()
        bench.feed([bench.hook("a", .turnDone, ttl: TTL.turnDone)])
        bench.feed([bench.hook("a", .turnDone, ttl: TTL.turnDone)])
        #expect(bench.snap.cues.count(.done) == 1)

        bench.feed([bench.hook("b", .preCompact, ttl: TTL.preCompact)])
        #expect(bench.lamp(.cmpct, 2) == .on)
        #expect(bench.snap.cues.count(.compact) == 1)

        // 5% left is not yet low; 4.5% is.
        bench.feed([
            bench.reading("a", .contextUsed, .count(190_000)),
            bench.reading("a", .contextWindow, .count(200_000)),
        ])
        #expect(bench.lamp(.lowctx, 1) == .off)
        bench.feed([bench.reading("a", .contextUsed, .count(191_000))])
        #expect(bench.lamp(.lowctx, 1) == .on)
        #expect(bench.snap.cues.count(.lowContext) == 1)
        bench.feed([bench.reading("a", .contextUsed, .count(192_000))])
        #expect(bench.snap.cues.count(.lowContext) == 1)
    }

    /// A session that takes its slot already done did not just finish: no signal.
    @Test func aSessionSeatedAsItIsSaysNothing() {
        let bench = Bench()
        bench.feed(bench.poll(["a"]) + [bench.hook("a", .turnDone, ttl: TTL.turnDone)])
        #expect(bench.lamp(.done, 1) == .on)
        #expect(bench.snap.cues.count(.done) == 0)
    }

    @Test func acknowledgeTurnsEveryFlashingWindowSteady() {
        let bench = twoSessions()
        bench.feed([
            bench.hook("a", .waiting, ttl: TTL.waiting),
            bench.hook("b", .waiting, ttl: TTL.waiting),
        ])
        bench.tap(PK4.acknowledge)

        #expect(bench.lamp(.wait, 1) == .on)
        #expect(bench.lamp(.wait, 2) == .on)
        #expect(!bench.snap.buzzer)
        #expect(bench.log.events(.alarmAcknowledged).first?.detail == "a.wait.1 a.wait.2")
    }

    @Test func aClearedConditionGoesDarkWhetherAcknowledgedOrNot() {
        let bench = twoSessions()
        bench.feed([bench.hook("a", .waiting, ttl: TTL.waiting)])
        bench.tap(PK4.acknowledge)
        bench.feed([bench.hook("b", .waiting, ttl: TTL.waiting)])
        #expect(bench.snap.cues.count(.wait) == 2)

        // The acknowledged one clears: the unacknowledged one still flashes.
        bench.feed([bench.reading("a", .promptSubmitted, .event, ttl: TTL.instant)])
        #expect(bench.lamp(.wait, 1) == .off)
        #expect(bench.lamp(.wait, 2) == .flash)

        bench.feed([bench.reading("b", .promptSubmitted, .event, ttl: TTL.instant)])
        #expect(bench.lamp(.wait, 2) == .off)
        #expect(bench.log.events(.alarmCleared).count == 2)
    }

    @Test func holdingLampTestLightsEveryWindowAndCapAndSoundsNothing() {
        let bench = twoSessions()
        bench.feed([bench.hook("a", .waiting, ttl: TTL.waiting)])
        bench.send(.press(PK4.lampTest))

        #expect(PK4.allLamps.allSatisfy { bench.lamp($0) == .test })
        #expect(bench.snap.button(PK4.silence).lamp == .test)
        #expect(bench.snap.button(PK4.function(3)).lamp == .test)
        #expect(bench.snap.button(PK4.lampTest).capDown)
        #expect(!bench.snap.buzzer)

        // Every tube shows every cathode.
        #expect(bench.snap.nixie(PK4.contextUsed) == "88888888")

        // A click is over at once; the test still shows for its minimum.
        bench.send(.release(PK4.lampTest))
        #expect(bench.lamp(.busy, 2) == .test)
        bench.run(for: ConsoleTiming.testMinimum)
        #expect(bench.lamp(.wait, 1) == .flash)
        #expect(bench.lamp(.busy, 2) == .off)
        // Raised once, before the test: the test itself says nothing.
        #expect(bench.snap.cues.count(.wait) == 1)
    }

    @Test func buzzerTestSoundsTheBuzzerEvenMuted() {
        let bench = twoSessions()
        bench.model.setBuzzerMuted(true)
        #expect(!bench.snap.buzzer)

        bench.send(.press(PK4.buzzerTest))
        #expect(bench.snap.buzzer)
        #expect(bench.snap.button(PK4.buzzerTest).lamp == .on)
        bench.send(.release(PK4.buzzerTest))
        #expect(bench.snap.buzzer)
        bench.run(for: ConsoleTiming.testMinimum)
        #expect(!bench.snap.buzzer)
        #expect(bench.snap.button(PK4.buzzerTest).lamp == .off)
        // Nothing is sent anywhere, and nothing is logged as a command.
        #expect(bench.log.events(.commandSent).isEmpty)
    }

    @Test func nonAlarmRowsAreJustOnAndOff() {
        let bench = twoSessions()
        bench.feed([
            bench.hook("a", .turnDone, ttl: TTL.turnDone),
            bench.hook("a", .agentDone, ttl: TTL.agentDone),
        ])
        #expect(bench.lamp(.done, 1) == .on)
        #expect(bench.lamp(.agent, 1) == .on)
        // DONE buzzes once; AGENT has no signal.
        #expect(bench.snap.cues.signals == [.done: 1])
        #expect(bench.log.events(.alarmRaised).isEmpty)
    }

    @Test func aPromptClearsWaitDoneAndAgentForThatSlotOnly() {
        let bench = twoSessions()
        bench.feed([
            bench.hook("a", .waiting, ttl: TTL.waiting),
            bench.hook("a", .turnDone, ttl: TTL.turnDone),
            bench.hook("a", .agentDone, ttl: TTL.agentDone),
            bench.hook("b", .turnDone, ttl: TTL.turnDone),
        ])
        bench.feed([bench.reading("a", .promptSubmitted, .event, ttl: TTL.instant)])

        #expect(bench.lamp(.wait, 1) == .off)
        #expect(bench.lamp(.done, 1) == .off)
        #expect(bench.lamp(.agent, 1) == .off)
        #expect(bench.lamp(.done, 2) == .on)
    }

    /// A permission granted in the terminal submits no prompt; the tool running is the sign
    /// the operator answered.
    @Test func aToolRunningClearsWaitingButNotDone() {
        let bench = twoSessions()
        bench.feed([
            bench.hook("a", .turnDone, ttl: TTL.turnDone),
            bench.hook("a", .waiting, ttl: TTL.waiting),
        ])
        #expect(bench.lamp(.wait, 1) == .flash)

        bench.feed([bench.reading("a", .toolUsed, .text("Bash"), ttl: TTL.instant)])
        #expect(bench.lamp(.wait, 1) == .off)
        #expect(bench.lamp(.done, 1) == .on)
        #expect(!bench.snap.buzzer)
    }

    @Test func stopDropsBusyAtOnceAndALaggingPollDoesNotRelightIt() {
        let bench = Bench()
        bench.feed(bench.poll(["a"], status: "busy"))
        #expect(bench.lamp(.busy, 1) == .on)

        bench.feed([bench.hook("a", .turnDone, ttl: TTL.turnDone)])
        #expect(bench.lamp(.busy, 1) == .off)
        #expect(bench.lamp(.done, 1) == .on)

        // The poll that was already in flight still says busy.
        bench.feed(bench.poll(["a"], status: "busy"))
        #expect(bench.lamp(.busy, 1) == .off)

        // Once idle has been seen, the next busy is real.
        bench.feed(bench.poll(["a"], status: "idle"))
        bench.feed(bench.poll(["a"], status: "busy"))
        #expect(bench.lamp(.busy, 1) == .on)
        // The readout is held to four changes a second, so it follows a moment later.
        bench.run(for: ConsoleTiming.nixieThrottle)
        #expect(bench.snap.nixie(PK4.sessionsBusy) == "1")
    }

    @Test func blockedWritesItsNeedsToTheTextLogWhenItRaises() {
        let bench = Bench()
        bench.feed(
            bench.agent("job", kind: "background") + [
                bench.reading("job", .jobTempo, .text("blocked")),
                bench.reading("job", .jobNeeds, .text("send a prompt to start")),
                bench.roster(["job"]),
            ])
        #expect(bench.lamp(.block, 1) == .flash)
        #expect(bench.log.lines == ["S1 NEEDS send a prompt to start"])
    }

    @Test func batteryLowJoinsTheAlarmLogic() {
        let bench = Bench()
        bench.feed([
            bench.machine(.batteryFraction, .amount(0.15)),
            bench.machine(.onMains, .flag(false)),
        ])
        #expect(bench.lamp(PK4.batteryLow) == .flash)
        #expect(bench.lamp(PK4.onBattery) == .on)
        #expect(bench.lamp(PK4.onMains) == .off)
        #expect(bench.snap.meter(PK4.batteryMeter) == 0.15)

        bench.tap(PK4.acknowledge)
        #expect(bench.lamp(PK4.batteryLow) == .on)

        bench.feed([bench.machine(.batteryFraction, .amount(0.5))])
        #expect(bench.lamp(PK4.batteryLow) == .off)
    }

    @Test func buzzerMutedSilencesTheSignalsButNeverTheFlash() {
        let bench = twoSessions()
        bench.model.setBuzzerMuted(true)
        bench.feed([bench.hook("a", .waiting, ttl: TTL.waiting)])
        #expect(bench.lamp(.wait, 1) == .flash)
        #expect(bench.snap.cues.signals.isEmpty)
        #expect(bench.lamp(PK4.silenced) == .on)
    }
}
