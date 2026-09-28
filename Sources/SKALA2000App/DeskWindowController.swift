import AppKit
import ConsoleKit
import ConsoleRuntime
import DeskArt
import DeskSound
import DeskView
import Observation

/// The console's one window.
///
/// The desk is a fixed drawing of 3352 × 1800 units, or 2500 × 1800 with panel F hidden, so
/// the content is locked to that aspect ratio and never narrower than 1280 points. The
/// window has no title bar: the desk is the whole window, and bare steel moves it. Full screen on a second display is its
/// intended home; there the desk is fitted and centred. Closing the window closes only the
/// window: the console goes on counting behind it.
@MainActor
final class DeskWindowController: NSObject, NSWindowDelegate {

    static let deskSize = NSSize(width: 3352, height: 1800)
    static let compactSize = NSSize(width: 2500, height: 1800)
    static let minimumWidth: CGFloat = 1280
    private static let loadPanelKey = "showsLoadPanel"

    /// COMPUTER: panel F in view. Hidden until the operator first shows it, then as they
    /// last left it.
    private(set) var showsLoadPanel = UserDefaults.standard.bool(forKey: loadPanelKey)

    /// ON TOP: the window above every other. Off at every launch.
    var isOnTop: Bool { window?.level == .floating }

    private var visibleSize: NSSize { showsLoadPanel ? Self.deskSize : Self.compactSize }

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
        let size = visibleSize
        let window = DeskWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1600, height: 1600 * size.height / size.width),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        // Titled still, for the Window menu, Mission Control and minimising, but the bar and
        // its buttons are gone: the desk reaches the window's top edge.
        window.title = "SKALA-2000 · Operator Console for Claude Code"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.collectionBehavior = [.fullScreenPrimary]
        window.backgroundColor = NSColor(cgColor: Palette.surround) ?? .black
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.tabbingMode = .disallowed

        let desk = DeskView(frame: NSRect(origin: .zero, size: window.frame.size))
        desk.autoresizingMask = [.width, .height]
        desk.showsLoadPanel = showsLoadPanel
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
        // A frame saved with a title bar, or with F the other way, is brought to shape.
        fitToDesk(window, resize: true)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Nothing is focused until Tab is pressed.
        window.makeFirstResponder(desk)
        host.deskChanged()
        let environment = ProcessInfo.processInfo.environment
        if environment["SKALA_BENCH_RESIZE"] == "1" {
            resizeBench = ResizeBench(window: window, folder: host.folder)
        }
        if environment["SKALA_BENCH_FULLSCREEN"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { window.toggleFullScreen(nil) }
        }
        if environment["SKALA_BENCH_APPEARANCE"] == "1" {
            // Day, night, day, night, as the Mac switching Light and Dark would.
            for step in 1...4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 2) {
                    NSApp.appearance = NSAppearance(named: step % 2 == 1 ? .darkAqua : .aqua)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [host] in
                let installs = DeskView.installSeconds.map { String(format: "%.1f", $0 * 1000) }
                let line = "appearance switches: installs \(installs.joined(separator: ", ")) ms\n"
                try? line.write(
                    to: host.folder.appendingPathComponent("appearance.log"), atomically: true,
                    encoding: .utf8)
            }
        }
        if environment["SKALA_BENCH_HIDE"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { window.miniaturize(nil) }
        }
    }

    // MARK: - Panel D's window buttons

    func setOnTop(_ on: Bool) {
        window?.level = on ? .floating : .normal
        host.deskChanged()
    }

    /// Panel F in view or out of it. The window keeps its height and its top left corner,
    /// and grows or shrinks to the right, as far as the screen allows.
    func setShowsLoadPanel(_ shown: Bool) {
        guard shown != showsLoadPanel else { return }
        showsLoadPanel = shown
        UserDefaults.standard.set(shown, forKey: Self.loadPanelKey)
        defer { host.deskChanged() }
        guard let window, let desk else { return }
        desk.showsLoadPanel = shown
        fitToDesk(window, resize: true)
    }

    /// Into the Dock. It stops floating first: a window restored from the Dock comes back
    /// among the others.
    func minimize() -> Bool {
        guard let window, window.styleMask.contains(.miniaturizable) else { return false }
        setOnTop(false)
        window.miniaturize(nil)
        return true
    }

    private func fitToDesk(_ window: NSWindow, resize: Bool) {
        let size = visibleSize
        window.contentAspectRatio = size
        window.contentMinSize = NSSize(
            width: Self.minimumWidth, height: Self.minimumWidth * size.height / size.width)
        // Full screen fits and centres the desk by itself.
        guard resize, !window.styleMask.contains(.fullScreen) else { return }
        let frame = window.frame
        var height = frame.height
        var width = (height * size.width / size.height).rounded()
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        if let screen, width > screen.width {
            width = screen.width
            height = (width * size.height / size.width).rounded()
        }
        var origin = NSPoint(x: frame.minX, y: frame.maxY - height)
        if let screen, origin.x + width > screen.maxX {
            origin.x = max(screen.minX, screen.maxX - width)
        }
        window.setFrame(
            NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true,
            animate: window.isVisible)
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

/// The desk's window. Its title bar buttons are hidden, so Close and Minimize from the menus,
/// which would press them, act directly; Minimize as MINIMIZE WINDOW does, letting go of
/// ON TOP first.
final class DeskWindow: NSWindow {
    override func performClose(_ sender: Any?) {
        close()
    }

    override func performMiniaturize(_ sender: Any?) {
        if let desk = delegate as? DeskWindowController {
            _ = desk.minimize()
        } else {
            miniaturize(sender)
        }
    }
}
