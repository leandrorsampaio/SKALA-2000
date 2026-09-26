import Foundation

/// Puts SKALA-2000's hooks into Claude Code's `settings.json`, and takes them out again.
///
/// Every hook is the same `async` command, piping the hook's JSON to the app's socket. They
/// are told apart from everything else in the file by the socket path they name, so Mac
/// Command Center's hooks and anything the owner wrote stay exactly where they are. The
/// settings are copied to `settings.json.skala-backup` before any write: they are
/// hand-edited and hard to reconstruct.
public struct HookInstaller: Sendable {

    /// What identifies our hooks inside a settings file.
    public static let marker = "SKALA-2000/hooks.sock"

    /// The command every hook runs. `$HOME` is expanded by the shell Claude Code runs it
    /// in, so the file names no user.
    public static let command =
        "curl -sS -m 2 --unix-socket \"$HOME/Library/Application Support/SKALA-2000/hooks.sock\" "
        + "-H 'X-SKALA-Client: 1' -H 'Content-Type: application/json' --data-binary @- "
        + "'http://localhost/v1/events/claude' >/dev/null 2>&1 || true"

    public let settings: URL
    public let events: [String]

    public init(
        settings: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json"),
        events: [String]
    ) {
        self.settings = settings
        self.events = events
    }

    public enum Status: Equatable, Sendable {
        /// Every event has our hook.
        case installed
        /// Some do, some don't: an older version, or a hand edit.
        case partial(missing: [String])
        case notInstalled
        /// The settings file exists but is not JSON we can read; nothing will be written.
        case unreadable
    }

    public enum Failure: Error, Equatable {
        case unreadable
        case writeFailed(String)
    }

    public var backup: URL { settings.appendingPathExtension("skala-backup") }

    // MARK: - Reading

    func load() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settings.path) else { return [:] }
        let data = try Data(contentsOf: settings)
        if data.isEmpty { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unreadable
        }
        return object
    }

    static func isOurs(_ group: Any) -> Bool {
        guard let hooks = (group as? [String: Any])?["hooks"] as? [[String: Any]] else {
            return false
        }
        return hooks.contains { ($0["command"] as? String)?.contains(marker) == true }
    }

    public func status() -> Status {
        guard let settings = try? load() else { return .unreadable }
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        let missing = events.filter { event in
            !((hooks[event] as? [Any]) ?? []).contains(where: Self.isOurs)
        }
        if missing.isEmpty { return .installed }
        return missing.count == events.count ? .notInstalled : .partial(missing: missing)
    }

    // MARK: - Writing

    public func install() throws { try write(installing: true) }

    public func remove() throws { try write(installing: false) }

    private func write(installing: Bool) throws {
        var root: [String: Any]
        do {
            root = try load()
        } catch {
            throw Failure.unreadable
        }
        let existing = root["hooks"] as? [String: Any] ?? [:]
        var merged: [String: Any] = [:]
        for event in Set(existing.keys).union(installing ? Set(events) : []) {
            var groups = ((existing[event] as? [Any]) ?? []).filter { !Self.isOurs($0) }
            if installing, events.contains(event) {
                groups.append([
                    "hooks": [
                        ["type": "command", "command": Self.command, "async": true, "timeout": 5]
                    ]
                ])
            }
            if !groups.isEmpty { merged[event] = groups }
        }
        if merged.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = merged
        }

        let folder = settings.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: settings.path) {
                try? FileManager.default.removeItem(at: backup)
                try FileManager.default.copyItem(at: settings, to: backup)
            }
            var data = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            data.append(0x0A)
            try data.write(to: settings, options: .atomic)
        } catch {
            throw Failure.writeFailed(error.localizedDescription)
        }
    }

    /// The snippet as `scripts/claude-hooks.json` holds it, for anyone who would rather
    /// paste it themselves.
    public func snippet() -> Data {
        var hooks: [String: Any] = [:]
        for event in events {
            hooks[event] = [
                [
                    "hooks": [
                        ["type": "command", "command": Self.command, "async": true, "timeout": 5]
                    ]
                ]
            ]
        }
        return
            (try? JSONSerialization.data(
                withJSONObject: ["hooks": hooks],
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]))
            ?? Data()
    }
}
