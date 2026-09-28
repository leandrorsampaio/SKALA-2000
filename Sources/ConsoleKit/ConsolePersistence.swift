import Foundation
import TelemetryKit

/// The electromechanical totals: console-wide sums, forward only, kept across launches.
///
/// Each is a sum of **positive deltas** per session. A session whose figure goes down —
/// restarted, resumed, re-read from the top — has the drop ignored rather than subtracted,
/// and counts again from the new figure.
public struct DrumTotals: Codable, Equatable, Sendable {

    public enum Figure: String, Codable, Sendable, CaseIterable {
        case cost, output, added, removed
    }

    public var costUSD: Double = 0
    public var outputTokens: Double = 0
    public var linesAdded: Double = 0
    public var linesRemoved: Double = 0

    /// The figure each session last reported, so a relaunch does not count it twice.
    /// Keyed by session id: a dictionary keyed by a custom type encodes as an array.
    public var lastSeen: [String: Seen] = [:]

    public struct Seen: Codable, Equatable, Sendable {
        public var figures: [String: Double]
        public var at: Date
    }

    public init() {}

    /// More than any session could report: a trillion dollars, tokens or lines. A figure
    /// above it is a damaged record, and counting it would ruin the totals for good.
    static let plausible: Double = 1e12

    /// Counts what `value` adds for this session. Returns whether any total moved.
    ///
    /// The first figure ever seen from a session counts in full: nothing of it has been
    /// counted before. That is also why `lastSeen` is persisted — without it a relaunch
    /// would count every running session again from zero.
    mutating func record(
        _ figure: Figure, value: Double, for key: SessionKey, at moment: Date
    ) -> Bool {
        guard value.isFinite, value >= 0, value <= Self.plausible else { return false }
        var seen = lastSeen[key.rawValue] ?? Seen(figures: [:], at: moment)
        let previous = seen.figures[figure.rawValue] ?? 0
        let delta = value - previous
        seen.figures[figure.rawValue] = value
        seen.at = moment
        lastSeen[key.rawValue] = seen
        guard delta > 0 else { return false }

        switch figure {
        case .cost: costUSD += delta
        case .output: outputTokens += delta
        case .added: linesAdded += delta
        case .removed: linesRemoved += delta
        }
        return true
    }

    /// Drops what old sessions last reported. Their totals stay.
    mutating func forget(before moment: Date) {
        lastSeen = lastSeen.filter { $0.value.at >= moment }
    }

    /// Field by field, like `PersistedConsole`: one mistyped total must not zero the others.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func total(_ key: CodingKeys) -> Double {
            (try? container.decodeIfPresent(Double.self, forKey: key)) ?? 0
        }
        costUSD = total(.costUSD)
        outputTokens = total(.outputTokens)
        linesAdded = total(.linesAdded)
        linesRemoved = total(.linesRemoved)
        lastSeen = (try? container.decodeIfPresent([String: Seen].self, forKey: .lastSeen)) ?? [:]
    }
}

/// Everything the desk remembers between launches.
///
/// Decoding is tolerant: a field that is missing or unreadable takes its default instead of
/// losing the rest, because the drum totals are the one thing here nobody can reconstruct.
public struct PersistedConsole: Codable, Equatable, Sendable {
    public var format = 1
    public var totals = DrumTotals()
    public var serviceSeconds: TimeInterval = 0
    /// Slot 1 at index 0.
    public var pencils: [String] = ["", "", "", ""]
    /// Which session sat in each slot, slot 1 at index 0, so a relaunch seats every
    /// session under its own pencil strip again rather than in the order they started.
    public var seats: [String] = ["", "", "", ""]
    public var selector = 1
    public var armedKeys: [InstrumentID] = []
    public var finish: Finish = .greyGreen
    public var buzzerMuted = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = (try? container.decodeIfPresent(Int.self, forKey: .format)) ?? 1
        totals = (try? container.decodeIfPresent(DrumTotals.self, forKey: .totals)) ?? DrumTotals()
        serviceSeconds =
            (try? container.decodeIfPresent(TimeInterval.self, forKey: .serviceSeconds)) ?? 0
        let strips = (try? container.decodeIfPresent([String].self, forKey: .pencils)) ?? []
        pencils = (0..<PK4.slots.count).map { $0 < strips.count ? strips[$0] : "" }
        let sat = (try? container.decodeIfPresent([String].self, forKey: .seats)) ?? []
        seats = (0..<PK4.slots.count).map { $0 < sat.count ? sat[$0] : "" }
        selector = min(
            4, max(1, (try? container.decodeIfPresent(Int.self, forKey: .selector)) ?? 1))
        armedKeys =
            (try? container.decodeIfPresent([InstrumentID].self, forKey: .armedKeys)) ?? []
        finish = (try? container.decodeIfPresent(Finish.self, forKey: .finish)) ?? .greyGreen
        buzzerMuted = (try? container.decodeIfPresent(Bool.self, forKey: .buzzerMuted)) ?? false
    }

    func pencil(_ slot: Int) -> String {
        let index = slot - 1
        return pencils.indices.contains(index) ? pencils[index] : ""
    }

    mutating func setPencil(_ slot: Int, _ text: String) {
        let index = slot - 1
        guard pencils.indices.contains(index) else { return }
        pencils[index] = text
    }

    /// The slot `key` last sat in, if it still holds it.
    func seat(of key: SessionKey) -> Int? {
        seats.firstIndex(of: key.rawValue).map { $0 + 1 }
    }

    mutating func setSeat(_ slot: Int, _ key: SessionKey?) {
        let index = slot - 1
        guard seats.indices.contains(index) else { return }
        seats[index] = key?.rawValue ?? ""
    }
}

/// Where the desk's memory lives. The file-backed one arrives with the app; tests keep it
/// in memory.
@MainActor
public protocol ConsoleStore: AnyObject {
    func load() -> PersistedConsole?
    func save(_ state: PersistedConsole)
}

@MainActor
public final class MemoryConsoleStore: ConsoleStore {
    public var state: PersistedConsole?
    public private(set) var saves = 0

    public init(_ state: PersistedConsole? = nil) {
        self.state = state
    }

    public func load() -> PersistedConsole? { state }

    public func save(_ state: PersistedConsole) {
        self.state = state
        saves += 1
    }
}
