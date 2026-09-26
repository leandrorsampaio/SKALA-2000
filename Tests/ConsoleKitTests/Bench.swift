import Foundation
import Testing

@testable import ConsoleKit
@testable import TelemetryKit

/// A console on a clock that only moves when a test moves it.
@MainActor
final class Bench {

    let clock: ManualClock
    let store: MemoryConsoleStore
    let log = MemoryConsoleLog()
    let model: ConsoleModel

    init(
        saved: PersistedConsole? = nil,
        commands: ConsoleCommands = .unassigned,
        poweredOn: Bool = true,
        start: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) {
        clock = ManualClock(start)
        store = MemoryConsoleStore(saved)
        model = ConsoleModel(
            clock: clock, store: store, log: log, commands: commands, poweredOn: poweredOn)
        if poweredOn { run(for: 3) }
    }

    var now: Date { clock.now }
    var snap: ConsoleSnapshot { model.snapshot }

    /// Moves the clock through every deadline on the way, the way the app's driver would.
    func run(for seconds: TimeInterval) {
        let end = clock.now.addingTimeInterval(seconds)
        var steps = 0
        while let due = model.nextDeadline, due <= end {
            steps += 1
            // Nothing should stay overdue after an advance; if it does, that is a bug the
            // test should see rather than hang on.
            precondition(steps < 200_000, "the model keeps asking to be advanced")
            if due > clock.now { clock.now = due }
            model.advance()
        }
        clock.now = end
        model.advance()
    }

    /// Readings in, then enough time for the coalesced snapshot to publish.
    func feed(_ readings: [Reading]) {
        model.ingest(readings)
        run(for: ConsoleTiming.coalesce)
    }

    func send(_ intent: ConsoleIntent) {
        model.send(intent)
    }

    func tap(_ id: InstrumentID) {
        model.send(.press(id))
        model.send(.release(id))
    }

    // MARK: - Readings

    func reading(
        _ key: SessionKey, _ field: Field, _ value: Value, ttl: TimeInterval = 6
    ) -> Reading {
        Reading(.session(key), field, value, at: now, ttl: ttl)
    }

    func machine(_ field: Field, _ value: Value, ttl: TimeInterval = 30) -> Reading {
        Reading(.machine, field, value, at: now, ttl: ttl)
    }

    func roster(_ keys: [SessionKey]) -> Reading {
        Reading(.machine, .roster, .keys(keys), at: now, ttl: 6)
    }

    /// What one `claude agents --json` poll says about a session.
    func agent(
        _ key: SessionKey, status: String = "idle", kind: String = "interactive",
        cwd: String = "/Users/operator/Projects/familyhub", started: Date? = nil
    ) -> [Reading] {
        [
            reading(key, .status, .text(status)),
            reading(key, .kind, .text(kind)),
            reading(key, .cwd, .text(cwd)),
            reading(key, .name, .text(key.rawValue)),
            reading(key, .startedAt, .time(started ?? now)),
        ]
    }

    /// A full poll: the roster plus each session's agent fields.
    func poll(_ keys: [SessionKey], status: String = "idle") -> [Reading] {
        keys.flatMap { agent($0, status: status) } + [roster(keys)]
    }

    func hook(_ key: SessionKey, _ field: Field, ttl: TimeInterval) -> Reading {
        reading(key, field, .event, ttl: ttl)
    }

    /// Keeps sessions alive across a stretch of time, polling every two seconds.
    func keepPolling(_ keys: [SessionKey], for seconds: TimeInterval, status: String = "idle") {
        var left = seconds
        while left > 0 {
            let step = min(2, left)
            run(for: step)
            feed(poll(keys, status: status))
            left -= step
        }
    }

    // MARK: - Reading the desk

    func lamp(_ id: InstrumentID) -> LampState { snap.lamp(id) }

    func lamp(_ row: AnnunciatorRow, _ slot: Int) -> LampState {
        snap.lamp(PK4.annunciator(row, slot: slot))
    }

    func slot(of key: SessionKey) -> Int? { model.slots.slot(of: key) }
}
