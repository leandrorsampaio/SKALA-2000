import AppKit
import ConsoleKit
import ConsoleRuntime
import DeskArt
import DeskSound
import DeskView
import Observation

/// The console's one window.
///
/// The desk is a fixed drawing of 2500 × 1800 units, so the content is locked to that
/// aspect ratio and never narrower than 1280 points. Full screen on a second display is its
/// intended home; there the desk is fitted and centred. Closing the window closes only the
/// window: the console goes on counting behind it.
@MainActor
final class DeskWindowController: NSObject, NSWindowDelegate {

    static let deskSize = NSSize(width: 2500, height: 1800)
    static let minimumWidth: CGFloat = 1280

    private let host: ConsoleHost
    private let sound: DeskSound
    private let director: DeskDirector
    private(set) var window: NSWindow?
    private(set) var desk: DeskView?
    /// Told once the first art is on screen, for the launch measurement.
    var firstArt: (ArtSet) -> Void = { _ in }
    private var resizeBench: ResizeBench?

    init(host: ConsoleHost, sound: DeskSound, director: DeskDirector) {
        self.host = host
        self.sound = sound
        self.director = director
        super.init()
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let size = Self.deskSize
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1600, height: 1600 * size.height / size.width),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "SKALA-2000 · Operator Console for Claude Code"
        window.contentAspectRatio = size
        window.contentMinSize = NSSize(
            width: Self.minimumWidth, height: Self.minimumWidth * size.height / size.width)
        window.collectionBehavior = [.fullScreenPrimary]
        window.backgroundColor = NSColor(cgColor: Palette.surround) ?? .black
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.tabbingMode = .disallowed

        let desk = DeskView(frame: window.contentLayoutRect)
        desk.autoresizingMask = [.width, .height]
        desk.send = { [weak self] intent in self?.host.console?.send(intent) }
        desk.click = { [weak self] in self?.sound.play(.click) }
        desk.stopClick = { [weak self] in self?.sound.play(.click) }
        var announcedFirst = false
        desk.artRendered = { [weak self] art in
            guard !announcedFirst else { return }
            announcedFirst = true
            self?.firstArt(art)
        }
        window.contentView = desk
        self.desk = desk
        if let snapshot = host.console?.model.snapshot { desk.apply(benched(snapshot)) }

        window.setFrameAutosaveName("SKALA2000Desk")
        if !window.setFrameUsingName("SKALA2000Desk") { window.center() }
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Nothing is focused until Tab is pressed.
        window.makeFirstResponder(desk)
        let environment = ProcessInfo.processInfo.environment
        if environment["SKALA_BENCH_RESIZE"] == "1" {
            resizeBench = ResizeBench(window: window, folder: host.folder)
        }
        if environment["SKALA_BENCH_FULLSCREEN"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { window.toggleFullScreen(nil) }
        }
        if environment["SKALA_BENCH_HIDE"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { window.miniaturize(nil) }
        }
    }

    /// The model changed: the view draws it, only while it can be seen.
    func snapshotChanged(_ snapshot: ConsoleSnapshot) {
        guard let window, let desk, window.occlusionState.contains(.visible) else { return }
        desk.apply(benched(snapshot))
    }

    /// `SKALA_BENCH=flash`: four alarm windows flashing, the buzzer silent.
    private func benched(_ snapshot: ConsoleSnapshot) -> ConsoleSnapshot {
        guard host.bench == "flash" else { return snapshot }
        var s = snapshot
        let count = Int(ProcessInfo.processInfo.environment["SKALA_FLASH_COUNT"] ?? "") ?? 4
        for slot in PK4.slots.prefix(count) { s.lamps[PK4.annunciator(.wait, slot: slot)] = .flash }
        s.buzzer = false
        return s
    }

    /// Back in sight: catch up at once.
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window, window.occlusionState.contains(.visible),
            let snapshot = host.console?.model.snapshot
        else { return }
        desk?.apply(benched(snapshot))
    }

    func windowDidResignKey(_ notification: Notification) {
        desk?.releasePressed()
    }

    func windowWillClose(_ notification: Notification) {
        desk?.releasePressed()
        window = nil
        desk = nil
    }
}
