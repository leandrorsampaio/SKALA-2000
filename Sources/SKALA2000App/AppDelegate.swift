import AppKit
import ConsoleKit
import ConsoleRuntime
import DeskArt
import DeskSound
import DeskView
import Observation
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let host = ConsoleHost()
    let sound = DeskSound()
    private(set) lazy var director = DeskDirector(sound: sound)
    private var desk: DeskWindowController?
    private var bench: BenchLog?
    /// The snapshot tracker currently armed; see `follow`.
    private var following = 0
    private lazy var settings = AppSettings(host: host, sound: sound)
    private lazy var settingsWindow = SettingsWindowController(settings: settings)
    private lazy var textLog = TextLogWindowController { [weak self] in
        self?.host.console?.log.readText(lastCharacters: 200_000) ?? ""
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DeskFonts.register()
        ArtCache.shared.usesDisk = true
        NSApp.mainMenu = MainMenu.build(
            MainMenu.Actions(
                showDesk: { [weak self] in self?.desk?.show() },
                showSettings: { [weak self] in self?.settingsWindow.show() },
                showTextLog: { [weak self] in self?.textLog.show() },
                openSafetyLog: { [weak self] in self?.settings.openSafetyLog() },
                openDataFolder: { [weak self] in self?.settings.openDataFolder() },
                toggleMains: { [weak self] in
                    guard let console = self?.host.console else { return }
                    console.send(.mains(!console.model.snapshot.mains))
                },
                mainsOn: { [weak self] in self?.host.console?.model.snapshot.mains ?? false }))
        // Before the console opens: the model reads its memory when it starts.
        if host.bench == nil { MemoryImport.offerIfDue() }
        host.open()
        bench = BenchLog(folder: ConsoleFolder.url)
        DeskView.recordsTimings = bench != nil
        host.listenForHooks()
        director.openLog = { [weak self] in self?.textLog.show() }
        observeSleep()
        host.onConsoleChange = { [weak self] in self?.consoleChanged() }
        director.announce = { words in
            // An alarm is announced as it is raised, so a VoiceOver user hears it.
            NSAccessibility.post(
                element: NSApp.mainWindow as Any, notification: .announcementRequested,
                userInfo: [
                    .announcement: words, .priority: NSAccessibilityPriorityLevel.high.rawValue,
                ])
        }
        if let snapshot = host.console?.model.snapshot { director.hear(snapshot) }
        follow()

        let desk = DeskWindowController(host: host, sound: sound, director: director)
        desk.firstArt = { art in
            let seconds = Date().timeIntervalSince(ProcessStart.date)
            let line =
                "launch to desk \(Int(seconds * 1000)) ms, art \(Int(art.renderSeconds * 1000)) ms at \(art.scale)"
            Log.performance(line)
            if ProcessInfo.processInfo.environment["SKALA_BENCH"] != nil {
                let url = ConsoleFolder.url.appendingPathComponent("launch.log")
                let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                try? (old + line + "\n").write(to: url, atomically: true, encoding: .utf8)
            }
        }
        self.desk = desk
        settings.applyToDesk = { [weak self] in
            guard let self else { return }
            self.desk?.desk?.lampCodes = self.settings.lampCodes
        }
        desk.show()
        settings.applyToDesk()
        if ProcessInfo.processInfo.environment["SKALA_SHOW_SETTINGS"] == "1" {
            settingsWindow.show()
        }
    }

    /// The relays, the buzzer and the window follow the model, not the view: a hidden
    /// console still sounds its alarms.
    ///
    /// One tracker at a time. A replaced console re-arms from `consoleChanged` while the
    /// old tracker, fired by the same change, would re-arm too: the ticket retires it.
    private func follow() {
        following += 1
        let ticket = following
        withObservationTracking {
            _ = host.console?.model.snapshot
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, ticket == self.following else { return }
                if let snapshot = self.host.console?.model.snapshot {
                    self.director.hear(snapshot)
                    self.desk?.snapshotChanged(snapshot)
                }
                self.follow()
            }
        }
    }

    private func consoleChanged() {
        if let snapshot = host.console?.model.snapshot {
            director.hear(snapshot)
            desk?.snapshotChanged(snapshot)
        }
        follow()
    }

    /// The owner runs the MacBook closed on AC with a 5K display; losing the display sends
    /// it to sleep. On wake, the Keep Awake lenses are read afresh once, and the view
    /// re-renders for whatever screen it is on now.
    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.host.didWake() }
        }
    }

    /// Closing the window keeps the console running; the Dock icon brings it back.
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag { desk?.show() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        sound.stop()
        host.quit()
    }
}

/// The app's own log lines, in the unified log under its subsystem.
enum Log {
    static let subsystem = "com.leandrorossisampaio.skala2000"
    private static let perf = OSLogShim(category: "performance")
    private static let hook = OSLogShim(category: "hooks")

    static func performance(_ message: String) { perf.log(message) }
    static func hooks(_ message: String) { hook.log(message) }
}

struct OSLogShim {
    let logger: Logger
    init(category: String) { logger = Logger(subsystem: Log.subsystem, category: category) }
    func log(_ message: String) { logger.notice("\(message, privacy: .public)") }
}
