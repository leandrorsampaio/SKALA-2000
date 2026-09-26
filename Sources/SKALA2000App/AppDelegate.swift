import AppKit
import DeskArt

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var desk: DeskWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DeskFonts.register()
        let desk = DeskWindowController()
        self.desk = desk
        desk.show()
    }

    /// Closing the window keeps the console running; the Dock icon brings it back.
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    )
        -> Bool
    {
        if !flag { desk?.show() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
