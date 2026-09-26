import CoreText
import Foundation

/// The five bundled faces, registered for this process only.
///
/// Digits are never set in a system font: if a face is missing, what Core Text falls back
/// to is a fault, not a choice, and `DeskFonts.missing` says which.
public enum DeskFonts {

    public static let barlowSemiBold = "BarlowCondensed-SemiBold"
    public static let barlowBold = "BarlowCondensed-Bold"
    public static let dosis = "Dosis-SemiBold"
    public static let nixie = "NixieOne-Regular"
    public static let marker = "PermanentMarker-Regular"
    public static let pencil = "Caveat-Regular"
    /// The PROGRAM BUILD card is typed. Courier New ships with macOS.
    public static let typewriter = "CourierNewPSMT"

    public static let bundled = [barlowSemiBold, barlowBold, dosis, nixie, marker, pencil]

    private static let lock = NSLock()
    nonisolated(unsafe) private static var registered = false

    /// Registers the faces. Safe to call from any thread, and more than once.
    public static func register(from folder: URL? = nil) {
        lock.lock()
        defer { lock.unlock() }
        guard !registered, let folder = folder ?? defaultFolder,
            let files = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil)
        else { return }
        let fonts = files.filter { $0.pathExtension == "ttf" }
        CTFontManagerRegisterFontURLs(fonts as CFArray, .process, true, nil)
        registered = true
    }

    /// Faces that did not register, by PostScript name. Empty when all is well.
    public static var missing: [String] {
        register()
        return bundled.filter { name in
            let font = CTFontCreateWithName(name as CFString, 12, nil)
            return (CTFontCopyPostScriptName(font) as String) != name
        }
    }

    /// Inside the app bundle, or the repository when run from `swift test` or `swift run`.
    public static var defaultFolder: URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Fonts/PK4"),
            FileManager.default.fileExists(atPath: bundled.path)
        {
            return bundled
        }
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Fonts/PK4")
        return FileManager.default.fileExists(atPath: repository.path) ? repository : nil
    }
}
