#if !APP_STORE

import Foundation

/// Follows one session's transcript the way `tail -f` does, and watches its subagents.
///
/// The file is read once and after that only the bytes that have appeared since: a long
/// session's transcript runs to tens of megabytes, and the newest `cost-state` checkpoint
/// can sit megabytes back from the end. A partial last line is carried to the next pass,
/// because a record is nearly always still being written when the read lands mid-line.
///
/// This is also where `cost-state` comes from. The checkpoint is a record in the same
/// file, so reading it separately would mean reading every transcript twice.
///
/// Not thread safe: the collector calls it from one queue.
public final class TranscriptSource {

    public let key: SessionKey
    private let projects: URL

    private var url: URL?
    private var lastSearch = Date.distantPast
    private var offset: UInt64 = 0
    private var partial = Data()
    private var accumulator = TranscriptAccumulator()

    /// A partial line past this is a file written faster than it is read, and is dropped
    /// rather than held.
    private static let maximumPartial = 8 * 1024 * 1024
    private static let chunk = 1024 * 1024
    /// How often to look again for a transcript that is not there yet.
    private static let searchEvery: TimeInterval = 10

    public init(key: SessionKey, projects: URL) {
        self.key = key
        self.projects = projects
    }

    /// Where the transcript was found, if it has been.
    public var transcript: URL? { url }

    public func poll(at moment: Date, ttl: TimeInterval) -> [Reading] {
        guard let url = locate(at: moment) else { return [] }
        readNewBytes(from: url)

        var readings: [Reading] = []
        if accumulator.hasReading {
            readings += accumulator.readings(for: key, at: moment, ttl: ttl)
            if let checkpoint = accumulator.checkpoint {
                readings += checkpoint.readings(for: key, at: moment, ttl: ttl)
            }
        }
        if let activity = subagentActivity(beside: url),
            moment.timeIntervalSince(activity) < TTL.subagentActivity
        {
            // Dated when the subagent wrote, so it goes dark thirty seconds after that
            // rather than thirty seconds after this poll.
            readings.append(
                Reading(
                    .session(key), .subagentActivity, .event, at: activity,
                    ttl: TTL.subagentActivity))
        }
        return readings
    }

    // MARK: - Finding the file

    /// The transcript lives under a folder named after the project, and the naming scheme
    /// is Claude Code's business, so the session id is looked up rather than reproduced.
    private func locate(at moment: Date) -> URL? {
        if let url, FileManager.default.fileExists(atPath: url.path) { return url }
        guard moment.timeIntervalSince(lastSearch) >= Self.searchEvery else { return nil }
        lastSearch = moment

        let folders =
            (try? FileManager.default.contentsOfDirectory(
                at: projects, includingPropertiesForKeys: nil)) ?? []
        for folder in folders {
            let candidate = folder.appendingPathComponent(key.rawValue + ".jsonl")
            if FileManager.default.fileExists(atPath: candidate.path) {
                if candidate != url { reset() }
                url = candidate
                return candidate
            }
        }
        return nil
    }

    private func reset() {
        offset = 0
        partial = Data()
        accumulator = TranscriptAccumulator()
    }

    // MARK: - Reading

    private func readNewBytes(from url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return }

        // Truncated or replaced under us: start again rather than read garbage.
        if size < offset { reset() }
        guard size > offset else { return }

        try? handle.seek(toOffset: offset)
        while let data = try? handle.read(upToCount: Self.chunk), !data.isEmpty {
            consume(data)
        }
        // Where reading stopped, not the size measured before it: Claude Code may have
        // written more meanwhile, and those lines must not be read twice.
        offset = (try? handle.offset()) ?? size
    }

    private func consume(_ data: Data) {
        var buffer = partial
        buffer.append(data)
        partial = Data()

        var start = buffer.startIndex
        while let newline = buffer[start...].firstIndex(of: UInt8(ascii: "\n")) {
            if newline > start { accumulator.consume(Data(buffer[start..<newline])) }
            start = buffer.index(after: newline)
        }
        let remainder = buffer[start...]
        if remainder.count <= Self.maximumPartial { partial = Data(remainder) }
    }

    // MARK: - Subagents

    /// The newest write by any of this session's subagents. Their records live in their
    /// own files under `<sessionId>/subagents/`, not in the session's transcript.
    private func subagentActivity(beside transcript: URL) -> Date? {
        let folder = transcript.deletingPathExtension().appendingPathComponent(
            "subagents", isDirectory: true)
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let newest = files.filter { $0.pathExtension == "jsonl" }
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]) }
            .compactMap(\.contentModificationDate)
            .max()
        return [newest, accumulator.lastSidechainAt].compactMap { $0 }.max()
    }
}

#endif
