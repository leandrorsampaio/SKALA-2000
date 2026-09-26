import AppKit
import ConsoleKit
import ConsoleRuntime

/// A one-time offer, on first launch, to carry on from the PK-4 desk in Mac Command Center:
/// its drum totals, hours in service, pencils, selector, paint and buzzer setting, which
/// live in one file, `console.json`. Only that file is copied, never the logs, and only
/// before SKALA-2000 has a memory of its own.
@MainActor
enum MemoryImport {

    static let old = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support/MacCommandCenter/PK-4/console.json")
    static var new: URL { ConsoleFolder.url.appendingPathComponent("console.json") }
    static let offeredKey = "pk4ImportOffered"

    static var isDue: Bool {
        !UserDefaults.standard.bool(forKey: offeredKey)
            && FileManager.default.fileExists(atPath: old.path)
            && !FileManager.default.fileExists(atPath: new.path)
    }

    static func read(_ url: URL) -> PersistedConsole? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PersistedConsole.self, from: data)
    }

    /// Asks, and copies if the answer is yes. Call before the console opens: the model reads
    /// its memory when it starts.
    static func offerIfDue() {
        guard isDue, let memory = read(old) else { return }
        UserDefaults.standard.set(true, forKey: offeredKey)
        let alert = NSAlert()
        alert.messageText = "Carry on from the PK-4 desk?"
        let hours = Int(memory.serviceSeconds / 3600)
        alert.informativeText = String(
            format:
                "Mac Command Center's PK-4 console has counted $%.0f, %.0f thousand output tokens, %.0f lines added and %.0f removed, and %d hours in service. SKALA-2000 can start from there.\n\nThis copies the desk's memory once: the totals, the hours, the pencil strips, the selector, the paint and the buzzer setting. The safety and text logs stay where they are.",
            memory.totals.costUSD, memory.totals.outputTokens / 1000, memory.totals.linesAdded,
            memory.totals.linesRemoved, hours)
        alert.addButton(withTitle: "Carry On")
        alert.addButton(withTitle: "Start Fresh")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? FileManager.default.copyItem(at: old, to: new)
    }
}
