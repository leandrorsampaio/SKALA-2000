import Foundation
import Observation
import TelemetryKit

/// The PK-4 console's rules, and the only place they live.
///
/// Readings go in through `ingest`, the operator's actions through `send`, and time
/// through `advance`. What comes out is `snapshot`: exactly one value per instrument.
/// Nothing here draws, reads a file or starts a timer. The caller schedules `advance()` at
/// `nextDeadline`, which is what keeps the console idle when nothing is changing.
@MainActor
@Observable
public final class ConsoleModel {

    /// Everything the views need. Replaced at most ten times a second from telemetry, at
    /// once from the operator.
    public private(set) var snapshot = ConsoleSnapshot()

    /// How buttons that reach outside the console are carried out.
    @ObservationIgnored public var commands: ConsoleCommands

    @ObservationIgnored let clock: any ConsoleClock
    @ObservationIgnored let store: any ConsoleStore
    @ObservationIgnored let log: any ConsoleLog

    // MARK: Telemetry

    @ObservationIgnored var sessions: [SessionKey: SessionState] = [:]
    @ObservationIgnored var machine: [Field: Reading] = [:]
    @ObservationIgnored var roster: Reading?
    @ObservationIgnored var slots = SlotTable()
    /// Sessions turned away because all four slots were in use, logged once each.
    @ObservationIgnored var refused: Set<SessionKey> = []
    /// Ended by the SessionEnd hook: a roster that still lists them has not caught up.
    @ObservationIgnored var ended: Set<SessionKey> = []
    /// Slots taken since their pencil strip was last looked at.
    @ObservationIgnored var prefill: [Int: SessionKey] = [:]

    // MARK: The desk

    @ObservationIgnored var saved: PersistedConsole
    @ObservationIgnored var alarms = AlarmBoard()
    @ObservationIgnored var cycles: [InstrumentID: ButtonCycle] = [:]
    @ObservationIgnored var guards: [InstrumentID: GuardState] = [:]
    @ObservationIgnored var power: Power
    /// LAMP TEST and BUZZER TEST held down, and when each may stop showing once let go.
    @ObservationIgnored var testsHeld: Set<InstrumentID> = []
    @ObservationIgnored var testsShowUntil: [InstrumentID: Date] = [:]
    @ObservationIgnored var walk: SelectorWalk?
    @ObservationIgnored var cues = ConsoleCues()
    /// SILENCE pressed, and not yet pressed again: no signal sounds.
    @ObservationIgnored var silenceMode = false
    /// Each slot's session and which of its signalled windows were lit when last looked
    /// at, so that each sounds once as it comes on.
    @ObservationIgnored var heard: [Int: (key: SessionKey, rows: Set<AnnunciatorRow>)] = [:]
    /// Which quota lamps were lit when last looked at; `nil` until the first reading, which
    /// is taken as it is, silently.
    @ObservationIgnored var quotaHeard: Set<InstrumentID>?
    @ObservationIgnored var nextTicket = 1
    @ObservationIgnored var loggedOnce: Set<String> = []
    @ObservationIgnored var issuesLogged: [String: Date] = [:]

    // MARK: Publishing

    @ObservationIgnored var lastPublish: Date?
    @ObservationIgnored var publishPending = false
    @ObservationIgnored var shownNixies: [InstrumentID: ShownNixie] = [:]
    @ObservationIgnored var nixieBypass = true
    @ObservationIgnored var nixieDue: Date?
    /// Whether the tubes were last shown under LAMP TEST.
    @ObservationIgnored var nixiesInTest = false
    @ObservationIgnored var saveDue: Date?
    @ObservationIgnored var serviceMark: Date?

    public init(
        clock: any ConsoleClock,
        store: any ConsoleStore,
        log: any ConsoleLog,
        commands: ConsoleCommands = .unassigned,
        poweredOn: Bool = true
    ) {
        self.clock = clock
        self.store = store
        self.log = log
        self.commands = commands

        let now = clock.now
        var saved = store.load() ?? PersistedConsole()
        saved.totals.forget(before: now.addingTimeInterval(-30 * 86_400))
        self.saved = saved

        power = poweredOn ? .poweringUp(since: now, chirped: false) : .off
        serviceMark = poweredOn ? now : nil
        if poweredOn { log.safety(SafetyEntry(at: now, event: .mainsOn)) }
        restoreQuota(now)
        publish(force: true)
    }

    // MARK: - Inputs

    /// Readings from any source, in any order. A reading with the wrong shape costs its own
    /// instrument and one log line; it never throws and never blanks the console.
    public func ingest(_ readings: [Reading]) {
        // MAINS off stops all polling, and a hook that still arrives has nothing to light.
        guard power != .off else { return }
        let now = clock.now
        accountService(now)

        var rosters: [Reading] = []
        for reading in readings {
            guard reading.value.kind == reading.field.kind else {
                logOnce(
                    "mistyped.\(reading.subject).\(reading.field.rawValue)", at: now,
                    subject: reading.subject,
                    detail:
                        "\(reading.field.rawValue) arrived as \(reading.value.kind.rawValue), "
                        + "expected \(reading.field.kind.rawValue)")
                continue
            }
            switch reading.subject {
            case .machine where reading.field == .roster:
                rosters.append(reading)
            case .machine:
                applyMachine(reading, now: now)
            case .session(let key):
                applySession(key, reading, now: now)
            }
        }
        // Rosters last: a session's start time, read in the same poll, decides which of
        // several newcomers gets the lower slot.
        for roster in rosters.sorted(by: { $0.observedAt < $1.observedAt }) {
            applyRoster(roster, now: now)
        }
        settle(now, force: false)
    }

    /// A source could not read something. It is logged, not shown.
    public func report(_ issue: TelemetryIssue) {
        let now = clock.now
        // A source that fails every poll would write thousands of identical lines a day;
        // the same failure is written again only after ten minutes.
        let key = "\(issue.source)|\(issue.field?.rawValue ?? "")|\(issue.message)"
        if let last = issuesLogged[key], now.timeIntervalSince(last) < 600 { return }
        issuesLogged[key] = now
        var session: SessionKey?
        if case .session(let key) = issue.subject { session = key }
        log.safety(
            SafetyEntry(
                at: now, event: .sourceError, slot: session.flatMap(slots.slot(of:)),
                session: session, detail: "\(issue.source): \(issue.message)"))
    }

    public func send(_ intent: ConsoleIntent) {
        let now = clock.now
        accountService(now)
        switch intent {
        case .selectorStep(let direction):
            walk = nil
            if direction != 0 { stepSelector(by: direction > 0 ? 1 : -1, at: now) }
        case .selectorGoTo(let position):
            let target = min(PK4.slots.upperBound, max(PK4.slots.lowerBound, position))
            walk = target == saved.selector ? nil : SelectorWalk(target: target, next: now)
        case .press(let id):
            press(id, at: now)
        case .release(let id):
            release(id, at: now)
        case .guard(let id, let open):
            setGuard(id, open: open, at: now, reason: nil)
        case .key(let id, let armed):
            setKey(id, armed: armed, at: now)
        case .mains(let on):
            setMains(on, at: now)
        case .pencil(let slot, let text):
            guard PK4.slots.contains(slot) else { break }
            saved.setPencil(slot, String(text.prefix(12)))
            prefill[slot] = nil
            scheduleSave(now)
        }
        settle(now, force: true)
    }

    /// Runs whatever has come due: timers, expiries, the power-up sequence.
    public func advance() {
        let now = clock.now
        accountService(now)
        settle(now, force: false)
    }

    /// When `advance()` next has work, or `nil` when nothing will change on its own.
    public var nextDeadline: Date? {
        let now = clock.now
        var due: [Date] = []

        let nextPublish = (lastPublish ?? .distantPast).addingTimeInterval(ConsoleTiming.coalesce)
        if publishPending { due.append(nextPublish) }
        // A held-back digit can show no sooner than the next publish is allowed; asking
        // for it earlier would have the caller advance in a loop.
        if let nixieDue { due.append(max(nixieDue, nextPublish)) }
        if let saveDue { due.append(saveDue) }
        if let walk { due.append(walk.next) }
        due += testsShowUntil.values.filter { $0 > now }
        if case .poweringUp(let since, _) = power {
            due += PowerUp(since: since).stages.filter { $0 > now }
        }

        for (id, cycle) in cycles {
            switch cycle.phase {
            case .down:
                if let held = cycle.heldSince {
                    due.append(held.addingTimeInterval(ConsoleTiming.holdToFire))
                }
            case .sent: due.append(cycle.since.addingTimeInterval(timeout(for: id)))
            case .confirmed: due.append(cycle.since.addingTimeInterval(glow(for: id)))
            case .noAnswer:
                due.append(cycle.since.addingTimeInterval(ConsoleTiming.noAnswerBlink))
            case .idle: break
            }
        }
        for id in PK4.guarded where guardMayFall(id) {
            if let touched = guards[id]?.touched {
                due.append(touched.addingTimeInterval(ConsoleTiming.guardFallsAfter))
            }
        }

        if power != .off {
            if let expiry = roster?.expiresAt, expiry > now { due.append(expiry) }
            if let expiry = machine.values.map(\.expiresAt).filter({ $0 > now }).min() {
                due.append(expiry)
            }
            for key in slots.keys {
                if let expiry = sessions[key]?.nextExpiry(after: now) { due.append(expiry) }
            }
            if let started = selectedState(now)?.fresh(.startedAt, at: now)?.value.time {
                let elapsed = max(0, now.timeIntervalSince(started))
                due.append(started.addingTimeInterval((floor(elapsed / 60) + 1) * 60))
            }
            let intoHour = saved.serviceSeconds.truncatingRemainder(dividingBy: 3600)
            due.append(now.addingTimeInterval(3600 - intoHour))
            // A reset countdown turns over every minute.
            if PK4.Quota.allCases.contains(where: { quotaResets($0, now) != nil }) {
                let intoMinute = now.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
                due.append(now.addingTimeInterval(60 - intoMinute))
            }
        }
        // A deadline already past means "now": the caller should advance at once.
        return due.min()
    }

    // MARK: - Preferences

    /// Not part of the console surface: these are set from the Settings window.
    public func setFinish(_ finish: Finish) {
        saved.finish = finish
        scheduleSave(clock.now)
        publish(force: true)
    }

    public func setBuzzerMuted(_ muted: Bool) {
        saved.buzzerMuted = muted
        scheduleSave(clock.now)
        publish(force: true)
    }

    public var isPowered: Bool { power != .off }

    public var buzzerMuted: Bool { saved.buzzerMuted }

    /// Writes the desk's memory now. Called on quit.
    public func flush() {
        let now = clock.now
        accountService(now)
        store.save(saved)
        saveDue = nil
    }

    // MARK: - Settling

    func settle(_ now: Date, force: Bool) {
        let fired = runTimers(now)
        reconcile(now)
        forgetQuietSessions(now)
        if let due = saveDue, now >= due {
            store.save(saved)
            saveDue = nil
        }
        var poweringUp = false
        if case .poweringUp = power { poweringUp = true }
        publish(force: force || fired || poweringUp)
    }

    func publish(force: Bool) {
        let now = clock.now
        // The wall clock set back: publishing waits for the coalescing gap, not for the
        // clock to catch up with the moment it was set back from.
        if let last = lastPublish, last > now { lastPublish = now }
        if !force, let last = lastPublish,
            now < last.addingTimeInterval(ConsoleTiming.coalesce)
        {
            publishPending = true
            return
        }
        var next = render(now)
        next.nixies = throttle(next.nixies, at: now)
        lastPublish = now
        publishPending = false
        if next != snapshot { snapshot = next }
    }

    /// Four digit changes a second per readout, except when the whole desk changes at
    /// once: a selector turn, power, or a lamp test starting or ending.
    func throttle(_ desired: [InstrumentID: String], at now: Date) -> [InstrumentID: String] {
        var bypass = nixieBypass
        if case .poweringUp = power { bypass = true }
        if power == .off { bypass = true }
        let testing = isLampTestShowing(now)
        if testing != nixiesInTest {
            bypass = true
            nixiesInTest = testing
        }
        nixieBypass = false
        nixieDue = nil

        var shown: [InstrumentID: String] = [:]
        for (id, value) in desired {
            if !bypass, let previous = shownNixies[id], previous.value != value {
                let allowed = previous.at.addingTimeInterval(ConsoleTiming.nixieThrottle)
                if now < allowed {
                    shown[id] = previous.value
                    nixieDue = min(nixieDue ?? allowed, allowed)
                    continue
                }
            }
            if shownNixies[id]?.value != value {
                shownNixies[id] = ShownNixie(value: value, at: now)
            }
            shown[id] = value
        }
        return shown
    }

    func scheduleSave(_ now: Date) {
        if saveDue == nil { saveDue = now.addingTimeInterval(ConsoleTiming.saveDebounce) }
    }

    /// Hours in service count while MAINS is on, like the hour meter on a real desk.
    func accountService(_ now: Date) {
        guard power != .off, let mark = serviceMark else { return }
        let elapsed = now.timeIntervalSince(mark)
        guard elapsed > 0 else { return }
        let minuteBefore = NixieFormat.whole(saved.serviceSeconds / 60)
        saved.serviceSeconds += elapsed
        serviceMark = now
        if NixieFormat.whole(saved.serviceSeconds / 60) != minuteBefore { scheduleSave(now) }
    }

    // MARK: - Logging

    func record(
        _ event: SafetyEntry.Event, at moment: Date, instrument: InstrumentID? = nil,
        slot: Int? = nil, session: SessionKey? = nil, detail: String? = nil
    ) {
        log.safety(
            SafetyEntry(
                at: moment, event: event, instrument: instrument, slot: slot, session: session,
                detail: detail))
    }

    func logOnce(_ key: String, at moment: Date, subject: Subject?, detail: String) {
        guard loggedOnce.insert(key).inserted else { return }
        var session: SessionKey?
        if case .session(let key) = subject { session = key }
        record(
            .sourceError, at: moment, slot: session.flatMap(slots.slot(of:)), session: session,
            detail: detail)
    }
}

// MARK: - Internal state

enum Power: Equatable {
    case off
    case poweringUp(since: Date, chirped: Bool)
    case live
}

/// The power-up sequence from `10-interaction.md`: POWER ON, the nixie rows striking top to
/// bottom on all eights, the needles rising, one second of lamp test, then live data.
struct PowerUp {
    let since: Date

    /// When power reaches the desk and the first row of tubes strikes.
    var powerOnAt: Date { since.addingTimeInterval(ConsoleTiming.powerOnLamp) }

    func strikeStart(row: Int) -> Date {
        powerOnAt.addingTimeInterval(ConsoleTiming.strikeStagger * Double(row))
    }

    func strikeEnd(row: Int) -> Date {
        strikeStart(row: row).addingTimeInterval(ConsoleTiming.strikeHold)
    }

    /// The needles rise and the lamp test begins when the last row has struck.
    var strikeEnd: Date { strikeEnd(row: PK4.nixieRows.count - 1) }
    var lampTestStart: Date { strikeEnd }
    var liveAt: Date { strikeEnd.addingTimeInterval(ConsoleTiming.lampTest) }

    var stages: [Date] {
        var stages = [powerOnAt, strikeEnd, liveAt]
        for row in PK4.nixieRows.indices {
            stages += [strikeStart(row: row), strikeEnd(row: row)]
        }
        return stages
    }
}

struct ButtonCycle: Equatable {
    var capDown = false
    var phase: CommandPhase = .idle
    var since = Date.distantPast
    var request: CommandRequest?
    /// A latching function stays lit while its state holds.
    var latched = false
    /// A guarded button's time-delay relay started timing here.
    var heldSince: Date?
    /// The state a round button's command is expected to produce.
    var expected: Bool?
    /// A round button with no observed field shows what it last confirmed.
    var reported: Bool?
    /// After no answer, a round button's lenses stay dark until its field reports afresh.
    var awaitingReading: Date?
}

struct GuardState: Equatable {
    var open = false
    var touched = Date.distantPast
}

struct SelectorWalk: Equatable {
    var target: Int
    var next: Date
}

struct ShownNixie: Equatable {
    var value: String
    var at: Date
}
