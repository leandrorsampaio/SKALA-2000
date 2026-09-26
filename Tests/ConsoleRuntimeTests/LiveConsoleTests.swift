#if !APP_STORE

import Foundation
import Testing

@testable import ConsoleKit
@testable import ConsoleRuntime
@testable import TelemetryKit

/// The whole console on this Mac — real Claude Code, real power — in a scratch folder.
///
///     PK4_LIVE=1 swift test --filter LiveConsole
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PK4_LIVE"] == "1"))
struct LiveConsoleTests {

    @Test func eightSecondsOfTheRealDesk() async throws {
        let scratch = Scratch()
        let console = PK4Console(directory: scratch.url, commands: .unassigned)
        let feed = ClaudeCodeFeed { console.ingest($0) }
        feed.start()
        defer { feed.stop() }
        try await Task.sleep(for: .seconds(8))

        let snap = console.model.snapshot
        let lit = snap.lamps.keys.map(\.rawValue).sorted()
        print(
            "running", snap.nixie(PK4.sessionsRunning), "busy", snap.nixie(PK4.sessionsBusy),
            "build", snap.programBuild ?? "-", "battery", snap.meter(PK4.batteryMeter))
        print("lit:", lit.filter { !$0.hasPrefix("b.") }.joined(separator: " "))
        print("pencils:", (1...4).map { snap.pencil(slot: $0) })
        console.tap(PK4.printText)
        console.shutDown()

        for file in scratch.files() {
            let size =
                (try? FileManager.default.attributesOfItem(
                    atPath: scratch.url.appendingPathComponent(file).path)[.size] as? Int) ?? 0
            print("file", file, size, "bytes")
        }
        let safety = try String(contentsOf: console.log.safetyURL, encoding: .utf8)
        print(safety.split(separator: "\n").prefix(6).joined(separator: "\n"))
        print(
            "text log:",
            console.log.readText().split(separator: "\n").prefix(4).joined(separator: " | "))
        #expect(snap.lamp(PK4.powerOn) == .on)
        #expect(snap.lamp(PK4.onMains) == .on || snap.lamp(PK4.onBattery) == .on)
        #expect(FileConsoleStore(directory: scratch.url).load() != nil)
    }
}

extension PK4Console {
    func tap(_ id: InstrumentID) {
        send(.press(id))
        send(.release(id))
    }
}

#endif

#if !APP_STORE
/// How often the snapshot really changes on this Mac, and in what.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PK4_LIVE"] == "1"))
struct LiveChurnTests {
    @Test func whatChangesAndHowOften() async throws {
        let scratch = Scratch()
        let console = PK4Console(directory: scratch.url, commands: .unassigned)
        let feed = ClaudeCodeFeed { console.ingest($0) }
        feed.start()
        defer {
            feed.stop()
            console.shutDown()
        }
        try await Task.sleep(for: .seconds(4))
        var previous = console.model.snapshot
        var changes = 0
        var fields: [String: Int] = [:]
        let end = Date().addingTimeInterval(30)
        while Date() < end {
            try await Task.sleep(for: .milliseconds(50))
            let now = console.model.snapshot
            guard now != previous else { continue }
            changes += 1
            for (id, v) in now.nixies where previous.nixies[id] != v {
                fields["nixie " + id.rawValue, default: 0] += 1
            }
            for id in Set(now.lamps.keys).union(previous.lamps.keys)
            where now.lamp(id) != previous.lamp(id) {
                fields["lamp " + id.rawValue, default: 0] += 1
            }
            for (id, v) in now.meters where previous.meters[id] != v {
                fields["meter " + id.rawValue, default: 0] += 1
            }
            for (id, v) in now.drums where previous.drums[id] != v {
                fields["drum " + id.rawValue, default: 0] += 1
            }
            if now.buttons != previous.buttons { fields["buttons", default: 0] += 1 }
            if now.programBuild != previous.programBuild { fields["build", default: 0] += 1 }
            if now.cues != previous.cues { fields["cues", default: 0] += 1 }
            previous = now
        }
        print("snapshot changes in 30 s:", changes)
        for (field, count) in fields.sorted(by: { $0.value > $1.value }).prefix(12) {
            print("  \(count)  \(field)")
        }
    }
}
#endif
