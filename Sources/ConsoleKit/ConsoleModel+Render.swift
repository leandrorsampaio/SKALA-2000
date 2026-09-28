import Foundation
import TelemetryKit

/// Turns the model's state into one value per instrument.
///
/// Every function here is a pure reading of state at a moment: rendering twice at the same
/// time gives the same snapshot. Anything not set stays at its dark value.
extension ConsoleModel {

    func render(_ now: Date) -> ConsoleSnapshot {
        var out = ConsoleSnapshot()
        out.selector = saved.selector
        out.finish = saved.finish
        out.mains = power != .off
        out.cues = cues
        for slot in PK4.slots where !saved.pencil(slot).isEmpty {
            out.pencils[slot] = saved.pencil(slot)
        }
        out.guardsOpen = Set(guards.filter { $0.value.open }.map(\.key))
        out.keysArmed = Set(saved.armedKeys)
        // Drum counters hold their reading on power loss: they are wheels, not lamps.
        out.drums = drums()

        let testing = isLampTestShowing(now)
        out.buttons = buttonFaces(testing: testing, at: now)

        switch power {
        case .off:
            return out

        case .poweringUp(let since, _):
            let schedule = PowerUp(since: since)
            out.nixies = strike(schedule, at: now)
            if now >= schedule.strikeEnd { out.meters = meters(now) }
            if testing { PK4.allLamps.forEach { out.lamps[$0] = .test } }
            return out

        case .live:
            out.meters = meters(now)
            out.programBuild = programBuild(now)
            if testing {
                // Every lamp on the desk, the tubes' every digit included.
                PK4.allLamps.forEach { out.lamps[$0] = .test }
                out.nixies = PK4.nixies.mapValues { NixieFormat.allEights($0) }
            } else {
                out.lamps = lamps(now)
                out.nixies = nixies(now)
            }
            // The buzzer sounds on its own only for BUZZER TEST, whatever else is set: that
            // is what it is for. Alarms and states speak in signals, once each.
            out.buzzer = isTestShowing(PK4.buzzerTest, now)
            return out
        }
    }

    /// While a test button is held, and for its minimum after, on a live desk only.
    func isTestShowing(_ id: InstrumentID, _ now: Date) -> Bool {
        guard case .live = power else { return false }
        return testsHeld.contains(id) || (testsShowUntil[id].map { now < $0 } ?? false)
    }

    func isLampTestShowing(_ now: Date) -> Bool {
        switch power {
        case .off: return false
        case .live: return isTestShowing(PK4.lampTest, now)
        case .poweringUp(let since, _):
            let schedule = PowerUp(since: since)
            return now >= schedule.lampTestStart && now < schedule.liveAt
        }
    }

    // MARK: - Nixies

    /// Row by row, top to bottom, each on all eights for 120 ms.
    func strike(_ schedule: PowerUp, at now: Date) -> [InstrumentID: String] {
        var out: [InstrumentID: String] = [:]
        for (row, ids) in PK4.nixieRows.enumerated() {
            let lit = now >= schedule.strikeStart(row: row) && now < schedule.strikeEnd(row: row)
            for id in ids {
                let template = PK4.nixies[id] ?? ""
                out[id] =
                    lit ? NixieFormat.allEights(template) : NixieFormat.dark(template)
            }
        }
        return out
    }

    func nixies(_ now: Date) -> [InstrumentID: String] {
        var out: [InstrumentID: String] = [:]
        for (id, template) in PK4.nixies { out[id] = NixieFormat.dark(template) }

        let selected = String(saved.selector)
        out[PK4.selected] = selected

        if let listed = freshRosterKeys(now) {
            let busy = listed.filter { sessions[$0]?.isBusy(at: now) == true }
            out[PK4.sessionsRunning] = NixieFormat.digits(listed.count, width: 1)
            out[PK4.sessionsBusy] = NixieFormat.digits(busy.count, width: 1)
        }

        // Panel E: how long until each plan window resets, while one is known, in days,
        // hours and minutes. Claude Code gives the moment it resets; the time left is
        // counted on the Mac's clock and rounded up as a countdown reads: 69 minutes and
        // a half read 00 01 10.
        for quota in PK4.Quota.allCases {
            guard let left = quotaResets(quota, now) else { continue }
            let minutes = NixieFormat.whole((left / 60).rounded(.up))
            out[PK4.quotaReset(quota, .days)] = NixieFormat.digits(minutes / 1440, width: 2)
            out[PK4.quotaReset(quota, .hours)] = NixieFormat.digits(minutes % 1440 / 60, width: 2)
            out[PK4.quotaReset(quota, .minutes)] = NixieFormat.digits(minutes % 60, width: 2)
        }
        out.merge(loadNixies(now)) { _, measured in measured }

        let panelB: [InstrumentID] = [
            PK4.contextUsed, PK4.inputTokens, PK4.outputTokens, PK4.thinkingTokens,
            PK4.cacheRead, PK4.cacheWritten, PK4.queueDepth, PK4.toolCalls, PK4.lastTurn,
            PK4.turnMessages, PK4.uptime, PK4.cost,
        ]

        switch selection(now) {
        case .empty:
            // An empty slot reads zero: there is no session, so nothing has happened.
            for id in panelB { out[id] = NixieFormat.zero(PK4.nixies[id] ?? "") }
        case .stale:
            // A stale number is never left standing.
            break
        case .live(_, let state):
            func put(_ id: InstrumentID, _ value: String?) {
                if let value { out[id] = value }
            }
            put(
                PK4.contextUsed,
                state.count(.contextUsed, at: now).map { NixieFormat.digits($0, width: 8) })
            put(
                PK4.inputTokens,
                state.count(.inputTokens, at: now).map { NixieFormat.digits($0, width: 8) })
            put(
                PK4.outputTokens,
                state.count(.outputTokens, at: now).map { NixieFormat.digits($0, width: 8) })
            put(
                PK4.thinkingTokens,
                state.count(.thinkingTokens, at: now).map { NixieFormat.digits($0, width: 8) })
            put(
                PK4.cacheRead,
                state.count(.cacheReadTokens, at: now).map { NixieFormat.thousands($0, width: 8) })
            put(
                PK4.cacheWritten,
                state.count(.cacheCreationTokens, at: now).map {
                    NixieFormat.thousands($0, width: 8)
                })
            put(
                PK4.queueDepth,
                state.count(.queueDepth, at: now).map { NixieFormat.digits($0, width: 6) })

            // The transcript's count, advanced live by PostToolUse between its reads.
            let counted = state.count(.toolCalls, at: now)
            if counted != nil || state.liveToolCalls > 0 {
                out[PK4.toolCalls] = NixieFormat.digits(
                    (counted ?? 0) + state.liveToolCalls, width: 6)
            }

            put(
                PK4.lastTurn,
                state.seconds(.turnDuration, at: now).map {
                    NixieFormat.minutesSeconds($0, leading: 4)
                })
            put(
                PK4.turnMessages,
                state.count(.turnMessages, at: now).map { NixieFormat.digits($0, width: 6) })
            put(
                PK4.uptime,
                state.fresh(.startedAt, at: now)?.value.time.map {
                    NixieFormat.hoursMinutes(now.timeIntervalSince($0), leading: 4)
                })
            put(PK4.cost, state.amount(.costUSD, at: now).map(NixieFormat.cost))
        }
        return out
    }

    // MARK: - Meters

    func meters(_ now: Date) -> [InstrumentID: Double] {
        var out: [InstrumentID: Double] = [:]
        for id in PK4.meters { out[id] = Needle.leftStop }

        if case .live(_, let state) = selection(now) {
            // Room left, not room used: green on a panel has to mean "fine".
            if let left = contextLeft(state, now) { out[PK4.contextMeter] = left }
            if let total = state.seconds(.totalDuration, at: now), total > 0 {
                if let api = state.seconds(.apiDuration, at: now) {
                    out[PK4.apiShareMeter] = min(1, max(0, api / total))
                }
                if let tools = state.seconds(.toolDuration, at: now) {
                    out[PK4.toolShareMeter] = min(1, max(0, tools / total))
                }
            }
        }

        let battery = machine[.batteryFraction].flatMap { $0.isFresh(at: now) ? $0 : nil }
        out[PK4.batteryMeter] = min(1, max(0, battery?.value.amount ?? 0))
        for quota in PK4.Quota.allCases {
            out[PK4.quotaMeter(quota)] = quotaUsed(quota, now) ?? Needle.leftStop
        }

        // Panel F: what the Mac is doing. A figure not read lies on the stop.
        func share(_ value: Double?) -> Double? { value.map { min(1, max(0, $0)) } }
        out[PK4.loadMeter(.cpu)] = share(machineAmount(.cpuLoad, now))
        out[PK4.loadMeter(.gpu)] = share(machineAmount(.gpuLoad, now))
        out[PK4.loadMeter(.power)] = share(machineAmount(.systemPower, now).map { $0 / PK4.powerScale })
        if let used = machineAmount(.memoryUsed, now),
            let total = machineAmount(.memoryTotal, now), total > 0
        {
            out[PK4.loadMeter(.memory)] = share(used / total)
        }
        return out
    }

    func machineAmount(_ field: Field, _ now: Date) -> Double? {
        guard let reading = machine[field], reading.isFresh(at: now) else { return nil }
        return reading.value.amount
    }

    func machineText(_ field: Field, _ now: Date) -> String? {
        guard let reading = machine[field], reading.isFresh(at: now) else { return nil }
        return reading.value.text
    }

    // MARK: - Panel F's tubes

    func loadNixies(_ now: Date) -> [InstrumentID: String] {
        var out: [InstrumentID: String] = [:]
        let gigabyte = 1_073_741_824.0
        func put(_ gauge: PK4.Gauge, _ field: Field, _ format: (Double) -> String) {
            if let value = machineAmount(field, now) { out[PK4.gauge(gauge)] = format(value) }
        }
        func whole(_ width: Int, per unit: Double = 1) -> (Double) -> String {
            { NixieFormat.digits(NixieFormat.whole(($0 / unit).rounded()), width: width) }
        }
        func decimal(_ whole: Int, per unit: Double) -> (Double) -> String {
            { NixieFormat.decimal($0 / unit, whole: whole, fraction: 1) }
        }
        put(.socTemp, .socTemperature, whole(3))
        put(.ssdTemp, .ssdTemperature, whole(3))
        put(.batteryTemp, .batteryTemperature, whole(3))
        put(.fan1, .fan1Speed, whole(4))
        put(.fan2, .fan2Speed, whole(4))
        // Memory in the gigabytes Activity Monitor uses, disks in the Finder's.
        put(.memoryUsed, .memoryUsed, decimal(2, per: gigabyte))
        put(.memoryWired, .memoryWired, decimal(2, per: gigabyte))
        put(.memoryCompressed, .memoryCompressed, decimal(2, per: gigabyte))
        put(.swap, .swapUsed, decimal(2, per: gigabyte))
        put(.diskFree, .diskFree) {
            NixieFormat.digits(NixieFormat.whole($0 / 1_000_000_000), width: 4)
        }
        put(.diskRead, .diskRead, decimal(3, per: 1_000_000))
        put(.diskWrite, .diskWrite, decimal(3, per: 1_000_000))
        put(.networkIn, .networkIn, decimal(3, per: 1_000_000))
        put(.networkOut, .networkOut, decimal(3, per: 1_000_000))

        // Each seated session's processes, in its own column, as panel A's windows are.
        for slot in PK4.slots {
            guard let key = slots.key(in: slot), let state = sessions[key],
                !state.isStale(at: now)
            else { continue }
            if let share = state.amount(.processCPU, at: now) {
                out[PK4.sessionCPU(slot: slot)] = NixieFormat.digits(
                    NixieFormat.whole((share * 100).rounded()), width: 3)
            }
            if let bytes = state.amount(.processMemory, at: now) {
                out[PK4.sessionMemory(slot: slot)] = NixieFormat.decimal(
                    bytes / gigabyte, whole: 2, fraction: 1)
            }
        }
        return out
    }

    // MARK: - Lamps

    func lamps(_ now: Date) -> [InstrumentID: LampState] {
        var out: [InstrumentID: LampState] = [:]
        func light(_ id: InstrumentID, _ on: Bool) {
            if on { out[id] = .on }
        }

        // Panel A: a slot whose session stopped reporting goes dark, whole column.
        for slot in PK4.slots {
            guard let key = slots.key(in: slot), let state = sessions[key],
                !state.isStale(at: now)
            else { continue }
            light(PK4.annunciator(.run, slot: slot), true)
            light(PK4.annunciator(.busy, slot: slot), state.isBusy(at: now))
            light(PK4.annunciator(.done, slot: slot), state.fresh(.turnDone, at: now) != nil)
            light(PK4.annunciator(.agent, slot: slot), state.fresh(.agentDone, at: now) != nil)
            light(PK4.annunciator(.bkgd, slot: slot), state.isJob(at: now))
            light(PK4.annunciator(.cmpct, slot: slot), state.isCompacting(at: now))
            light(
                PK4.annunciator(.remote, slot: slot), state.flag(.remoteControl, at: now) == true)
            // Red, and flashing for as long as it holds, like WAIT and BLOCK.
            if isLowOnContext(state, now) { out[PK4.annunciator(.lowctx, slot: slot)] = .flash }
        }

        // Panel D's foot: the Mac's thermal state and memory pressure, a lamp for each; red
        // ones flash for as long as they hold, as panel A's do.
        if let state = machineText(.thermalState, now).flatMap(PK4.Thermal.init) {
            out[PK4.thermal(state)] = state == .serious || state == .critical ? .flash : .on
        }
        if let level = machineText(.memoryPressure, now).flatMap(PK4.Pressure.init) {
            out[PK4.pressure(level)] = level == .critical ? .flash : .on
        }

        // Panel A's red rows flash for as long as they hold: ACKNOWLEDGE steadies only the
        // desk's own alarms, DATA STALE and BATT LOW.
        let panelA = Set(
            PK4.slots.flatMap {
                [PK4.annunciator(.wait, slot: $0), PK4.annunciator(.block, slot: $0)]
            })
        for id in PK4.alarmBoard {
            let state = alarms.state(id)
            guard state != .off else { continue }
            out[id] = panelA.contains(id) ? .flash : state
        }
        for quota in PK4.Quota.allCases {
            let used = quotaUsed(quota, now) ?? 0
            light(PK4.quotaNear(quota), used >= ConsoleTiming.quotaNear)
            // AT LIMIT flashes for as long as it holds.
            if used >= ConsoleTiming.quotaLimit { out[PK4.quotaLimit(quota)] = .flash }
        }

        // Signals go unheard: SILENCE's mode is on, or the buzzer is muted in Settings.
        light(PK4.silenced, silenceMode || saved.buzzerMuted)

        // Panel B: the selected session's groups. One window per group at most; a value
        // with no window of its own lights OTHER where there is one, and nothing where
        // there is not.
        if case .live(_, let state) = selection(now) {
            if let permission = Self.permissionWindow(state.text(.permissionMode, at: now)) {
                light(PK4.permission(permission), true)
            }
            if let effort = Self.effortWindow(state.text(.effort, at: now)) {
                light(PK4.effort(effort), true)
            }
            let window = state.count(.contextWindow, at: now)
            if let model = Self.modelWindow(state.text(.model, at: now), contextWindow: window) {
                light(PK4.model(model), true)
            }
            if let mode = Self.modeWindow(state.text(.mode, at: now)) {
                light(PK4.mode(mode), true)
            }
            if let kind = kindWindow(state, now) { light(PK4.kind(kind), true) }
            if let tier = Self.tierWindow(state.text(.serviceTier, at: now)) {
                light(PK4.tier(tier), true)
            }

            // PRICE UNKNOWN is steady: a warning, not an alarm.
            light(PK4.warning(.price), state.flag(.unknownModelCost, at: now) == true)
            light(PK4.warning(.subagent), state.fresh(.subagentActivity, at: now) != nil)
            light(PK4.warning(.precompact), state.isCompacting(at: now))
        }

        // Panel D.
        for id in PK4.lensed {
            guard let reported = roundState(id, now) else { continue }
            out[reported ? PK4.lensOn(id) : PK4.lensOff(id)] = .on
        }
        let mains = machine[.onMains].flatMap { $0.isFresh(at: now) ? $0.value.flag : nil }
        light(PK4.onMains, mains == true)
        light(PK4.onBattery, mains == false)
        light(PK4.charging, machineFlag(.charging, at: now) == true)
        return out
    }

    /// INTERACTIVE for a terminal session; DETACHED for anything else, or a job.
    func kindWindow(_ state: SessionState, _ now: Date) -> PK4.Kind? {
        if state.isJob(at: now) { return .detached }
        guard let kind = state.text(.kind, at: now) else { return nil }
        return kind == "interactive" ? .interactive : .detached
    }

    /// What a round button's lenses show. `nil` lights neither: the machine has not said,
    /// or has not answered.
    func roundState(_ id: InstrumentID, _ now: Date) -> Bool? {
        let cycle = cycles[id] ?? ButtonCycle()
        if cycle.phase == .sent || cycle.phase == .noAnswer || cycle.awaitingReading != nil {
            return nil
        }
        if let field = commands.action(for: id).observes { return machineFlag(field, at: now) }
        return cycle.reported
    }

    // MARK: - Buttons

    func buttonFaces(testing: Bool, at now: Date) -> [InstrumentID: ButtonFace] {
        var out: [InstrumentID: ButtonFace] = [:]
        for id in PK4.litButtons + PK4.round {
            let cycle = cycles[id] ?? ButtonCycle()
            var lamp = LampState.off
            // A round cap is black bakelite and never lights; its lenses do the talking.
            if power != .off, !PK4.round.contains(id) {
                if testing {
                    lamp = .test
                } else if PK4.tests.contains(id) {
                    // A test button burns while its test shows.
                    lamp = isTestShowing(id, now) ? .on : .off
                } else if cycle.phase == .confirmed || cycle.latched {
                    lamp = .on
                } else if id == PK4.silence, silenceMode {
                    // SILENCE burns while its mode is on.
                    lamp = .on
                }
            }
            out[id] = ButtonFace(capDown: cycle.capDown, lamp: lamp, phase: cycle.phase)
        }
        return out
    }

    // MARK: - Counters

    func drums() -> [InstrumentID: Int] {
        func wheels(_ value: Double) -> Int {
            // Six wheels roll over like an odometer rather than stop.
            NixieFormat.whole(value.truncatingRemainder(dividingBy: 1_000_000))
        }
        let totals = saved.totals
        return [
            PK4.totalCost: wheels(totals.costUSD),
            PK4.totalOutput: wheels(totals.outputTokens / 1000),
            PK4.linesAdded: wheels(totals.linesAdded),
            PK4.linesRemoved: wheels(totals.linesRemoved),
            PK4.hoursInService: wheels(saved.serviceSeconds / 3600),
        ]
    }

    /// The highest build among running sessions.
    func programBuild(_ now: Date) -> String? {
        let keys = freshRosterKeys(now) ?? Array(slots.keys)
        return keys.compactMap { sessions[$0]?.text(.version, at: now) }
            .max { $0.compare($1, options: .numeric) == .orderedAscending }
    }
}
