import Foundation
import TelemetryKit

/// Buttons, guards, the key, the selector and MAINS.
extension ConsoleModel {

    // MARK: - Buttons

    func press(_ id: InstrumentID, at now: Date) {
        var cycle = cycles[id] ?? ButtonCycle()
        guard !cycle.capDown else { return }

        if PK4.tests.contains(id) {
            cycle.capDown = true
            cycle.phase = .down
            cycle.since = now
            cycles[id] = cycle
            if case .live = power {
                testsHeld.insert(id)
                testsShowUntil[id] = now.addingTimeInterval(ConsoleTiming.testMinimum)
            }
            return
        }

        // While a command is out, the button ignores further presses.
        guard cycle.phase != .sent else { return }

        if PK4.guarded.contains(id) {
            // A closed guard covers the button completely.
            guard guards[id]?.open == true else { return }
            guards[id]?.touched = now
            cycle.capDown = true
            cycle.phase = .down
            cycle.since = now
            // Without the key the button travels, and nothing is sent.
            let keyed = !PK4.keyed.contains(id) || saved.armedKeys.contains(id)
            cycle.heldSince = power == .live && keyed ? now : nil
            cycles[id] = cycle
            return
        }

        cycle.capDown = true
        cycle.phase = .down
        cycle.since = now
        cycles[id] = cycle
    }

    func release(_ id: InstrumentID, at now: Date) {
        guard var cycle = cycles[id], cycle.capDown else { return }
        cycle.capDown = false

        if PK4.tests.contains(id) {
            cycle.phase = .idle
            cycles[id] = cycle
            testsHeld.remove(id)
            return
        }

        if PK4.guarded.contains(id) {
            // Released before 2 s: the time-delay relay drops out. Nothing is sent and
            // nothing shows it. After 2 s the command is already out; letting go is nothing.
            if cycle.phase == .down {
                cycle.phase = .idle
                cycle.heldSince = nil
            }
            cycles[id] = cycle
            return
        }

        guard cycle.phase == .down else {
            cycles[id] = cycle
            return
        }
        cycles[id] = cycle
        // A dead console sends nothing, and neither does one still powering up.
        guard power == .live else {
            cycles[id]?.phase = .idle
            return
        }
        // Sending happens on release.
        dispatch(id, at: now)
    }

    /// Sends a button's command at the selected slot as it is right now.
    func dispatch(_ id: InstrumentID, at moment: Date) {
        let slot = saved.selector
        let key = slots.key(in: slot)
        let ticket = nextTicket
        nextTicket += 1
        let request = CommandRequest(
            button: id, ticket: ticket, slot: slot, session: key, issuedAt: moment)

        var cycle = cycles[id] ?? ButtonCycle()
        cycle.phase = .sent
        cycle.since = moment
        cycle.request = request
        cycles[id] = cycle
        record(.commandSent, at: moment, instrument: id, slot: slot, session: key)

        switch id {
        case PK4.silence:
            // A mode, on and off: while on, no signal sounds and its lamps burn.
            silenceMode.toggle()
            record(
                .alarmSilenced, at: moment, instrument: id, detail: silenceMode ? "on" : "off")
            confirm(id, at: moment)
        case PK4.acknowledge:
            let acknowledged = alarms.acknowledge()
            record(
                .alarmAcknowledged, at: moment, instrument: id,
                detail: acknowledged.isEmpty
                    ? nil : acknowledged.map(\.rawValue).joined(separator: " "))
            confirm(id, at: moment)
        case PK4.printText:
            if log.text(printLines(slot: slot, now: moment)) {
                cues.openLog += 1
                confirm(id, at: moment)
            } else {
                noAnswer(id, at: moment)
            }
        default:
            let action = commands.action(for: id)
            if PK4.round.contains(id) {
                let current =
                    action.observes.flatMap { machineFlag($0, at: moment) }
                    ?? cycle.reported
                cycles[id]?.expected = !(current ?? false)
            }
            action.perform(request) { [weak self] confirmed in
                self?.commandReplied(id, ticket: ticket, confirmed: confirmed)
            }
        }
    }

    /// The command's own result. A late reply, or one for an earlier press, is ignored.
    func commandReplied(_ id: InstrumentID, ticket: Int, confirmed: Bool) {
        guard let cycle = cycles[id], cycle.phase == .sent, cycle.request?.ticket == ticket
        else { return }
        let now = clock.now
        if PK4.round.contains(id), commands.action(for: id).observes != nil, confirmed {
            // Only the machine reporting the new state lights a lens.
            return
        }
        if confirmed { confirm(id, at: now) } else { noAnswer(id, at: now) }
        publish(force: true)
    }

    func confirm(_ id: InstrumentID, at moment: Date) {
        guard var cycle = cycles[id], cycle.phase == .sent else { return }
        cycle.phase = .confirmed
        cycle.since = moment
        if commands.action(for: id).latching, !PK4.round.contains(id) { cycle.latched.toggle() }
        if PK4.round.contains(id) { cycle.reported = cycle.expected }
        cycles[id] = cycle
        record(
            .commandConfirmed, at: moment, instrument: id, slot: cycle.request?.slot,
            session: cycle.request?.session)
    }

    func noAnswer(_ id: InstrumentID, at moment: Date) {
        guard var cycle = cycles[id], cycle.phase == .sent else { return }
        cycle.phase = .noAnswer
        cycle.since = moment
        if PK4.round.contains(id), commands.action(for: id).observes != nil {
            cycle.awaitingReading = moment
        }
        cycles[id] = cycle
        record(
            .commandNoAnswer, at: moment, instrument: id, slot: cycle.request?.slot,
            session: cycle.request?.session)
    }

    /// The desk's own buttons answer at once; the rest take as long as their action says.
    func timeout(for id: InstrumentID) -> TimeInterval {
        switch id {
        case PK4.silence, PK4.acknowledge, PK4.printText: ConsoleTiming.noAnswer
        default: commands.action(for: id).timeout
        }
    }

    func glow(for id: InstrumentID) -> TimeInterval {
        PK4.guarded.contains(id) ? ConsoleTiming.guardedGlow : ConsoleTiming.momentaryGlow
    }

    func machineFlag(_ field: Field, at moment: Date) -> Bool? {
        guard let reading = machine[field], reading.isFresh(at: moment) else { return nil }
        return reading.value.flag
    }

    // MARK: - Timers

    /// Everything that happens because time passed. A late call catches up: a command
    /// that timed out and finished blinking both happen, in order.
    @discardableResult
    func runTimers(_ now: Date) -> Bool {
        var fired = false

        if case .poweringUp(let since, let chirped) = power {
            let schedule = PowerUp(since: since)
            if !chirped, now >= schedule.lampTestStart {
                cues.chirp += 1
                power = .poweringUp(since: since, chirped: true)
                fired = true
            }
            if now >= schedule.liveAt {
                power = .live
                nixieBypass = true
                fired = true
            }
        }

        while let walk, now >= walk.next {
            fired = true
            stepSelector(by: walk.target > saved.selector ? 1 : -1, at: walk.next)
            if saved.selector == walk.target {
                self.walk = nil
            } else {
                self.walk?.next = walk.next.addingTimeInterval(ConsoleTiming.selectorDetent)
            }
        }

        for id in cycles.keys.sorted() where advanceCycle(id, now) { fired = true }

        for id in PK4.guarded where guardMayFall(id) {
            guard let touched = guards[id]?.touched else { continue }
            let falls = touched.addingTimeInterval(ConsoleTiming.guardFallsAfter)
            if now >= falls {
                // Not before whatever last happened under it: after a command's 93 s the
                // guard falls as the no answer shows, and is logged then, not 88 s back.
                let at = max(falls, cycles[id]?.since ?? falls)
                setGuard(id, open: false, at: at, reason: "idle")
                fired = true
            }
        }
        return fired
    }

    private func advanceCycle(_ id: InstrumentID, _ now: Date) -> Bool {
        var fired = false
        while let cycle = cycles[id] {
            switch cycle.phase {
            case .down:
                guard let held = cycle.heldSince else { return fired }
                let pullIn = held.addingTimeInterval(ConsoleTiming.holdToFire)
                guard now >= pullIn else { return fired }
                // The relay pulls in with a clunk, the only sign the hold was long enough.
                cycles[id]?.heldSince = nil
                cues.relay += 1
                dispatch(id, at: pullIn)
            case .sent:
                let deadline = cycle.since.addingTimeInterval(timeout(for: id))
                guard now >= deadline else { return fired }
                noAnswer(id, at: deadline)
            case .confirmed:
                let end = cycle.since.addingTimeInterval(glow(for: id))
                guard now >= end else { return fired }
                cycles[id]?.phase = .idle
                cycles[id]?.since = end
                // A confirmed disruptive command lets its guard fall shut.
                if PK4.guarded.contains(id) {
                    setGuard(id, open: false, at: end, reason: "confirmed")
                }
            case .noAnswer:
                let end = cycle.since.addingTimeInterval(ConsoleTiming.noAnswerBlink)
                guard now >= end else { return fired }
                cycles[id]?.phase = .idle
                cycles[id]?.since = end
            case .idle:
                return fired
            }
            fired = true
        }
        return fired
    }

    /// An open guard falls by itself after five seconds with nothing happening under it.
    func guardMayFall(_ id: InstrumentID) -> Bool {
        guard guards[id]?.open == true else { return false }
        guard let cycle = cycles[id] else { return true }
        return !cycle.capDown && cycle.phase != .sent && cycle.phase != .confirmed
    }

    // MARK: - Guards and the key

    func setGuard(_ id: InstrumentID, open: Bool, at moment: Date, reason: String?) {
        guard PK4.guarded.contains(id) else { return }
        var state = guards[id] ?? GuardState()
        state.touched = moment
        guard state.open != open else {
            guards[id] = state
            return
        }
        state.open = open
        guards[id] = state
        // A flap shut over a button being held drops the time-delay relay: nothing fires.
        if !open { cycles[id]?.heldSince = nil }
        record(
            open ? .guardLifted : .guardLowered, at: moment, instrument: id,
            slot: saved.selector, session: slots.key(in: saved.selector), detail: reason)
    }

    /// The key sits in the well under F12's guard, so it turns only with the guard up.
    func setKey(_ id: InstrumentID, armed: Bool, at moment: Date) {
        guard PK4.keyed.contains(id), guards[id]?.open == true else { return }
        guards[id]?.touched = moment
        guard saved.armedKeys.contains(id) != armed else { return }
        if armed {
            saved.armedKeys.append(id)
        } else {
            saved.armedKeys.removeAll { $0 == id }
            // The key turned back while the button is held: the relay drops out.
            cycles[id]?.heldSince = nil
        }
        scheduleSave(moment)
        record(
            armed ? .keyArmed : .keyDisarmed, at: moment, instrument: id, slot: saved.selector,
            session: slots.key(in: saved.selector))
    }

    // MARK: - Selector

    /// One detent. The switch is pinned at 1 and 4: from 4 the only way is back.
    func stepSelector(by direction: Int, at moment: Date) {
        let next = saved.selector + direction
        guard PK4.slots.contains(next) else { return }
        saved.selector = next
        // Every panel B readout swaps to the new session at once.
        nixieBypass = true
        scheduleSave(moment)
    }

    // MARK: - MAINS

    func setMains(_ on: Bool, at moment: Date) {
        guard on != (power != .off) else { return }
        nixieBypass = true
        if on {
            power = .poweringUp(since: moment, chirped: false)
            serviceMark = moment
            record(.mainsOn, at: moment)
            return
        }

        accountService(moment)
        power = .off
        serviceMark = nil
        // Off darkens every instrument. What the board knew goes with it: on power-up every
        // alarm that is still true is raised, and heard, again.
        alarms.reset()
        heard = [:]
        testsHeld = []
        testsShowUntil = [:]
        walk = nil
        for (id, cycle) in cycles {
            var idle = ButtonCycle()
            idle.capDown = cycle.capDown
            idle.latched = cycle.latched
            idle.reported = cycle.reported
            idle.since = moment
            if cycle.capDown { idle.phase = .down }
            cycles[id] = idle
        }
        record(.mainsOff, at: moment)
    }

    // MARK: - PRINT TEXT

    /// The selected slot's strings. They are what the session last said, fresh or not:
    /// this is a log, not an instrument.
    func printLines(slot: Int, now: Date) -> [String] {
        let tag = "S\(slot)"
        guard let key = slots.key(in: slot), let state = sessions[key] else {
            return ["\(tag) NO SESSION"]
        }
        var lines: [String] = []
        func line(_ label: String, _ field: Field) {
            if let text = state.readings[field]?.value.text, !text.isEmpty {
                lines.append("\(tag) \(label) \(text)")
            }
        }
        line("NAME", .name)
        line("JOB", .jobName)
        line("CWD", .cwd)
        line("TITLE", .aiTitle)
        line("BRANCH", .gitBranch)
        line("MODEL", .model)
        line("EFFORT", .effort)
        for usage in state.readings[.modelUsage]?.value.lines ?? [] {
            lines.append("\(tag) USAGE \(usage)")
        }
        let mix = state.readings[.toolMix]?.value.tally ?? [:]
        for (tool, calls) in mix.sorted(by: {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }) {
            lines.append("\(tag) TOOL \(tool) \(calls)")
        }
        line("PROMPT", .lastPrompt)
        line("NEEDS", .jobNeeds)
        line("DETAIL", .jobDetail)
        return lines.isEmpty ? ["\(tag) NO TEXT"] : lines
    }
}
