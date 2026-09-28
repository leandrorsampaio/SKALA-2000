import AppKit
import ConsoleKit
import ConsoleRuntime
import FakeSources
import Foundation
import HookServer
import KeepAwake
import Observation
import TelemetryKit

/// Everything between the app and the console: when it runs, what it reads, what its
/// outside buttons do.
///
/// - **It keeps running with its window closed**, so the drum totals and the hours in
///   service count what happened while nobody was looking. ⌘Q stops it.
/// - **One reader of `~/.claude`**, running only while MAINS is on and the desk is not
///   playing the scripted day.
/// - **The scripted day** stands in for Claude Code in a folder of its own, so a demo
///   never touches the real totals or the real safety log.
@MainActor
@Observable
final class ConsoleHost {

    private(set) var console: PK4Console?
    /// When a hook event last arrived, for Settings: the desk has no instrument for it.
    private(set) var lastHookEvent: Date?
    private(set) var hookEventCount = 0
    /// When Claude Code last ran the status line command, and whether that run carried the
    /// plan's usage: for Settings, which is how anyone can tell why panel E is dark.
    private(set) var lastStatusline: Date?
    private(set) var statuslineCarriedUsage = false

    var demo: Bool {
        didSet {
            guard demo != oldValue else { return }
            UserDefaults.standard.set(demo, forKey: Keys.demo)
            // A different desk: close this one and open the other.
            guard console != nil else { return }
            close()
            open()
            onConsoleChange()
        }
    }

    /// Told when the console is replaced, so the window can follow the new one.
    @ObservationIgnored var onConsoleChange: () -> Void = {}

    @ObservationIgnored let keepAwake = KeepAwake()
    /// SPEAKERS: the Mac's own speakers, and back.
    @ObservationIgnored let speakers = SpeakerSwitch()
    /// The desk's window, for ON TOP, COMPUTER and MINIMIZE. Set by the app once it exists.
    @ObservationIgnored weak var window: DeskWindowController?
    @ObservationIgnored private var hooks: HookServer?
    /// Why the hook receiver is not listening, if it isn't: for Settings.
    private(set) var hookProblem: String?
    @ObservationIgnored private var consolePowered = false
    @ObservationIgnored private var demoFeed: DemoFeed?
    @ObservationIgnored private var claude: ClaudeCodeFeed?

    enum Keys {
        static let demo = "demo"
    }

    /// For measurements only: `SKALA_BENCH=static` runs the console with no telemetry at
    /// all, `flash` the same with four alarm windows flashing, `demo` the scripted day,
    /// `real` the real feed.
    let bench = ProcessInfo.processInfo.environment["SKALA_BENCH"]

    init() {
        let environment = ProcessInfo.processInfo.environment
        demo =
            environment["SKALA_BENCH"] == "demo"
            || (environment["SKALA_DEMO"].map { $0 == "1" }
                ?? UserDefaults.standard.bool(forKey: Keys.demo))
        keepAwake.onChange = { [weak self] _ in
            // The machine's answer reaches the lenses on the next turn of the run loop,
            // not from inside the press that asked for it.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.console?.ingest(self.keepAwakeReadings())
            }
        }
        // Whoever changed the output, the desk or the Mac's own sound menu.
        speakers.onChange = { [weak self] in self?.deskChanged() }
    }

    /// The folder this desk keeps its memory and logs in.
    var folder: URL {
        demo
            ? ConsoleFolder.url.appendingPathComponent("Demo", isDirectory: true)
            : ConsoleFolder.url
    }

    // MARK: - Lifecycle

    func open() {
        guard console == nil else { return }
        let folder = self.folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Weak: the console holds these commands, and a strong reference back would keep
        // every console the demo switch replaced alive.
        weak var created: PK4Console?
        let console = PK4Console(
            directory: folder, commands: commands(for: { created }), readsMachine: !demo,
            extras: { [weak self] in
                guard let self else { return [] }
                return self.keepAwakeReadings() + self.deskReadings()
            },
            onPower: { [weak self] on in
                self?.consolePowered = on
                self?.updateFeeds()
            })
        created = console
        self.console = console
        console.loadDetailed = window?.showsLoadPanel ?? false
        updateFeeds()
    }

    /// Writes the desk's memory and stops everything it was reading.
    func close() {
        console?.shutDown()
        console = nil
        consolePowered = false
        updateFeeds()
    }

    func quit() {
        close()
        hooks?.stop()
        keepAwake.releaseAll()
        speakers.stop()
    }

    // MARK: - Hooks

    /// The socket Claude Code's hooks reach the app on.
    static var hookSocket: URL { ConsoleFolder.url.appendingPathComponent("hooks.sock") }

    /// Starts listening for hook events. Parsing happens off the main thread, a PostToolUse
    /// body being up to megabytes; only the readings come to the console.
    func listenForHooks() {
        let server = HookServer(socketURL: Self.hookSocket) { [weak self] body in
            let readings = ClaudeHooks.readings(from: body, at: Date())
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.hookEvents(readings) }
            }
        }
        server.refused = { reason in
            Log.hooks("refused \(reason)")
        }
        // The status line: the plan's usage windows go to the desk, the line back to
        // Claude Code. The rest of what the status line is told is dropped here.
        server.statusline = { [weak self] body in
            let readings = ClaudeStatusline.readings(from: body, at: Date())
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.lastStatusline = Date()
                    self.statuslineCarriedUsage = !readings.isEmpty
                    if !readings.isEmpty { self.console?.ingest(readings) }
                }
            }
            return ClaudeStatusline.line(from: body)
        }
        do {
            try server.start()
            hooks = server
            hookProblem = nil
        } catch {
            hookProblem = "\(error)"
            Log.hooks("hook receiver did not start: \(error)")
        }
    }

    var isListeningForHooks: Bool { hooks?.isRunning ?? false }

    // MARK: - Feeds

    private func updateFeeds() {
        if bench == "static" || bench == "flash" { return }
        let wantsClaude = console != nil && consolePowered && !demo
        if wantsClaude {
            if claude == nil {
                let feed = ClaudeCodeFeed { [weak self] batch in
                    guard let self, !self.demo, self.consolePowered else { return }
                    self.console?.ingest(batch)
                }
                feed.start()
                claude = feed
            }
        } else {
            claude?.stop()
            claude = nil
        }

        if console != nil, consolePowered, demo {
            if demoFeed == nil {
                demoFeed = DemoFeed { [weak self] readings in
                    guard let self else { return }
                    self.console?.ingest(readings + self.keepAwakeReadings() + self.deskReadings())
                }
            }
        } else {
            demoFeed?.stop()
            demoFeed = nil
        }
    }

    /// Hook events, already parsed. Only the real console hears them: a demo has sessions
    /// of its own.
    func hookEvents(_ readings: [Reading]) {
        lastHookEvent = Date()
        hookEventCount += 1
        guard !demo, consolePowered else { return }
        console?.ingest(readings)
    }

    /// The Mac woke: read everything afresh once, rather than letting every source that
    /// slept catch up at once.
    func didWake() {
        guard let console, consolePowered else { return }
        console.ingest(keepAwakeReadings())
    }

    // MARK: - Commands

    /// Everything on the desk that reaches outside it. F6 and F7 stay unassigned; see
    /// `SessionCommands` for why.
    ///
    /// A demo reaches no further than Keep Awake, which is harmless and undone by pressing
    /// again: its sessions are made up, and a demo that put the Mac to sleep would be a
    /// poor demo. Everything else answers NO ANSWER, which is the truth.
    private func commands(for console: @escaping @MainActor () -> PK4Console?) -> ConsoleCommands {
        // The desk's own window and the Mac's sound, which a demo may reach too: each is
        // undone by pressing again.
        var actions: [InstrumentID: CommandAction] = [
            PK4.fc1: keepAwakeAction(.displayOn),
            PK4.fc2: keepAwakeAction(.displayOff),
            PK4.onTop: windowAction { $0.setOnTop(!$0.isOnTop) },
            PK4.computer: windowAction { $0.setShowsLoadPanel(!$0.showsLoadPanel) },
            PK4.minimize: CommandAction { [weak self] _, reply in
                reply(self?.window?.minimize() ?? false)
            },
            PK4.speakers: CommandAction { [weak self] _, reply in
                guard let self, self.speakers.toggle() else { return reply(false) }
                DispatchQueue.main.async { [weak self] in self?.deskChanged() }
            },
        ]
        if !demo {
            actions[PK4.sleepMode] = SystemCommands.sleepMode()
            actions[PK4.monitorOff] = SystemCommands.monitorOff()
            let session = SessionCommands.actions(
                details: { console()?.model.details(of: $0) },
                safetyLog: ConsoleFolder.url.appendingPathComponent("safety.log"))
            actions.merge(session) { current, _ in current }
        }
        return ConsoleCommands(actions: actions)
    }

    /// FC1 and FC2 toggle their own Keep Awake mode, and the two exclude each other. The
    /// assertion's new state is the answer, reported as a reading.
    private func keepAwakeAction(_ mode: KeepAwakeMode) -> CommandAction {
        CommandAction { [weak self] _, reply in
            guard let self else { return reply(false) }
            do {
                try self.keepAwake.toggle(mode)
            } catch {
                reply(false)
            }
        }
    }

    /// ON TOP and COMPUTER act on the window; its new state is the answer, reported as a
    /// reading on the next turn of the run loop.
    private func windowAction(
        _ change: @escaping @MainActor (DeskWindowController) -> Void
    ) -> CommandAction {
        CommandAction { [weak self] _, reply in
            guard let self, let window = self.window else { return reply(false) }
            change(window)
            DispatchQueue.main.async { [weak self] in self?.deskChanged() }
        }
    }

    /// What ON TOP, SPEAKERS and COMPUTER show on their lenses.
    func deskReadings() -> [Reading] {
        let now = Date()
        func flag(_ field: Field, _ value: Bool) -> Reading {
            Reading(.machine, field, .flag(value), at: now, ttl: MachineSource.ttl)
        }
        var out = [flag(.builtInSpeakers, speakers.isOnSpeakers)]
        if let window {
            out += [flag(.windowOnTop, window.isOnTop), flag(.loadPanelShown, window.showsLoadPanel)]
        }
        return out
    }

    /// The window or the sound changed: the lenses hear at once, and the load source reads
    /// in full only while panel F can be seen.
    func deskChanged() {
        console?.loadDetailed = window?.showsLoadPanel ?? false
        guard consolePowered else { return }
        console?.ingest(deskReadings())
    }

    /// Which Keep Awake mode is on, for FC1's and FC2's lenses.
    func keepAwakeReadings() -> [Reading] {
        let now = Date()
        return [
            Reading(
                .machine, .keepAwakeDisplayOn, .flag(keepAwake.mode == .displayOn), at: now,
                ttl: MachineSource.ttl),
            Reading(
                .machine, .keepAwakeDisplayOff, .flag(keepAwake.mode == .displayOff), at: now,
                ttl: MachineSource.ttl),
        ]
    }
}

/// The scripted day, played at the speed of the clock on the wall, from 08:55. At 18:00
/// it starts again.
@MainActor
final class DemoFeed {

    private var day = FakeDay.opening(at: Date())
    private var timer: Timer?
    private let deliver: @MainActor ([Reading]) -> Void

    init(deliver: @escaping @MainActor ([Reading]) -> Void) {
        self.deliver = deliver
        timer = Timer.scheduledTimer(withTimeInterval: FakeDay.tick, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 0.2
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        if day.isOver { day = FakeDay.opening(at: Date()) }
        deliver(day.catchUp(to: Date()))
    }
}
