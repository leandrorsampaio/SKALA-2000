import ConsoleKit
import Foundation
import TelemetryKit

/// Where the console keeps its files: `~/Library/Application Support/SKALA-2000/`.
///
/// SKALA-2000 is a direct-distribution app without the App Sandbox (it must read
/// `~/.claude`), so this is the real folder in the user's Library, never a container.
public enum ConsoleFolder {
    public static let name = "SKALA-2000"

    public static var url: URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(
                "Library/Application Support")
        let folder = base.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

/// The desk's memory as one JSON file, `console.json`.
///
/// Written whole and atomically, so a crash mid-write leaves the previous copy. A file that
/// cannot be read at all is moved aside rather than overwritten: the drum totals are the
/// one thing here nobody can reconstruct, and a person may want them back.
@MainActor
public final class FileConsoleStore: ConsoleStore {

    public let url: URL

    public init(directory: URL) {
        url = directory.appendingPathComponent("console.json")
    }

    public func load() -> PersistedConsole? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try Self.decoder.decode(PersistedConsole.self, from: data)
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = url.deletingPathExtension().appendingPathExtension("damaged-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            return nil
        }
    }

    public func save(_ state: PersistedConsole) {
        guard let data = try? Self.encoder.encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// The safety log and the text log, as two files beside the desk's memory.
///
/// `safety.log` is append-only, one JSON object per line: every command and how it ended,
/// every guard lift and key turn, every alarm, every source error. When it passes 10 MB it
/// becomes `safety.1.log` and a new one starts, so it never fills a disk and the last
/// stretch is always kept.
///
/// `text.log` is what PRINT TO LOG writes: the console's only way to show a string. Each
/// line is stamped with local time, because a person reads it.
@MainActor
public final class FileConsoleLog: ConsoleLog {

    public let safetyURL: URL
    public let textURL: URL
    private let rotateAt: Int

    public init(directory: URL, rotateAt: Int = 10 * 1024 * 1024) {
        safetyURL = directory.appendingPathComponent("safety.log")
        textURL = directory.appendingPathComponent("text.log")
        self.rotateAt = rotateAt
    }

    public func safety(_ entry: SafetyEntry) {
        guard var line = try? Self.encoder.encode(entry) else { return }
        line.append(UInt8(ascii: "\n"))
        rotateIfFull()
        _ = append(line, to: safetyURL)
    }

    public func text(_ lines: [String]) -> Bool {
        let stamp = Self.stamp.string(from: Date())
        let text = lines.map { "\(stamp)  \($0)\n" }.joined()
        return append(Data(text.utf8), to: textURL)
    }

    /// The text log as it stands, for the log window. A log that has grown for months is
    /// shown from its most recent part.
    public func readText(lastCharacters limit: Int = .max) -> String {
        let text = (try? String(contentsOf: textURL, encoding: .utf8)) ?? ""
        return text.count > limit ? String(text.suffix(limit)) : text
    }

    private func rotateIfFull() {
        let size =
            (try? FileManager.default.attributesOfItem(atPath: safetyURL.path)[.size] as? Int) ?? 0
        guard size >= rotateAt else { return }
        let previous = safetyURL.deletingPathExtension().appendingPathExtension("1.log")
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: safetyURL, to: previous)
    }

    /// Opened for each write rather than held: someone deleting or moving the file while
    /// the app runs gets a fresh one, not writes into a file that is gone.
    private func append(_ data: Data, to url: URL) -> Bool {
        if !FileManager.default.fileExists(atPath: url.path) {
            return FileManager.default.createFile(atPath: url.path, contents: data)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return false }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(timestamp.string(from: date))
        }
        return encoder
    }()

    /// Milliseconds matter in a log of relays and holds.
    nonisolated(unsafe) static let timestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
