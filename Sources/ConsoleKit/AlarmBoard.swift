import Foundation

/// The alarm logic shared by WAITING FOR OPERATOR, BLOCKED, BATT LOW and DATA STALE.
///
/// | Event                    | Window                 | Sound                               |
/// | ------------------------ | ---------------------- | ----------------------------------- |
/// | condition becomes true   | flash                  | its signal, once                    |
/// | ACKNOWLEDGE              | every flashing → on    | —                                   |
/// | condition clears         | off, acked or not      | —                                   |
///
/// SILENCE is not here: it is a mode of the whole desk's sound, not of the board.
///
/// LAMP TEST is not here: it overrides what every window shows without touching what the
/// board knows.
struct AlarmBoard: Equatable {

    struct Entry: Equatable {
        var raisedAt: Date
        var acknowledged = false
    }

    enum Change: Equatable {
        case raised
        case cleared
    }

    private(set) var active: [InstrumentID: Entry] = [:]

    /// Sets one condition and says what changed, so the caller can log it.
    mutating func set(_ id: InstrumentID, _ condition: Bool, at moment: Date) -> Change? {
        switch (condition, active[id] != nil) {
        case (true, false):
            active[id] = Entry(raisedAt: moment)
            return .raised
        case (false, true):
            active[id] = nil
            return .cleared
        default:
            return nil
        }
    }

    /// Returns the alarms that were flashing and now burn steady.
    @discardableResult
    mutating func acknowledge() -> [InstrumentID] {
        var acknowledged: [InstrumentID] = []
        for (id, entry) in active where !entry.acknowledged {
            active[id]?.acknowledged = true
            acknowledged.append(id)
        }
        return acknowledged.sorted()
    }

    mutating func reset() {
        active = [:]
    }

    func state(_ id: InstrumentID) -> LampState {
        guard let entry = active[id] else { return .off }
        return entry.acknowledged ? .on : .flash
    }

    var hasUnacknowledged: Bool { active.values.contains { !$0.acknowledged } }
}
