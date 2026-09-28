import ConsoleKit
import Foundation
import TelemetryKit

/// Wakes the model exactly when it next has work, and not otherwise.
///
/// One timer, rescheduled after every input. A console with nothing changing wakes a few
/// times a minute — for an expiry, the uptime minute, the hour meter — which is what keeps
/// it idle.
@MainActor
public final class ConsoleDriver {

    private let model: ConsoleModel
    private var timer: Timer?
    private var scheduledFor: Date?

    public init(model: ConsoleModel) {
        self.model = model
    }

    /// Call after anything reaches the model.
    public func poke() {
        guard let due = model.nextDeadline else {
            stop()
            return
        }
        if let scheduledFor, scheduledFor == due, timer?.isValid == true { return }
        timer?.invalidate()
        let timer = Timer(fire: max(due, Date()), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        // The power-up strikes its nixie rows 40 ms apart.
        timer.tolerance = 0.004
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        scheduledFor = due
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        scheduledFor = nil
    }

    private func fire() {
        timer = nil
        scheduledFor = nil
        model.advance()
        poke()
    }
}

/// The PK-4 console, running: the model, its files, its timer and the Mac's own readings,
/// started and stopped with MAINS.
///
/// Views talk to `send` and read `model.snapshot`. Claude Code's readings come from the
/// app, which shares one reader of `~/.claude` between the console and the menu bar panel:
/// `onPower` tells it when the console starts and stops wanting them, which is how MAINS
/// off stops the polling. The app also hands in the commands that reach outside the
/// console, and readings of its own, such as which Keep Awake mode is on.
@MainActor
public final class PK4Console {

    public let model: ConsoleModel
    public let log: FileConsoleLog
    public let directory: URL

    private let driver: ConsoleDriver
    private let extras: @MainActor () -> [Reading]
    private let readsMachine: Bool
    private let onPower: @MainActor (Bool) -> Void
    private var machine: MachineSource?
    private var sourcesRunning = false

    /// - Parameters:
    ///   - directory: where the desk's memory and its logs are kept.
    ///   - commands: how the buttons that reach outside the console are carried out.
    ///   - readsMachine: whether to read the Mac's power and sleep. Off for the scripted
    ///     day, which brings its own.
    ///   - extras: readings the app contributes, collected with each machine reading.
    ///   - onPower: told when the console starts and stops wanting readings.
    public init(
        directory: URL = ConsoleFolder.url,
        commands: ConsoleCommands,
        readsMachine: Bool = true,
        extras: @escaping @MainActor () -> [Reading] = { [] },
        onPower: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.directory = directory
        self.extras = extras
        self.readsMachine = readsMachine
        self.onPower = onPower
        log = FileConsoleLog(directory: directory)
        model = ConsoleModel(
            clock: SystemClock(), store: FileConsoleStore(directory: directory), log: log,
            commands: commands)
        driver = ConsoleDriver(model: model)
        syncSources()
        driver.poke()
    }

    public func send(_ intent: ConsoleIntent) {
        model.send(intent)
        syncSources()
        driver.poke()
    }

    public func ingest(_ readings: [Reading]) {
        guard !readings.isEmpty else { return }
        model.ingest(readings)
        driver.poke()
    }

    /// A pass of a source: its readings, and anything it could not read.
    public func ingest(_ batch: TelemetryBatch) {
        batch.issues.forEach(model.report)
        ingest(batch.readings)
    }

    /// The paint, from Settings. Saved soon after, even with MAINS off.
    public func setFinish(_ finish: Finish) {
        model.setFinish(finish)
        driver.poke()
    }

    /// Whether alarms sound the buzzer, from Settings. Saved soon after, like the paint.
    public func setBuzzerMuted(_ muted: Bool) {
        model.setBuzzerMuted(muted)
        driver.poke()
    }

    /// Stops everything and writes the desk's memory. Call before letting go of it.
    public func shutDown() {
        stopSources()
        driver.stop()
        model.flush()
    }

    public var isReadingSources: Bool { sourcesRunning }

    // MARK: - Sources follow MAINS

    private func syncSources() {
        model.isPowered ? startSources() : stopSources()
    }

    private func startSources() {
        guard !sourcesRunning else { return }
        sourcesRunning = true
        if readsMachine {
            let machine = MachineSource { [weak self] readings in
                guard let self else { return }
                self.ingest(readings + self.extras())
            }
            machine.start()
            self.machine = machine
        }
        onPower(true)
    }

    private func stopSources() {
        guard sourcesRunning else { return }
        sourcesRunning = false
        machine?.stop()
        machine = nil
        onPower(false)
    }
}
