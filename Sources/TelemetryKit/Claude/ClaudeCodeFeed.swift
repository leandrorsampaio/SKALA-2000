#if !APP_STORE

import CoreServices
import Foundation

/// Runs the Claude Code collector: a pass every two seconds, and one straight away when
/// Claude Code writes something.
///
/// Everything happens on one utility queue, so a busy disk or a slow CLI never holds up
/// the console; batches are handed to the main actor. Stopping it — MAINS off — stops the
/// timer, the file events and the CLI with it.
public final class ClaudeCodeFeed: @unchecked Sendable {

    /// File events closer together than this are one pass.
    public static let settle: TimeInterval = 0.25

    private let home: ClaudeHome
    private let collector: ClaudeCodeCollector
    private let deliver: @MainActor (TelemetryBatch) -> Void
    private let queue = DispatchQueue(label: "com.maccommandcenter.claude-code", qos: .utility)

    // Touched only on `queue`.
    private var timer: DispatchSourceTimer?
    private var events: FileEventStream?
    private var pending: ClaudeCodeCollector.Trigger = []
    private var scheduled = false
    private var running = false

    public init(
        home: ClaudeHome = ClaudeHome(),
        collector: ClaudeCodeCollector? = nil,
        deliver: @escaping @MainActor (TelemetryBatch) -> Void
    ) {
        self.home = home
        self.collector = collector ?? ClaudeCodeCollector(home: home)
        self.deliver = deliver
    }

    public func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(
                deadline: .now(), repeating: ClaudeCodeCollector.tick, leeway: .milliseconds(200))
            timer.setEventHandler { [weak self] in self?.pass() }
            timer.resume()
            self.timer = timer

            // The root, not its three folders: a folder that does not exist yet cannot be
            // watched, and `jobs/` appears only when the first background job does.
            events = FileEventStream(path: home.root.path, latency: Self.settle, queue: queue) {
                [weak self] paths in self?.filesChanged(paths)
            }
            events?.start()
        }
    }

    public func stop() {
        queue.async { [self] in
            running = false
            timer?.cancel()
            timer = nil
            events?.stop()
            events = nil
            pending = []
        }
    }

    // MARK: - On the queue

    private func filesChanged(_ paths: [String]) {
        guard running else { return }
        let sessions = home.sessions.path + "/"
        let jobs = home.jobs.path + "/"
        let projects = home.projects.path + "/"
        var interesting = false
        for path in paths {
            if path.hasPrefix(sessions) {
                pending.insert(.sessions)
                interesting = true
            } else if path.hasPrefix(jobs) {
                pending.insert(.jobs)
                interesting = true
            } else if path.hasPrefix(projects), path.hasSuffix(".jsonl") {
                interesting = true
            }
        }
        if interesting { schedulePass(after: 0) }
    }

    private func schedulePass(after delay: TimeInterval) {
        guard !scheduled else { return }
        scheduled = true
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.scheduled = false
            self?.pass()
        }
    }

    private func pass() {
        guard running else { return }
        let trigger = pending
        pending = []
        let now = Date()
        let batch = collector.collect(at: now, trigger: trigger)
        if let deferred = collector.deferredRun {
            schedulePass(after: max(0, deferred.timeIntervalSince(now)))
        }
        let deliver = self.deliver
        DispatchQueue.main.async {
            MainActor.assumeIsolated { deliver(batch) }
        }
    }
}

/// FSEvents on one folder and everything under it, file by file.
///
/// A vnode source on a folder hears only entries added, removed and renamed. Claude Code
/// rewrites session files and appends to transcripts in place, so file-level events are
/// the only ones that hear it.
final class FileEventStream {

    private var stream: FSEventStreamRef?
    private let handler: ([String]) -> Void

    init(
        path: String, latency: TimeInterval, queue: DispatchQueue,
        handler: @escaping ([String]) -> Void
    ) {
        self.handler = handler
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil,
            release: nil, copyDescription: nil)
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagNoDefer)
        stream = FSEventStreamCreate(
            nil,
            { _, info, count, paths, _, _ in
                guard let info else { return }
                let stream = Unmanaged<FileEventStream>.fromOpaque(info).takeUnretainedValue()
                let list = unsafeBitCast(paths, to: NSArray.self)
                stream.handler((0..<count).compactMap { list[$0] as? String })
            },
            &context, [path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency, flags)
        if let stream { FSEventStreamSetDispatchQueue(stream, queue) }
    }

    func start() {
        if let stream { FSEventStreamStart(stream) }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}

#endif
