import AppKit
import DeskView

/// The console's one window.
///
/// The desk is a fixed drawing of 2500 × 1800 units, so the content is locked to that
/// aspect ratio and never narrower than 1280 points. Full screen on a second display is its
/// intended home.
@MainActor
final class DeskWindowController: NSObject, NSWindowDelegate {

    static let deskSize = NSSize(width: 2500, height: 1800)
    static let minimumWidth: CGFloat = 1280

    private var window: NSWindow?

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
        window.backgroundColor = NSColor(
            red: 0x1A / 255, green: 0x1C / 255, blue: 0x1B / 255, alpha: 1)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = DeskView(frame: window.contentLayoutRect)
        window.setFrameAutosaveName("SKALA2000Desk")
        if !window.setFrameUsingName("SKALA2000Desk") { window.center() }
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
