import Foundation
import TelemetryKit

/// One line of the safety log: append-only, one JSON object per line once it is on disk.
///
/// Every command sent and how it ended, every guard lift and key turn, every alarm raised,
/// silenced, acknowledged and cleared, and every source error, with the session it
/// concerned.
public struct SafetyEntry: Codable, Equatable, Sendable {

    public enum Event: String, Codable, Sendable {
        case commandSent = "command.sent"
        case commandConfirmed = "command.confirmed"
        case commandNoAnswer = "command.noAnswer"
        case guardLifted = "guard.lift"
        case guardLowered = "guard.lower"
        case keyArmed = "key.arm"
        case keyDisarmed = "key.disarm"
        case alarmRaised = "alarm.raise"
        case alarmSilenced = "alarm.silence"
        case alarmAcknowledged = "alarm.acknowledge"
        case alarmCleared = "alarm.clear"
        case sourceError = "source.error"
        case slotTaken = "slot.take"
        case slotReleased = "slot.release"
        case slotRefused = "slot.refuse"
        case mainsOn = "mains.on"
        case mainsOff = "mains.off"
    }

    public var at: Date
    public var event: Event
    public var instrument: InstrumentID?
    public var slot: Int?
    public var session: SessionKey?
    public var detail: String?

    public init(
        at: Date, event: Event, instrument: InstrumentID? = nil, slot: Int? = nil,
        session: SessionKey? = nil, detail: String? = nil
    ) {
        self.at = at
        self.event = event
        self.instrument = instrument
        self.slot = slot
        self.session = session
        self.detail = detail
    }
}

/// Where the console writes. The safety log is for what happened; the text log is the
/// console's only way to show a string, and it opens on PRINT TEXT.
@MainActor
public protocol ConsoleLog: AnyObject {
    func safety(_ entry: SafetyEntry)
    /// Appends lines to the text log. Returns false when they could not be written, so
    /// PRINT TEXT reports no answer instead of a lamp it has not earned.
    func text(_ lines: [String]) -> Bool
}

@MainActor
public final class MemoryConsoleLog: ConsoleLog {
    public private(set) var entries: [SafetyEntry] = []
    public private(set) var lines: [String] = []
    /// Makes `text` fail, to test PRINT TEXT's no-answer path.
    public var textFails = false

    public init() {}

    public func safety(_ entry: SafetyEntry) {
        entries.append(entry)
    }

    public func text(_ lines: [String]) -> Bool {
        guard !textFails else { return false }
        self.lines += lines
        return true
    }

    public func events(_ event: SafetyEntry.Event) -> [SafetyEntry] {
        entries.filter { $0.event == event }
    }
}

// MARK: - Commands

/// What a command is asked to do: which button, for which session, captured at the moment
/// it was sent.
public struct CommandRequest: Sendable, Equatable {
    public let button: InstrumentID
    public let ticket: Int
    /// The selector position when the button was released (or, for a guarded one, when
    /// its relay pulled in). Turning the selector afterwards does not redirect it.
    public let slot: Int
    public let session: SessionKey?
    public let issuedAt: Date
}

/// How one button reaches the machine.
///
/// Dispatching is not confirmation. A command confirms only when the machine reports the
/// new state — the observed field, or the command's own result through `reply` — and
/// anything that never answers is shown as no answer after 3 s.
public struct CommandAction {

    /// Sends the command. Call `reply` with the command's own result when there is one; a
    /// command that says nothing is shown as no answer.
    public var perform:
        @MainActor (CommandRequest, _ reply: @escaping @MainActor (Bool) -> Void) -> Void
    /// Stays lit while its state holds, rather than glowing for 600 ms.
    public var latching: Bool
    /// The machine flag a round button reports on its ON and OFF lenses. When set, only a
    /// reading of it confirms the command; `reply(true)` alone does not.
    public var observes: Field?
    /// How long it may take before it is shown as no answer. Three seconds, unless the
    /// command waits on the operator — for a password, say.
    public var timeout: TimeInterval

    public init(
        latching: Bool = false,
        observes: Field? = nil,
        timeout: TimeInterval = ConsoleTiming.noAnswer,
        perform:
            @escaping @MainActor (CommandRequest, _ reply: @escaping @MainActor (Bool) -> Void) ->
            Void
    ) {
        self.perform = perform
        self.latching = latching
        self.observes = observes
        self.timeout = timeout
    }

    /// Not yet defined. It sends nothing, so it always ends as no answer.
    public static func unassigned(observes: Field? = nil) -> CommandAction {
        CommandAction(observes: observes) { _, _ in }
    }
}

/// Every button that reaches outside the console. SILENCE, ACKNOWLEDGE, LAMP TEST and
/// PRINT TEXT are the console's own and are not here.
public struct ConsoleCommands {

    public var actions: [InstrumentID: CommandAction]

    public init(actions: [InstrumentID: CommandAction] = [:]) {
        self.actions = actions
    }

    /// F1 to F12 are to be defined. The round buttons arrive with the system commands;
    /// until then they too answer nothing.
    public static let unassigned = ConsoleCommands()

    func action(for id: InstrumentID) -> CommandAction {
        var action = actions[id] ?? .unassigned()
        if action.observes == nil { action.observes = Self.defaultObserved[id] }
        return action
    }

    /// What each round button reports on its lenses, whoever implements it. FC1 and FC2
    /// are the two Keep Awake modes: pressing one while the other is on switches modes,
    /// and each pair of lenses follows its own mode.
    static let defaultObserved: [InstrumentID: Field] = [
        PK4.sleepMode: .systemAsleep,
        PK4.monitorOff: .displayAsleep,
        PK4.fc1: .keepAwakeDisplayOn,
        PK4.fc2: .keepAwakeDisplayOff,
    ]
}
