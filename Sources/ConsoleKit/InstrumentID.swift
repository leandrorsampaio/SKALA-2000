import Foundation

/// The stable name of one instrument or control on the desk: `a.wait.2`, `b.nixie.output`.
///
/// Views look their value up by it and send intents with it. An id the snapshot has no
/// entry for reads as the instrument's dark value, so a missing entry can never light
/// anything.
public struct InstrumentID: RawRepresentable, Hashable, Sendable, Codable, Comparable,
    ExpressibleByStringLiteral, CustomStringConvertible
{
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public var description: String { rawValue }

    public static func < (lhs: InstrumentID, rhs: InstrumentID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// One row of the panel A annunciator, top to bottom.
public enum AnnunciatorRow: String, CaseIterable, Sendable {
    case run, busy, wait, done, agent, bkgd, block, cmpct, lowctx

    /// Alarm rows flash and sound until acknowledged; the rest are plain on and off.
    public var isAlarm: Bool { self == .wait || self == .block }
}

/// The wiring list: every id on the PK-4 desk, named after the signal map.
public enum PK4 {

    public static let slots = 1...4

    // MARK: Panel A · all sessions

    public static func annunciator(_ row: AnnunciatorRow, slot: Int) -> InstrumentID {
        InstrumentID("a.\(row.rawValue).\(slot)")
    }

    public static func pencil(slot: Int) -> InstrumentID { InstrumentID("a.pencil.\(slot)") }

    public static let sessionsRunning: InstrumentID = "a.nixie.running"
    public static let sessionsBusy: InstrumentID = "a.nixie.busy"
    public static let silence: InstrumentID = "a.sil"
    public static let acknowledge: InstrumentID = "a.ack"
    public static let lampTest: InstrumentID = "a.test"
    public static let buzzerTest: InstrumentID = "a.buzzer.test"
    /// Under the buzzer: burns while an alarm would not sound, silenced or muted.
    public static let silenced: InstrumentID = "a.silenced"
    /// Test buttons act while held, on the desk alone, and send nothing anywhere.
    public static let tests: Set<InstrumentID> = [lampTest, buzzerTest]

    // MARK: Panel B · selected session

    public static let selector: InstrumentID = "b.selector"
    public static let selected: InstrumentID = "b.nixie.selected"
    public static let printText: InstrumentID = "b.prt"

    public static let contextMeter: InstrumentID = "b.meter.context"
    public static let apiShareMeter: InstrumentID = "b.meter.api"
    public static let toolShareMeter: InstrumentID = "b.meter.tool"

    public static let contextUsed: InstrumentID = "b.nixie.contextUsed"
    public static let inputTokens: InstrumentID = "b.nixie.input"
    public static let outputTokens: InstrumentID = "b.nixie.output"
    public static let thinkingTokens: InstrumentID = "b.nixie.thinking"
    public static let cacheRead: InstrumentID = "b.nixie.cacheRead"
    public static let cacheWritten: InstrumentID = "b.nixie.cacheWritten"
    public static let queueDepth: InstrumentID = "b.nixie.queue"
    public static let toolCalls: InstrumentID = "b.nixie.tools"
    public static let lastTurn: InstrumentID = "b.nixie.lastTurn"
    public static let turnMessages: InstrumentID = "b.nixie.turnMessages"
    public static let uptime: InstrumentID = "b.nixie.uptime"
    public static let cost: InstrumentID = "b.nixie.cost"

    public enum Permission: String, CaseIterable, Sendable {
        case `default`, acceptEdits, plan, auto, bypass
    }

    public enum Effort: String, CaseIterable, Sendable {
        case low, medium, high, xhigh, max, ultracode
    }
    /// Opus by its context window, the one model the desk tells apart that way.
    public enum Model: String, CaseIterable, Sendable {
        case opus200k, opus1m, sonnet, haiku, fable, other
    }
    public enum Mode: String, CaseIterable, Sendable { case normal, other }
    public enum Kind: String, CaseIterable, Sendable { case interactive, detached }
    public enum Tier: String, CaseIterable, Sendable { case standard, other }
    public enum Warning: String, CaseIterable, Sendable {
        case price, stale, subagent, precompact
    }

    public static func permission(_ window: Permission) -> InstrumentID {
        InstrumentID("b.perm.\(window.rawValue)")
    }
    public static func effort(_ window: Effort) -> InstrumentID {
        InstrumentID("b.effort.\(window.rawValue)")
    }
    public static func model(_ window: Model) -> InstrumentID {
        InstrumentID("b.model.\(window.rawValue)")
    }
    public static func mode(_ window: Mode) -> InstrumentID {
        InstrumentID("b.mode.\(window.rawValue)")
    }
    public static func kind(_ window: Kind) -> InstrumentID {
        InstrumentID("b.kind.\(window.rawValue)")
    }
    public static func tier(_ window: Tier) -> InstrumentID {
        InstrumentID("b.tier.\(window.rawValue)")
    }
    public static func warning(_ window: Warning) -> InstrumentID {
        InstrumentID("b.warn.\(window.rawValue)")
    }

    public static let totalCost: InstrumentID = "b.drum.cost"
    public static let totalOutput: InstrumentID = "b.drum.output"
    public static let linesAdded: InstrumentID = "b.drum.added"
    public static let linesRemoved: InstrumentID = "b.drum.removed"

    public static let targetB: InstrumentID = "b.nixie.target"
    /// The guarded keys. F10 and F11 have no job yet; F12, behind its key, ends a session.
    public static let f10: InstrumentID = "b.f10"
    public static let f11: InstrumentID = "b.f11"
    public static let f12: InstrumentID = "b.f12"

    // MARK: Panel C · control, selected session

    public static let targetC: InstrumentID = "c.nixie.target"

    public static func function(_ number: Int) -> InstrumentID { InstrumentID("c.f\(number)") }

    // MARK: Panel D · computer controls

    public static let sleepMode: InstrumentID = "d.sleep"
    public static let monitorOff: InstrumentID = "d.monitor"
    public static let fc1: InstrumentID = "d.fc1"
    public static let fc2: InstrumentID = "d.fc2"

    /// The green ON lens above a round button.
    public static func lensOn(_ button: InstrumentID) -> InstrumentID {
        InstrumentID(button.rawValue + ".on")
    }

    /// The white OFF lens above a round button.
    public static func lensOff(_ button: InstrumentID) -> InstrumentID {
        InstrumentID(button.rawValue + ".off")
    }

    public static let batteryMeter: InstrumentID = "d.meter.battery"
    public static let onMains: InstrumentID = "d.power.mains"
    public static let onBattery: InstrumentID = "d.power.battery"
    public static let charging: InstrumentID = "d.power.charging"
    public static let batteryLow: InstrumentID = "d.power.battlow"

    // MARK: Panel E · power and service

    public static let mains: InstrumentID = "e.mains"
    public static let powerOn: InstrumentID = "e.poweron"
    public static let hoursInService: InstrumentID = "e.drum.hours"

    // MARK: Groups

    public static let routine: [InstrumentID] = (1...9).map(function)
    public static let guarded: [InstrumentID] = [f10, f11, f12]
    public static let round: [InstrumentID] = [sleepMode, monitorOff, fc1, fc2]
    /// Only F12 has a key switch.
    public static let keyed: Set<InstrumentID> = [f12]
    public static let alarmBoard: [InstrumentID] =
        slots.flatMap { [annunciator(.wait, slot: $0), annunciator(.block, slot: $0)] }
        + [warning(.stale), batteryLow]

    /// Every nixie row, with the characters its tubes can show. The view draws one cell
    /// per character of the template and never changes the count; the model always hands
    /// it a string of exactly this length.
    public static let nixies: [InstrumentID: String] = [
        sessionsRunning: "0", sessionsBusy: "0",
        selected: "0", targetB: "0", targetC: "0",
        contextUsed: "00000000", inputTokens: "00000000", outputTokens: "00000000",
        thinkingTokens: "00000000", cacheRead: "00000000", cacheWritten: "00000000",
        // The column beside the token rows: six tubes each, so all six line up with COST.
        queueDepth: "000000", toolCalls: "000000", lastTurn: "0000:00",
        turnMessages: "000000", uptime: "0000:00", cost: "0000.00",
    ]

    /// Top to bottom as the desk is drawn, for the power-up strike. Readouts on the same
    /// line strike together.
    public static let nixieRows: [[InstrumentID]] = [
        [targetC],
        [selected],
        [contextUsed, queueDepth],
        [inputTokens, toolCalls],
        [outputTokens, lastTurn],
        [thinkingTokens, turnMessages],
        [cacheRead, uptime],
        [cacheWritten, cost],
        [sessionsRunning, sessionsBusy],
        [targetB],
    ]

    /// Every lamp window and lens on the desk, which is what LAMP TEST lights.
    public static var allLamps: [InstrumentID] {
        var lamps: [InstrumentID] = []
        for slot in slots {
            lamps += AnnunciatorRow.allCases.map { annunciator($0, slot: slot) }
        }
        lamps.append(silenced)
        lamps += Permission.allCases.map(permission)
        lamps += Effort.allCases.map(effort)
        lamps += Model.allCases.map(model)
        lamps += Mode.allCases.map(mode)
        lamps += Kind.allCases.map(kind)
        lamps += Tier.allCases.map(tier)
        lamps += Warning.allCases.map(warning)
        lamps += round.flatMap { [lensOn($0), lensOff($0)] }
        lamps += [onMains, onBattery, charging, batteryLow, powerOn]
        return lamps
    }

    /// Every button with a cap that can light.
    public static let litButtons: [InstrumentID] =
        [silence, acknowledge, lampTest, buzzerTest, printText] + routine + guarded

    public static let meters: [InstrumentID] = [contextMeter, apiShareMeter, toolShareMeter]
}
