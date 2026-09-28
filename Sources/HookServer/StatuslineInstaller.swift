import Foundation

/// Puts SKALA-2000's status line command into Claude Code's `settings.json`, and takes it
/// out again.
///
/// Claude Code hands its status line command the plan's usage windows, which nothing else
/// reports. The command posts that JSON to the app's socket and prints the line the app
/// answers with; with the app closed it prints nothing. There is one status line per
/// settings file: one someone else configured is never replaced. The settings are copied to
/// `settings.json.skala-backup` before any write, and a linked file stays linked.
public struct StatuslineInstaller: Sendable {

    /// What identifies our command inside a settings file.
    public static let marker = HookInstaller.marker

    public static let command =
        "curl -sS -m 1 --unix-socket \"$HOME/Library/Application Support/SKALA-2000/hooks.sock\" "
        + "-H 'X-SKALA-Client: 1' -H 'Content-Type: application/json' --data-binary @- "
        + "'http://localhost\(HookServer.statuslinePath)' 2>/dev/null || true"

    public let settings: URL

    public init(
        settings: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    ) {
        self.settings = settings
    }

    public enum Status: Equatable, Sendable {
        case installed
        case notInstalled
        /// Someone else's status line is configured; SKALA-2000's would replace it.
        case otherStatusline
        case unreadable
    }

    public enum Failure: Error, Equatable {
        case unreadable
        case otherStatusline
        case writeFailed(String)
    }

    public var backup: URL { settings.appendingPathExtension("skala-backup") }

    public static func isOurs(_ statusLine: Any?) -> Bool {
        guard let fields = statusLine as? [String: Any], let command = fields["command"] as? String
        else { return false }
        return command.contains(marker) && command.contains(HookServer.statuslinePath)
    }

    func load() throws -> [String: Any] {
        let file = settings.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        let data = try Data(contentsOf: file)
        if data.isEmpty { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unreadable
        }
        return object
    }

    public func status() -> Status {
        guard let root = try? load() else { return .unreadable }
        guard let current = root["statusLine"] else { return .notInstalled }
        return Self.isOurs(current) ? .installed : .otherStatusline
    }

    public func install() throws {
        var root: [String: Any]
        do { root = try load() } catch { throw Failure.unreadable }
        if let current = root["statusLine"], !Self.isOurs(current) {
            throw Failure.otherStatusline
        }
        root["statusLine"] = ["type": "command", "command": Self.command, "padding": 0]
        try write(root)
    }

    public func remove() throws {
        var root: [String: Any]
        do { root = try load() } catch { throw Failure.unreadable }
        guard Self.isOurs(root["statusLine"]) else { return }
        root.removeValue(forKey: "statusLine")
        try write(root)
    }

    private func write(_ root: [String: Any]) throws {
        // A settings file kept with someone's dotfiles is written where it lives.
        let file = settings.resolvingSymlinksInPath()
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                try? FileManager.default.removeItem(at: backup)
                try FileManager.default.copyItem(at: file, to: backup)
            }
            var data = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            data.append(0x0A)
            // Atomic, and the file keeps its permissions.
            try data.write(to: file, options: .atomic)
        } catch {
            throw Failure.writeFailed(error.localizedDescription)
        }
    }
}
