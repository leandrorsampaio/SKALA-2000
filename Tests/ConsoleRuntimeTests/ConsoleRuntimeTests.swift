import Foundation
import Testing

@testable import ConsoleKit
@testable import ConsoleRuntime
@testable import TelemetryKit

/// A folder that is gone when the test is.
final class Scratch {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("pk4-runtime-" + UUID().uuidString, isDirectory: true)

    init() { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: url) }

    func files() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }
}

@MainActor
@Suite struct ConsoleFilesTests {

    @Test func theDesksMemoryRoundTrips() {
        let scratch = Scratch()
        let store = FileConsoleStore(directory: scratch.url)
        #expect(store.load() == nil)

        var state = PersistedConsole()
        state.totals.costUSD = 418.7
        _ = state.totals.record(
            .output, value: 3000, for: "s-1", at: Date(timeIntervalSince1970: 1_800_000_000))
        state.selector = 3
        state.pencils = ["familyhub", "", "pk4", ""]
        state.armedKeys = [PK4.f12]
        store.save(state)

        #expect(FileConsoleStore(directory: scratch.url).load() == state)
    }

    /// The drum totals are the one thing nobody can reconstruct: an unreadable file is kept.
    @Test func anUnreadableFileIsMovedAsideNotOverwritten() throws {
        let scratch = Scratch()
        let store = FileConsoleStore(directory: scratch.url)
        try Data("{ this is not json".utf8).write(to: store.url)

        #expect(store.load() == nil)
        #expect(scratch.files().contains { $0.hasPrefix("console.damaged-") })
        store.save(PersistedConsole())
        #expect(store.load() == PersistedConsole())
    }

    @Test func theSafetyLogIsOneJSONObjectPerLine() throws {
        let scratch = Scratch()
        let log = FileConsoleLog(directory: scratch.url)
        let moment = Date(timeIntervalSince1970: 1_800_000_000.25)
        log.safety(
            SafetyEntry(
                at: moment, event: .commandSent, instrument: PK4.f12, slot: 2, session: "s-2"))
        log.safety(SafetyEntry(at: moment, event: .guardLifted, instrument: PK4.f12))

        let lines = try String(contentsOf: log.safetyURL, encoding: .utf8)
            .split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        let first = try #require(
            JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        #expect(first["event"] as? String == "command.sent")
        #expect(first["instrument"] as? String == "b.f12")
        #expect(first["slot"] as? Int == 2)
        #expect(first["session"] as? String == "s-2")
        #expect(first["at"] as? String == "2027-01-15T08:00:00.250Z")
    }

    @Test func theSafetyLogRollsOverRatherThanFillingTheDisk() throws {
        let scratch = Scratch()
        let log = FileConsoleLog(directory: scratch.url, rotateAt: 200)
        for _ in 0..<10 { log.safety(SafetyEntry(at: Date(), event: .mainsOn)) }
        #expect(scratch.files().contains("safety.1.log"))
        let current = try Data(contentsOf: log.safetyURL)
        #expect(current.count < 400)
    }

    @Test func textLinesAreStampedAndReadBack() {
        let scratch = Scratch()
        let log = FileConsoleLog(directory: scratch.url)
        #expect(log.text(["S1 TITLE FamilyHub auth", "S1 BRANCH main"]))
        let text = log.readText()
        #expect(text.contains("  S1 TITLE FamilyHub auth\n"))
        #expect(text.split(separator: "\n").count == 2)
    }

    @Test func aTextLogThatCannotBeWrittenSaysSo() {
        let scratch = Scratch()
        let nowhere = scratch.url.appendingPathComponent("not-a-folder")
        try? Data().write(to: nowhere)
        #expect(!FileConsoleLog(directory: nowhere).text(["S1 NAME x"]))
    }
}

#if !APP_STORE

/// `pmset`, answering whatever the test says.
final class FakePmset: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    var status: Int32 = 0
    private(set) var calls: [[String]] = []

    func run(_ executable: URL, arguments: [String], timeout: TimeInterval) -> CommandOutput? {
        lock.lock()
        defer { lock.unlock() }
        calls.append([executable.path] + arguments)
        return CommandOutput(status: status, stdout: Data())
    }
}

@MainActor
@Suite struct SystemCommandTests {

    func perform(_ action: CommandAction) async throws -> Bool? {
        var answer: Bool?
        action.perform(
            CommandRequest(
                button: PK4.sleepMode, ticket: 1, slot: 1, session: nil, issuedAt: Date())
        ) { answer = $0 }
        try await Task.sleep(for: .milliseconds(300))
        return answer
    }

    /// `pmset` finishing is not the Mac asleep: success says nothing, and the lens waits for
    /// the machine.
    @Test func aCleanExitIsNotConfirmation() async throws {
        let pmset = FakePmset()
        let answer = try await perform(SystemCommands.sleepMode(runner: pmset))
        #expect(pmset.calls == [["/usr/bin/pmset", "sleepnow"]])
        #expect(answer == nil)
        #expect(SystemCommands.sleepMode(runner: pmset).observes == .systemAsleep)
    }

    @Test func aFailureIsNoAnswerAtOnce() async throws {
        let pmset = FakePmset()
        pmset.status = 1
        let answer = try await perform(SystemCommands.monitorOff(runner: pmset))
        #expect(pmset.calls == [["/usr/bin/pmset", "displaysleepnow"]])
        #expect(answer == false)
    }
}

#endif

@MainActor
@Suite(.serialized) struct PK4ConsoleTests {

    /// Real time, real timer: the power-up sequence finishes on its own.
    @Test func theDriverRunsThePowerUpSequenceOnItsOwn() async throws {
        let scratch = Scratch()
        let console = PK4Console(
            directory: scratch.url, commands: .unassigned)
        defer { console.shutDown() }
        #expect(console.model.snapshot.nixie(PK4.selected) == " ")

        // About two seconds, waited for rather than slept: other suites share the main
        // thread, and a busy one delays the timer, not the outcome.
        // SELECTED shows its slot only once the sequence is over and the desk is live.
        let deadline = Date().addingTimeInterval(10)
        while console.model.snapshot.nixie(PK4.selected) != "1", Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(console.model.snapshot.nixie(PK4.selected) == "1")
        #expect(console.model.snapshot.mains)
    }

    @Test func mainsStartsAndStopsTheSources() {
        let scratch = Scratch()
        let console = PK4Console(
            directory: scratch.url, commands: .unassigned)
        defer { console.shutDown() }
        #expect(console.isReadingSources)

        console.send(.mains(false))
        #expect(!console.isReadingSources)
        console.send(.mains(true))
        #expect(console.isReadingSources)
    }

    @Test func shuttingDownWritesTheDesksMemoryAndTheLog() throws {
        let scratch = Scratch()
        let console = PK4Console(
            directory: scratch.url, commands: .unassigned)
        console.send(.pencil(slot: 2, text: "tax"))
        console.send(.mains(false))
        console.shutDown()

        #expect(FileConsoleStore(directory: scratch.url).load()?.pencils[1] == "tax")
        let safety = try String(contentsOf: console.log.safetyURL, encoding: .utf8)
        #expect(safety.contains("\"mains.on\""))
        #expect(safety.contains("\"mains.off\""))
    }

    @Test func theAppsOwnReadingsArriveWithTheMachines() async throws {
        let scratch = Scratch()
        let console = PK4Console(
            directory: scratch.url, commands: .unassigned,
            extras: { [Reading(.machine, .keepAwakeDisplayOff, .flag(true), at: Date(), ttl: 30)] })
        defer { console.shutDown() }
        try await Task.sleep(for: .seconds(2.2))
        #expect(console.model.snapshot.lamp(PK4.lensOn(PK4.fc2)) == .on)
        #expect(console.model.snapshot.lamp(PK4.lensOff(PK4.fc1)) == .off)
    }
}
