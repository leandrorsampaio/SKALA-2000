import Foundation
import TelemetryKit

/// How readings become slots, lamps and alarms.
extension ConsoleModel {

    // MARK: - Machine

    func applyMachine(_ reading: Reading, now: Date) {
        machine[reading.field] = reading
        guard let flag = reading.value.flag else { return }

        // A round button is confirmed by the machine reporting the state it asked for,
        // never by its command having been dispatched.
        for id in PK4.round where commands.action(for: id).observes == reading.field {
            guard let cycle = cycles[id] else { continue }
            if cycle.phase == .sent, cycle.expected == flag {
                confirm(id, at: now)
            }
            if let since = cycle.awaitingReading, reading.observedAt > since {
                cycles[id]?.awaitingReading = nil
            }
        }
    }

    // MARK: - Sessions

    func applySession(_ key: SessionKey, _ reading: Reading, now: Date) {
        var state = sessions[key] ?? SessionState()
        var reading = reading
        // Two sources report the last compaction: the PostCompact hook at once, and the
        // transcript's boundary record on its next pass, which for a moment can still be
        // the previous one. The later of the two is the truth.
        if reading.field == .compactBoundary,
            let known = state.readings[.compactBoundary]?.value.time,
            let reported = reading.value.time, known > reported
        {
            reading.value = .time(known)
        }
        state.store(reading)

        switch reading.field {
        case .promptSubmitted:
            // The operator answered: whatever was waiting on them is over.
            state.clear([.waiting, .turnDone, .agentDone])
            state.busySuppressed = false
        case .turnDone:
            state.busy = false
            state.busySuppressed = true
        case .toolUsed:
            state.liveToolCalls += 1
            // A tool ran, so whatever it was waiting on has been answered — typically a
            // permission granted in the terminal, which submits no prompt. The hook
            // endpoint only reports the main agent's tools as this field.
            state.clear([.waiting])
        case .toolCalls:
            state.liveToolCalls = 0
        case .status:
            switch reading.value.text {
            case "busy":
                state.busy = !state.busySuppressed
            case "idle":
                state.busy = false
                state.busySuppressed = false
            default:
                // Nothing but busy and idle has been observed. Anything else changes
                // nothing: stopping is the Stop hook's to say.
                logUnknown(key, .status, reading.value.text, at: now)
            }
        default:
            break
        }
        sessions[key] = state

        switch reading.field {
        case .sessionStarted:
            ended.remove(key)
            take(key, at: now, viaHook: true)
        case .sessionEnded:
            ended.insert(key)
            if let slot = slots.slot(of: key) { release(slot, at: now, detail: "session end") }
        case .costUSD: countDrum(.cost, reading, key, now)
        case .outputTokens: countDrum(.output, reading, key, now)
        case .linesAdded: countDrum(.added, reading, key, now)
        case .linesRemoved: countDrum(.removed, reading, key, now)
        case .permissionMode:
            if Self.permissionWindow(reading.value.text) == nil {
                logUnknown(key, .permissionMode, reading.value.text, at: now)
            }
        case .effort:
            if Self.effortWindow(reading.value.text) == nil {
                logUnknown(key, .effort, reading.value.text, at: now)
            }
        case .contextWindow:
            if let size = reading.value.count, size != 200_000, size != 1_000_000 {
                logUnknown(key, .contextWindow, String(size), at: now)
            }
        default:
            break
        }
    }

    func countDrum(
        _ figure: DrumTotals.Figure, _ reading: Reading, _ key: SessionKey, _ now: Date
    ) {
        guard let value = reading.value.amount else { return }
        if saved.totals.record(figure, value: value, for: key, at: now) { scheduleSave(now) }
    }

    /// Once per session, field and value: a group that goes dark says why, but only once.
    func logUnknown(_ key: SessionKey, _ field: Field, _ value: String?, at now: Date) {
        let value = value ?? "(none)"
        logOnce(
            "unknown.\(key).\(field.rawValue).\(value)", at: now, subject: .session(key),
            detail: "\(field.rawValue) has an unknown value: \(value)")
    }

    // MARK: - Slots

    func applyRoster(_ reading: Reading, now: Date) {
        roster = reading
        guard let keys = reading.value.keys else { return }
        let listed = Set(keys)

        // A record that is no longer listed has ended. A hook-announced session gets a
        // grace period, because the hook fires before `claude agents` lists it.
        let graceStart = reading.observedAt.addingTimeInterval(-ConsoleTiming.hookGrace)
        for (slot, occupant) in slots.occupants.sorted(by: { $0.key < $1.key })
        where !listed.contains(occupant.key) {
            if occupant.viaHook, occupant.lastEvidence > graceStart { continue }
            release(slot, at: now, detail: "no longer listed")
        }

        ended.formIntersection(listed)
        for key in listed { slots.confirm(key, at: reading.observedAt) }

        let newcomers = listed.filter { slots.slot(of: $0) == nil && !ended.contains($0) }
            .sorted { lhs, rhs in
                let left = startedAt(lhs) ?? .distantFuture
                let right = startedAt(rhs) ?? .distantFuture
                return left == right ? lhs < rhs : left < right
            }
        // Sessions that had a slot before a relaunch sit down first, each in its own.
        let returning = newcomers.filter { saved.seat(of: $0) != nil }
        for key in returning + newcomers.filter({ saved.seat(of: $0) == nil }) {
            take(key, at: now, viaHook: false)
        }
    }

    func startedAt(_ key: SessionKey) -> Date? {
        sessions[key]?.readings[.startedAt]?.value.time
    }

    func take(_ key: SessionKey, at now: Date, viaHook: Bool) {
        guard slots.slot(of: key) == nil else { return }
        if let slot = slots.take(key, at: now, viaHook: viaHook, preferring: saved.seat(of: key)) {
            refused.remove(key)
            prefill[slot] = key
            saved.setSeat(slot, key)
            scheduleSave(now)
            record(.slotTaken, at: now, slot: slot, session: key)
        } else if refused.insert(key).inserted {
            record(.slotRefused, at: now, session: key, detail: "all four slots in use")
        }
    }

    func release(_ slot: Int, at now: Date, detail: String) {
        let key = slots.key(in: slot)
        slots.release(slot)
        prefill[slot] = nil
        saved.setSeat(slot, nil)
        scheduleSave(now)
        record(.slotReleased, at: now, slot: slot, session: key, detail: detail)
    }

    /// A session nobody lists and nothing has heard from for ten minutes is forgotten. Its
    /// contribution to the drum totals is kept.
    func forgetQuietSessions(_ now: Date) {
        let listed = Set(freshRosterKeys(now) ?? [])
        let cutoff = now.addingTimeInterval(-ConsoleTiming.forgetSession)
        for (key, state) in sessions
        where !listed.contains(key) && slots.slot(of: key) == nil && state.lastHeard < cutoff {
            sessions[key] = nil
        }
    }

    func freshRosterKeys(_ now: Date) -> [SessionKey]? {
        guard let roster, roster.isFresh(at: now) else { return nil }
        return roster.value.keys
    }

    // MARK: - Reconciling

    /// Re-derives what depends on time and on everything else at once: pencil strips and
    /// the alarm board.
    func reconcile(_ now: Date) {
        fillPencils(now)
        guard power == .live else { return }
        signalChanges(now)

        for condition in alarmConditions(now) {
            guard let change = alarms.set(condition.id, condition.active, at: now) else {
                continue
            }
            record(
                change == .raised ? .alarmRaised : .alarmCleared, at: now,
                instrument: condition.id, slot: condition.slot, session: condition.session)

            if change == .raised {
                // WAIT asks twice, quickly; BLOCK and the desk's own alarms once, long.
                let waiting = condition.slot.map {
                    condition.id == PK4.annunciator(.wait, slot: $0)
                }
                signal(waiting == true ? .wait : .block)
            }

            // BLOCKED writes its reason to the text log by itself: the console has no
            // other way to say what a stuck agent needs.
            if change == .raised, let slot = condition.slot,
                condition.id == PK4.annunciator(.block, slot: slot),
                let key = condition.session,
                let needs = sessions[key]?.text(.jobNeeds, at: now)
            {
                _ = log.text(["S\(slot) NEEDS \(needs)"])
            }
        }
    }

    /// Signals the moment each slot's DONE, CMPCT and LOW CONTEXT windows come on. A
    /// session only just seated is taken as it is, silently: it did not just change.
    func signalChanges(_ now: Date) {
        for slot in PK4.slots {
            guard let key = slots.key(in: slot), let state = sessions[key], !state.isStale(at: now)
            else {
                heard[slot] = nil
                continue
            }
            var rows: Set<AnnunciatorRow> = []
            if state.fresh(.turnDone, at: now) != nil { rows.insert(.done) }
            if state.isCompacting(at: now) { rows.insert(.cmpct) }
            if isLowOnContext(state, now) { rows.insert(.lowctx) }
            let before = heard[slot]
            heard[slot] = (key, rows)
            guard let before, before.key == key else { continue }
            for row in AnnunciatorRow.allCases
            where rows.contains(row) && !before.rows.contains(row) {
                switch row {
                case .done: signal(.done)
                case .cmpct: signal(.compact)
                case .lowctx: signal(.lowContext)
                default: break
                }
            }
        }
    }

    /// Counts a signal for the sound layer, unless SILENCE's mode or the mute holds it.
    func signal(_ signal: Signal) {
        guard !silenceMode, !saved.buzzerMuted else { return }
        cues.signals[signal, default: 0] += 1
    }

    /// The share of the context window still free, when the session says both figures.
    func contextLeft(_ state: SessionState, _ now: Date) -> Double? {
        guard let used = state.count(.contextUsed, at: now),
            let window = state.count(.contextWindow, at: now), window > 0
        else { return nil }
        return min(1, max(0, 1 - Double(used) / Double(window)))
    }

    /// Under 5% of the context left: LOW CONTEXT lights, and beeps once.
    func isLowOnContext(_ state: SessionState, _ now: Date) -> Bool {
        (contextLeft(state, now) ?? 1) < ConsoleTiming.lowContext
    }

    struct AlarmCondition {
        var id: InstrumentID
        var active: Bool
        var slot: Int?
        var session: SessionKey?
    }

    func alarmConditions(_ now: Date) -> [AlarmCondition] {
        var conditions: [AlarmCondition] = []
        for slot in PK4.slots {
            let key = slots.key(in: slot)
            let state = key.flatMap { sessions[$0] }
            let live = state.map { !$0.isStale(at: now) } ?? false
            conditions.append(
                AlarmCondition(
                    id: PK4.annunciator(.wait, slot: slot),
                    active: live && state?.fresh(.waiting, at: now) != nil, slot: slot,
                    session: key))
            conditions.append(
                AlarmCondition(
                    id: PK4.annunciator(.block, slot: slot),
                    active: live && state?.text(.jobTempo, at: now) == "blocked", slot: slot,
                    session: key))
        }

        let selected = saved.selector
        let selectedKey = slots.key(in: selected)
        conditions.append(
            AlarmCondition(
                id: PK4.warning(.stale),
                active: selectedKey.map { sessions[$0]?.isStale(at: now) ?? true } ?? false,
                slot: selected, session: selectedKey))

        let battery = machine[.batteryFraction].flatMap { $0.isFresh(at: now) ? $0 : nil }
        conditions.append(
            AlarmCondition(
                id: PK4.batteryLow, active: (battery?.value.amount).map { $0 < 0.2 } ?? false))
        return conditions
    }

    /// The first time a session takes an empty slot, its strip gets the project name. After
    /// that the strip belongs to the operator.
    func fillPencils(_ now: Date) {
        for (slot, key) in prefill {
            guard slots.key(in: slot) == key, saved.pencil(slot).isEmpty else {
                prefill[slot] = nil
                continue
            }
            guard let name = sessions[key]?.pencilName(at: now) else { continue }
            saved.setPencil(slot, String(name.prefix(12)))
            prefill[slot] = nil
            scheduleSave(now)
        }
    }

    // MARK: - The selected slot

    enum Selection {
        case empty
        case stale(SessionKey)
        case live(SessionKey, SessionState)
    }

    func selection(_ now: Date) -> Selection {
        guard let key = slots.key(in: saved.selector) else { return .empty }
        guard let state = sessions[key], !state.isStale(at: now) else { return .stale(key) }
        return .live(key, state)
    }

    func selectedState(_ now: Date) -> SessionState? {
        if case .live(_, let state) = selection(now) { return state }
        return nil
    }

    // MARK: - Enumerations

    static func permissionWindow(_ raw: String?) -> PK4.Permission? {
        switch raw {
        case "default": .default
        case "acceptEdits": .acceptEdits
        case "plan": .plan
        case "auto": .auto
        case "bypassPermissions": .bypass
        default: nil
        }
    }

    /// `max` sits above `xhigh` and has no window of its own: it lights the top of the
    /// scale rather than leaving the group dark for the whole session. PRINT TEXT writes
    /// the exact value.
    static func effortWindow(_ raw: String?) -> PK4.Effort? {
        switch raw {
        case "low": .low
        case "medium": .medium
        case "high": .high
        case "xhigh": .xhigh
        case "max": .max
        case "ultracode": .ultracode
        default: nil
        }
    }

    /// Substring match on the id. Anything else is OTHER; the full id goes to the log.
    /// Opus lights by its context window: 1M when the session reports one, else 200K,
    /// Opus's standard window.
    static func modelWindow(_ raw: String?, contextWindow: Int? = nil) -> PK4.Model? {
        guard let id = raw?.lowercased(), !id.isEmpty else { return nil }
        if id.contains("opus") { return contextWindow == 1_000_000 ? .opus1m : .opus200k }
        if id.contains("sonnet") { return .sonnet }
        if id.contains("haiku") { return .haiku }
        if id.contains("fable") { return .fable }
        return .other
    }

    static func modeWindow(_ raw: String?) -> PK4.Mode? {
        guard let raw else { return nil }
        return raw == "normal" ? .normal : .other
    }

    static func tierWindow(_ raw: String?) -> PK4.Tier? {
        guard let raw else { return nil }
        return raw == "standard" ? .standard : .other
    }
}

// MARK: - For commands

/// What a command acting on a session needs to find it: where it works and which process
/// it is. Read from the newest readings, fresh or not: a command is aimed at the session
/// as last seen.
public struct SessionDetails: Sendable, Equatable {
    public var cwd: String?
    public var pid: Int?
    public var name: String?
    /// A background job has no terminal and no process of its own to signal.
    public var isJob: Bool
}

extension ConsoleModel {
    public func details(of key: SessionKey) -> SessionDetails? {
        guard let state = sessions[key] else { return nil }
        let now = clock.now
        return SessionDetails(
            cwd: state.readings[.cwd]?.value.text,
            pid: state.readings[.pid]?.value.count,
            name: state.readings[.name]?.value.text,
            isJob: state.isJob(at: now))
    }
}
