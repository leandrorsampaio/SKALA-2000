import AppKit

/// The standard menu bar, with the console's own few commands.
@MainActor
enum MainMenu {

    struct Actions {
        var showDesk: () -> Void
        var showSettings: () -> Void
        var showTextLog: () -> Void
        var openSafetyLog: () -> Void
        var openDataFolder: () -> Void
        /// MAINS, now the desk has no switch for it.
        var toggleMains: () -> Void
        var mainsOn: () -> Bool
    }

    static func build(_ actions: Actions) -> NSMenu {
        let main = NSMenu()
        let target = MenuTarget.shared
        target.actions = actions

        func item(
            _ title: String, _ action: Selector?, _ key: String = "",
            _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil
        ) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = target
            return item
        }

        let app = NSMenu(title: "SKALA-2000")
        app.addItem(item("About SKALA-2000", #selector(MenuTarget.about), target: target))
        app.addItem(.separator())
        app.addItem(item("Settings…", #selector(MenuTarget.settings), ",", target: target))
        app.addItem(.separator())
        let services = NSMenu(title: "Services")
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        NSApp.servicesMenu = services
        app.addItem(servicesItem)
        app.addItem(.separator())
        app.addItem(item("Hide SKALA-2000", #selector(NSApplication.hide(_:)), "h"))
        app.addItem(
            item(
                "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h",
                [.command, .option]))
        app.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        app.addItem(.separator())
        app.addItem(item("Quit SKALA-2000", #selector(NSApplication.terminate(_:)), "q"))
        add(app, to: main)

        let file = NSMenu(title: "File")
        file.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), "w"))
        add(file, to: main)

        // The pencil strips are text fields: they need the edit commands.
        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", Selector(("undo:")), "z"))
        edit.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        add(edit, to: main)

        let console = NSMenu(title: "Console")
        console.addItem(item("Desk", #selector(MenuTarget.desk), "1", target: target))
        console.addItem(item("Text Log", #selector(MenuTarget.textLog), "l", target: target))
        console.addItem(
            item(
                "Safety Log", #selector(MenuTarget.safetyLog), "l", [.command, .shift],
                target: target))
        console.addItem(.separator())
        console.addItem(
            item("Mains", #selector(MenuTarget.mains), "m", [.command, .shift], target: target))
        console.addItem(.separator())
        console.addItem(item("Open Data Folder", #selector(MenuTarget.dataFolder), target: target))
        add(console, to: main)

        let view = NSMenu(title: "View")
        view.addItem(
            item(
                "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f",
                [.command, .control]))
        add(view, to: main)

        let window = NSMenu(title: "Window")
        window.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        window.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        window.addItem(.separator())
        window.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        NSApp.windowsMenu = window
        add(window, to: main)

        let help = NSMenu(title: "Help")
        NSApp.helpMenu = help
        add(help, to: main)
        return main
    }

    private static func add(_ menu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
    }
}

@MainActor
final class MenuTarget: NSObject, NSMenuItemValidation {
    static let shared = MenuTarget()
    var actions: MainMenu.Actions?

    @objc func about() {
        let credits = NSAttributedString(
            string:
                "Operator Console for Claude Code, type DD-72.\nInstrument Works No 4 · Dresden · 1972.\n\nFonts: Barlow Condensed, Dosis, Nixie One, Permanent Marker and Caveat, under the SIL Open Font License and the Apache License.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
            ])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func settings() { actions?.showSettings() }
    @objc func desk() { actions?.showDesk() }
    @objc func textLog() { actions?.showTextLog() }
    @objc func safetyLog() { actions?.openSafetyLog() }
    @objc func dataFolder() { actions?.openDataFolder() }
    @objc func mains() { actions?.toggleMains() }

    /// MAINS shows a check while the desk has power.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(mains) { item.state = actions?.mainsOn() == true ? .on : .off }
        return true
    }
}
