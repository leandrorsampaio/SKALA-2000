import AppKit
import ConsoleKit
import ConsoleRuntime
import DeskArt
import DeskSound
import Observation
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let host = ConsoleHost()
    let sound = DeskSound()
    private(set) lazy var director = DeskDirector(sound: sound)
    private var desk: DeskWindowController?
    private var bench: BenchLog?
    private lazy var textLog = TextLogWindowController { [weak self] in
        self?.host.console?.log.readText(lastCharacters: 200_000) ?? ""
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DeskFonts.register()
        host.open()
        bench = BenchLog(folder: ConsoleFolder.url)
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
        desk.show()
    }

    /// The relays, the buzzer and the window follow the model, not the view: a hidden
    /// console still sounds its alarms.
    private func follow() {
        withObservationTracking {
            _ = host.console?.model.snapshot
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
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
