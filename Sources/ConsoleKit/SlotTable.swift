import Foundation
import TelemetryKit

/// Which session sits in which of the four columns.
///
/// A new session takes the lowest free slot and keeps it until its record disappears, so a
/// column never changes hands while its session is alive. A fifth session gets nothing
/// until one of the four ends.
struct SlotTable: Equatable {

    struct Occupant: Equatable {
        var key: SessionKey
        var takenAt: Date
        /// Taken on the SessionStart hook, ahead of the roster.
        var viaHook: Bool
        /// When a roster or a hook last said this session exists.
        var lastEvidence: Date
    }

    private(set) var occupants: [Int: Occupant] = [:]

    func key(in slot: Int) -> SessionKey? { occupants[slot]?.key }

    func slot(of key: SessionKey) -> Int? {
        occupants.first { $0.value.key == key }?.key
    }

    var keys: Set<SessionKey> { Set(occupants.values.map(\.key)) }

    var freeSlot: Int? { PK4.slots.first { occupants[$0] == nil } }

    /// The slot taken, or `nil` when all four are in use: `preferred` if it is free, else
    /// the lowest free one.
    mutating func take(
        _ key: SessionKey, at moment: Date, viaHook: Bool, preferring preferred: Int? = nil
    ) -> Int? {
        if let existing = slot(of: key) { return existing }
        let wanted = preferred.flatMap { PK4.slots.contains($0) && occupants[$0] == nil ? $0 : nil }
        guard let free = wanted ?? freeSlot else { return nil }
        occupants[free] = Occupant(
            key: key, takenAt: moment, viaHook: viaHook, lastEvidence: moment)
        return free
    }

    mutating func confirm(_ key: SessionKey, at moment: Date) {
        guard let slot = slot(of: key) else { return }
        occupants[slot]?.lastEvidence = moment
        occupants[slot]?.viaHook = false
    }

    mutating func release(_ slot: Int) {
        occupants[slot] = nil
    }
}
