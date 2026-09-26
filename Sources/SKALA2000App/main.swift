import AppKit

// A regular Dock app with a standard menu bar. `NSApplicationMain` would look for a nib;
// this app has none, so the delegate is wired by hand.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
