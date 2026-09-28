import AppKit
import ConsoleKit
import ConsoleRuntime
import DeskSound
import HookServer
import Observation
import ServiceManagement
import TelemetryKit

/// Everything the Settings window changes, in one place. The desk's own memory (finish,
/// buzzer muted) lives in the console model and is saved with the drum totals; the rest
/// are this Mac's preferences.
@MainActor
@Observable
final class AppSettings {

    @ObservationIgnored let host: ConsoleHost
    @ObservationIgnored let sound: DeskSound
    @ObservationIgnored var applyToDesk: () -> Void = {}

    enum Keys {
        static let soundOn = "soundOn"
        static let volume = "volume"
        static let lampCodes = "lampCodes"
    }

    init(host: ConsoleHost, sound: DeskSound) {
        self.host = host
        self.sound = sound
        let defaults = UserDefaults.standard
        soundOn = defaults.object(forKey: Keys.soundOn) as? Bool ?? true
        volume = defaults.object(forKey: Keys.volume) as? Double ?? 0.8
        lampCodes = defaults.object(forKey: Keys.lampCodes) as? Bool ?? true
        apply()
        refreshHooks()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var soundOn: Bool {
        didSet {
            UserDefaults.standard.set(soundOn, forKey: Keys.soundOn)
            apply()
        }
    }

    var volume: Double {
        didSet {
            UserDefaults.standard.set(volume, forKey: Keys.volume)
            apply()
        }
    }

    /// Whether lamp windows carry their HL designator under the lettering.
    var lampCodes: Bool {
        didSet {
            UserDefaults.standard.set(lampCodes, forKey: Keys.lampCodes)
            applyToDesk()
        }
    }

    private func apply() {
        sound.isEnabled = soundOn
        sound.volume = Float(volume)
    }

    // MARK: - The desk's memory

    var finish: Finish {
        get {
            access(keyPath: \.finish)
            return host.console?.model.snapshot.finish ?? .greyGreen
        }
        set {
            withMutation(keyPath: \.finish) { host.console?.setFinish(newValue) }
        }
    }

    var buzzerMuted: Bool {
        get {
            access(keyPath: \.buzzerMuted)
            return host.console?.model.buzzerMuted ?? false
        }
        set {
            withMutation(keyPath: \.buzzerMuted) { host.console?.setBuzzerMuted(newValue) }
        }
    }

    var demo: Bool {
        get { host.demo }
        set { host.demo = newValue }
    }

    // MARK: - Launch at login

    var launchAtLogin = false
    var launchAtLoginProblem: String?

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginProblem = nil
        } catch {
            launchAtLoginProblem = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Hooks

    var hookStatus: HookInstaller.Status = .notInstalled
    var hookProblem: String?

    var installer: HookInstaller { HookInstaller(events: ClaudeHooks.events) }

    func refreshHooks() { hookStatus = installer.status() }

    func installHooks() {
        do {
            try installer.install()
            hookProblem = nil
        } catch {
            hookProblem = "\(error)"
        }
        refreshHooks()
    }

    func removeHooks() {
        do {
            try installer.remove()
            hookProblem = nil
        } catch {
            hookProblem = "\(error)"
        }
        refreshHooks()
    }

    // MARK: - Files

    func openDataFolder() {
        NSWorkspace.shared.open(ConsoleFolder.url)
    }

    func openSafetyLog() {
        let url = host.folder.appendingPathComponent("safety.log")
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(host.folder)
        }
    }
}
