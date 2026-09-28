import AppKit
import ConsoleKit
import HookServer
import SwiftUI

/// Preferences, in an ordinary macOS window: it is not the desk, and may look like macOS.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private let settings: AppSettings
    private var window: NSWindow?

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
    }

    func show() {
        settings.refreshHooks()
        settings.refreshStatusline()
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(
            rootView: SettingsView(settings: settings, host: settings.host))
        let window = NSWindow(contentViewController: controller)
        window.title = "SKALA-2000 Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let host: ConsoleHost

    var body: some View {
        Form {
            Section("Desk") {
                Picker("Paint", selection: $settings.finish) {
                    Text("Grey-green enamel").tag(Finish.greyGreen)
                    Text("Ivory enamel").tag(Finish.ivory)
                    Text("Matte graphite").tag(Finish.graphite)
                }
                Toggle("Lamp designators (HL numbers) on the windows", isOn: $settings.lampCodes)
                Text("Day and night follow the Mac's Light and Dark appearance.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Sound") {
                Toggle("Sound", isOn: $settings.soundOn)
                HStack {
                    Text("Volume")
                    Slider(value: $settings.volume, in: 0...1)
                }
                .disabled(!settings.soundOn)
                Toggle("Buzzer muted", isOn: $settings.buzzerMuted)
                Text("Muted, alarms still flash. BUZZER TEST sounds regardless.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Claude Code hooks") {
                LabeledContent("Hooks in ~/.claude/settings.json") { Text(hookText) }
                LabeledContent("Receiver") {
                    Text(
                        host.isListeningForHooks
                            ? "listening" : (host.hookProblem ?? "not listening"))
                }
                LabeledContent("Last event") {
                    if let last = host.lastHookEvent {
                        Text(last, format: .relative(presentation: .named))
                    } else {
                        Text("none since launch")
                    }
                }
                HStack {
                    Button("Install hooks") { settings.installHooks() }
                        .disabled(settings.hookStatus == .installed)
                    Button("Remove hooks") { settings.removeHooks() }
                        .disabled(settings.hookStatus == .notInstalled)
                }
                if let problem = settings.hookProblem {
                    Text(problem).font(.caption).foregroundStyle(.red)
                }
                Text(
                    "Hooks tell the desk what just happened: waiting, turn done, agent done. Your settings are copied to settings.json.skala-backup first; Mac Command Center's hooks and your own are left as they are. Restart running sessions to pick the change up."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Claude Code status line") {
                LabeledContent("Status line in ~/.claude/settings.json") { Text(statuslineText) }
                HStack {
                    Button("Install status line") { settings.installStatusline() }
                        .disabled(settings.statuslineStatus != .notInstalled)
                    Button("Remove status line") { settings.removeStatusline() }
                        .disabled(settings.statuslineStatus != .installed)
                }
                if let problem = settings.statuslineProblem {
                    Text(problem).font(.caption).foregroundStyle(.red)
                }
                Text(
                    "The status line tells panel E how much of your plan's 5-hour and weekly limits you have used. Claude Code shows the model, the context used and both limits under its prompt, and stops showing most of its footer hints, as with any status line."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Running") {
                Toggle("Play the scripted day (demo)", isOn: $settings.demo)
                Toggle(
                    "Open at login",
                    isOn: Binding(
                        get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
                if let problem = settings.launchAtLoginProblem {
                    Text(problem).font(.caption).foregroundStyle(.red)
                }
                Text("Closing the window keeps the desk counting. Quit with ⌘Q.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Files") {
                HStack {
                    Button("Open data folder") { settings.openDataFolder() }
                    Button("Open safety log") { settings.openSafetyLog() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize()
    }

    private var statuslineText: String {
        switch settings.statuslineStatus {
        case .installed: "installed"
        case .notInstalled: "not installed"
        case .otherStatusline: "another status line is configured"
        case .unreadable: "settings.json could not be read"
        }
    }

    private var hookText: String {
        switch settings.hookStatus {
        case .installed: "installed"
        case .notInstalled: "not installed"
        case .partial(let missing): "partly installed (\(missing.count) missing)"
        case .unreadable: "settings.json could not be read"
        }
    }
}
