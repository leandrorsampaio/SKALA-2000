import Foundation
import Testing

@testable import ConsoleKit
@testable import TelemetryKit

/// A command that remembers its requests and answers only when told to.
@MainActor
final class Recorder {
    var requests: [CommandRequest] = []
    var replies: [(Bool) -> Void] = []

    func action(latching: Bool = false, observes: Field? = nil) -> CommandAction {
        CommandAction(latching: latching, observes: observes) { [weak self] request, reply in
            self?.requests.append(request)
            self?.replies.append(reply)
        }
    }

    func answer(_ confirmed: Bool) {
        replies.removeFirst()(confirmed)
    }
}

@MainActor
@Suite struct CommandTests {

    // MARK: - Routine pushbuttons

    @Test func theLampAnswersTheMachineNotTheFinger() {
        let recorder = Recorder()
        let bench = Bench(commands: ConsoleCommands(actions: [PK4.function(1): recorder.action()]))
        bench.feed(bench.poll(["a"]))

        bench.send(.press(PK4.function(1)))
        #expect(bench.snap.button(PK4.function(1)).capDown)
        #expect(bench.snap.button(PK4.function(1)).phase == .down)
        #expect(recorder.requests.isEmpty)

        // Sending happens on release, and the lamp does not change.
        bench.send(.release(PK4.function(1)))
        #expect(recorder.requests.count == 1)
        #expect(recorder.requests.first?.slot == 1)
        #expect(recorder.requests.first?.session == "a")
        #expect(bench.snap.button(PK4.function(1)).phase == .sent)
        #expect(bench.snap.button(PK4.function(1)).lamp == .off)
        #expect(bench.log.events(.commandSent).count == 1)

        recorder.answer(true)
        #expect(bench.snap.button(PK4.function(1)).phase == .confirmed)
        #expect(bench.snap.button(PK4.function(1)).lamp == .on)

        // A momentary function glows for 600 ms.
        bench.run(for: 0.61)
        #expect(bench.snap.button(PK4.function(1)).phase == .idle)
        #expect(bench.snap.button(PK4.function(1)).lamp == .off)
    }

    @Test func nothingBackInThreeSecondsIsNoAnswer() {
        let bench = Bench()
        bench.tap(PK4.function(7))
        bench.run(for: 2.9)
        #expect(bench.snap.button(PK4.function(7)).phase == .sent)

        bench.run(for: 0.2)
        #expect(bench.snap.button(PK4.function(7)).phase == .noAnswer)
        #expect(bench.snap.button(PK4.function(7)).lamp == .off)
        #expect(bench.log.events(.commandNoAnswer).count == 1)

        bench.run(for: ConsoleTiming.noAnswerBlink)
        #expect(bench.snap.button(PK4.function(7)).phase == .idle)
    }

    @Test func pressesWhileSentAreIgnored() {
        let recorder = Recorder()
        let bench = Bench(commands: ConsoleCommands(actions: [PK4.function(2): recorder.action()]))
        bench.tap(PK4.function(2))
        bench.tap(PK4.function(2))
        bench.tap(PK4.function(2))
        #expect(recorder.requests.count == 1)
        #expect(!bench.snap.button(PK4.function(2)).capDown)
    }

    @Test func aLateReplyForAnEarlierPressIsIgnored() {
        let recorder = Recorder()
        let bench = Bench(commands: ConsoleCommands(actions: [PK4.function(2): recorder.action()]))
        bench.tap(PK4.function(2))
        bench.run(for: 4)
        bench.tap(PK4.function(2))
        recorder.answer(true)  // the first press's answer, far too late
        #expect(bench.snap.button(PK4.function(2)).phase == .sent)
        recorder.answer(true)
        #expect(bench.snap.button(PK4.function(2)).phase == .confirmed)
    }

    @Test func aLatchingFunctionStaysLitUntilPressedAgain() {
        let recorder = Recorder()
        let bench = Bench(
            commands: ConsoleCommands(actions: [PK4.function(3): recorder.action(latching: true)]))
        bench.tap(PK4.function(3))
        recorder.answer(true)
        bench.run(for: 2)
        #expect(bench.snap.button(PK4.function(3)).lamp == .on)

        bench.tap(PK4.function(3))
        recorder.answer(true)
        bench.run(for: 2)
        #expect(bench.snap.button(PK4.function(3)).lamp == .off)
    }

    @Test func theTargetIsTheSlotSelectedAtRelease() {
        let recorder = Recorder()
        let bench = Bench(commands: ConsoleCommands(actions: [PK4.function(4): recorder.action()]))
        bench.send(.press(PK4.function(4)))
        bench.send(.selectorStep(1))
        bench.send(.release(PK4.function(4)))
        bench.send(.selectorStep(1))
        #expect(recorder.requests.first?.slot == 2)
    }

    @Test func aFailedReplyIsNoAnswerAtOnce() {
        let recorder = Recorder()
        let bench = Bench(commands: ConsoleCommands(actions: [PK4.function(5): recorder.action()]))
        bench.tap(PK4.function(5))
        recorder.answer(false)
        #expect(bench.snap.button(PK4.function(5)).phase == .noAnswer)
    }

    // MARK: - The console's own buttons

    @Test func printTextWritesTheSelectedSessionsStringsAndOpensTheLog() {
        let bench = Bench()
        bench.feed(
            bench.poll(["a"]) + [
                bench.reading("a", .aiTitle, .text("FamilyHub auth")),
                bench.reading("a", .gitBranch, .text("main")),
                bench.reading("a", .toolMix, .tally(["Bash": 528, "Read": 40])),
                bench.reading("a", .lastPrompt, .text("carry on")),
            ])
        bench.tap(PK4.printText)

        #expect(bench.log.lines.contains("S1 TITLE FamilyHub auth"))
        #expect(bench.log.lines.contains("S1 BRANCH main"))
        #expect(bench.log.lines.contains("S1 TOOL Bash 528"))
        #expect(bench.log.lines.contains("S1 PROMPT carry on"))
        #expect(bench.snap.cues.openLog == 1)
        #expect(bench.snap.button(PK4.printText).phase == .confirmed)
    }

    @Test func printTextThatCannotWriteIsNoAnswer() {
        let bench = Bench()
        bench.log.textFails = true
        bench.tap(PK4.printText)
        #expect(bench.snap.button(PK4.printText).phase == .noAnswer)
        #expect(bench.snap.cues.openLog == 0)
    }

    @Test func printTextOnAnEmptySlotSaysSo() {
        let bench = Bench()
        bench.send(.selectorStep(1))
        bench.tap(PK4.printText)
        #expect(bench.log.lines == ["S2 NO SESSION"])
    }

    // MARK: - Guarded buttons

    @Test func aClosedGuardCoversTheButton() {
        let recorder = Recorder()
        let bench = Bench(commands: ConsoleCommands(actions: [PK4.f8: recorder.action()]))
        bench.send(.press(PK4.f8))
        bench.run(for: 3)
        bench.send(.release(PK4.f8))
        #expect(recorder.requests.isEmpty)
        #expect(!bench.snap.button(PK4.f8).capDown)
    }

    @Test func releasingAGuardedHoldEarlySendsNothingAndShowsNothing() {
        let recorder = Recorder()
        let bench = Bench(commands: ConsoleCommands(actions: [PK4.f8: recorder.action()]))
        bench.send(.guard(PK4.f8, open: true))
        bench.send(.press(PK4.f8))
        bench.run(for: 1.9)
        #expect(bench.snap.button(PK4.f8).capDown)
        bench.send(.release(PK4.f8))
        bench.run(for: 1)

        #expect(recorder.requests.isEmpty)
        #expect(bench.snap.cues.relay == 0)
        #expect(bench.snap.button(PK4.f8).phase == .idle)
        #expect(bench.log.events(.commandSent).isEmpty)
    }

    @Test func aTwoSecondHoldPullsTheRelayInAndSends() {
        let recorder = Recorder()
        let bench = Bench(commands: ConsoleCommands(actions: [PK4.f9: recorder.action()]))
        bench.feed(bench.poll(["a"]))
        bench.send(.guard(PK4.f9, open: true))
        bench.send(.press(PK4.f9))
        bench.run(for: 2)

        #expect(bench.snap.cues.relay == 1)
        #expect(recorder.requests.count == 1)
        #expect(recorder.requests.first?.session == "a")
        // The cap is still held down: letting go now changes nothing.
        #expect(bench.snap.button(PK4.f9).capDown)
        bench.send(.release(PK4.f9))
        #expect(bench.snap.button(PK4.f9).phase == .sent)

        // Confirmed: the cap glows for 1.5 s, then the guard falls shut.
        recorder.answer(true)
        #expect(bench.snap.button(PK4.f9).lamp == .on)
        bench.run(for: 1.4)
        #expect(bench.snap.guardsOpen.contains(PK4.f9))
        bench.run(for: 0.2)
        #expect(!bench.snap.guardsOpen.contains(PK4.f9))
        #expect(bench.log.events(.guardLowered).last?.detail == "confirmed")
    }

    @Test func f10NeedsItsKeyAndTheKeyNeedsTheGuardOpen() {
        let recorder = Recorder()
        let bench = Bench(commands: ConsoleCommands(actions: [PK4.f10: recorder.action()]))

        bench.send(.key(PK4.f10, armed: true))
        #expect(!bench.snap.keysArmed.contains(PK4.f10))

        bench.send(.guard(PK4.f10, open: true))
        bench.send(.press(PK4.f10))
        bench.run(for: 2.5)
        bench.send(.release(PK4.f10))
        // Without the key the button travels, and nothing is sent.
        #expect(recorder.requests.isEmpty)

        bench.send(.key(PK4.f10, armed: true))
        #expect(bench.snap.keysArmed.contains(PK4.f10))
        #expect(bench.log.events(.keyArmed).count == 1)
        bench.send(.press(PK4.f10))
        bench.run(for: 2)
        #expect(recorder.requests.count == 1)
    }

    @Test func anOpenGuardFallsAfterFiveIdleSeconds() {
        let bench = Bench()
        bench.send(.guard(PK4.f8, open: true))
        bench.run(for: 4.9)
        #expect(bench.snap.guardsOpen.contains(PK4.f8))
        bench.run(for: 0.2)
        #expect(!bench.snap.guardsOpen.contains(PK4.f8))
        #expect(bench.log.events(.guardLifted).count == 1)
        #expect(bench.log.events(.guardLowered).first?.detail == "idle")
    }

    // MARK: - Round buttons

    @Test func aRoundButtonConfirmsOnlyOnTheObservedState() {
        let recorder = Recorder()
        let bench = Bench(
            commands: ConsoleCommands(actions: [
                PK4.monitorOff: recorder.action(observes: .displayAsleep)
            ]))
        bench.feed([bench.machine(.displayAsleep, .flag(false))])
        #expect(bench.lamp(PK4.lensOff(PK4.monitorOff)) == .on)
        #expect(bench.lamp(PK4.lensOn(PK4.monitorOff)) == .off)

        bench.tap(PK4.monitorOff)
        // Both lenses dark while waiting for the Mac.
        #expect(bench.lamp(PK4.lensOff(PK4.monitorOff)) == .off)
        #expect(bench.lamp(PK4.lensOn(PK4.monitorOff)) == .off)

        // The command saying it worked is not the display going to sleep.
        recorder.answer(true)
        #expect(bench.snap.button(PK4.monitorOff).phase == .sent)

        bench.feed([bench.machine(.displayAsleep, .flag(true))])
        #expect(bench.snap.button(PK4.monitorOff).phase == .confirmed)
        #expect(bench.lamp(PK4.lensOn(PK4.monitorOff)) == .on)
        // A round cap never lights.
        #expect(bench.snap.button(PK4.monitorOff).lamp == .off)
    }

    @Test func aRoundButtonWithNoAnswerStaysDarkUntilTheMachineReportsAgain() {
        let bench = Bench()
        bench.feed([bench.machine(.systemAsleep, .flag(false))])
        bench.tap(PK4.sleepMode)
        bench.run(for: 4.5)
        #expect(bench.snap.button(PK4.sleepMode).phase == .idle)
        #expect(bench.lamp(PK4.lensOff(PK4.sleepMode)) == .off)

        bench.feed([bench.machine(.systemAsleep, .flag(false))])
        #expect(bench.lamp(PK4.lensOff(PK4.sleepMode)) == .on)
    }

    /// FC1 and FC2 are the two Keep Awake modes. Each pair of lenses follows its own mode,
    /// so switching from one to the other moves both.
    @Test func fc1AndFc2SwitchBetweenTheKeepAwakeModes() {
        let recorder = Recorder()
        let bench = Bench(
            commands: ConsoleCommands(actions: [
                PK4.fc1: recorder.action(), PK4.fc2: recorder.action(),
            ]))
        bench.feed([
            bench.machine(.keepAwakeDisplayOn, .flag(false)),
            bench.machine(.keepAwakeDisplayOff, .flag(true)),
        ])
        #expect(bench.lamp(PK4.lensOn(PK4.fc2)) == .on)
        #expect(bench.lamp(PK4.lensOff(PK4.fc1)) == .on)

        bench.tap(PK4.fc1)
        bench.feed([
            bench.machine(.keepAwakeDisplayOn, .flag(true)),
            bench.machine(.keepAwakeDisplayOff, .flag(false)),
        ])
        #expect(bench.snap.button(PK4.fc1).phase == .confirmed)
        #expect(bench.lamp(PK4.lensOn(PK4.fc1)) == .on)
        #expect(bench.lamp(PK4.lensOff(PK4.fc2)) == .on)
        #expect(bench.lamp(PK4.lensOn(PK4.fc2)) == .off)
    }

    @Test func toBeDefinedFunctionsAnswerNothing() {
        let bench = Bench()
        for id in PK4.routine + PK4.guarded { bench.tap(id) }
        bench.run(for: 3.1)
        let noAnswers = bench.log.events(.commandNoAnswer).compactMap(\.instrument)
        #expect(Set(noAnswers) == Set(PK4.routine))
        // FC1 has never reported a state: both of its lenses stay dark.
        #expect(bench.lamp(PK4.lensOn(PK4.fc1)) == .off)
        #expect(bench.lamp(PK4.lensOff(PK4.fc1)) == .off)
    }
}
