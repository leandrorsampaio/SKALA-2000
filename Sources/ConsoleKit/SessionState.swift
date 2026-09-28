import Foundation
import TelemetryKit

/// The newest reading of every field for one session, and the little the console derives
/// from the order they arrived in.
struct SessionState {

    private(set) var readings: [Field: Reading] = [:]

    /// BUSY. Set by `status == "busy"`, cleared by `idle` or the Stop hook.
    var busy = false
    /// After Stop, a `busy` still in flight from the last poll must not relight the lamp.
    /// Lifted by an observed `idle` or the next prompt.
    var busySuppressed = false
    /// PostToolUse calls since the transcript last reported its own count.
    var liveToolCalls = 0
    var lastHeard = Date.distantPast

    mutating func store(_ reading: Reading) {
        readings[reading.field] = reading
        // A process still running says nothing of whether Claude Code still reports on it.
        if !reading.field.isProcessLoad { lastHeard = max(lastHeard, reading.observedAt) }
    }

    mutating func clear(_ fields: [Field]) {
        fields.forEach { readings[$0] = nil }
    }

    func fresh(_ field: Field, at moment: Date) -> Reading? {
        guard let reading = readings[field], reading.isFresh(at: moment) else { return nil }
        return reading
    }

    func text(_ field: Field, at moment: Date) -> String? {
        fresh(field, at: moment)?.value.text
    }

    func count(_ field: Field, at moment: Date) -> Int? {
        fresh(field, at: moment)?.value.count
    }

    func amount(_ field: Field, at moment: Date) -> Double? {
        fresh(field, at: moment)?.value.amount
    }

    func seconds(_ field: Field, at moment: Date) -> TimeInterval? {
        fresh(field, at: moment)?.value.seconds
    }

    func flag(_ field: Field, at moment: Date) -> Bool? {
        fresh(field, at: moment)?.value.flag
    }

    /// Stale when the newest reading this session has had is no longer believed. Events
    /// that act on arrival carry no lifetime and do not count.
    func isStale(at moment: Date) -> Bool {
        let newest = readings.values.filter { $0.ttl > 0 && !$0.field.isProcessLoad }
            .max { $0.observedAt < $1.observedAt }
        guard let newest else { return true }
        return !newest.isFresh(at: moment)
    }

    /// A background job rather than a terminal someone is watching.
    func isJob(at moment: Date) -> Bool {
        if let kind = text(.kind, at: moment), kind != "interactive" { return true }
        return fresh(.jobState, at: moment) != nil || fresh(.jobTempo, at: moment) != nil
    }

    func isBusy(at moment: Date) -> Bool {
        if busy, fresh(.status, at: moment) != nil { return true }
        return text(.jobState, at: moment) == "working"
    }

    /// From PreCompact until the transcript shows the boundary, or the hook's five minutes.
    func isCompacting(at moment: Date) -> Bool {
        guard let started = fresh(.preCompact, at: moment) else { return false }
        if let boundary = readings[.compactBoundary]?.value.time, boundary >= started.observedAt {
            return false
        }
        return true
    }

    /// What the pencil strip is pre-filled with, the first time this session takes an
    /// empty slot.
    func pencilName(at moment: Date) -> String? {
        if isJob(at: moment) {
            if let name = text(.jobName, at: moment) ?? text(.name, at: moment), !name.isEmpty {
                return name
            }
        }
        guard let cwd = text(.cwd, at: moment), !cwd.isEmpty else { return nil }
        let base = URL(fileURLWithPath: cwd).lastPathComponent
        return base.isEmpty ? nil : base
    }

    /// The expiry that changes what this session shows soonest.
    func nextExpiry(after moment: Date) -> Date? {
        readings.values.map(\.expiresAt).filter { $0 > moment }.min()
    }
}
