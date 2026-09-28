import Foundation

/// The four things a lamp can be. Every window, lens and lit cap on the desk takes one.
public enum LampState: String, Sendable, Equatable, Codable {
    case off
    case on
    /// An alarm: until ACKNOWLEDGE for the desk's own, for as long as it holds for panel A's
    /// red rows and AT LIMIT. The view flashes it from one shared 2 Hz clock.
    case flash
    /// LAMP TEST is held, or the power-up test is running.
    case test
}

/// `idle → down → sent → confirmed | noAnswer → idle`, for every button on the desk.
public enum CommandPhase: String, Sendable, Equatable {
    case idle
    /// The cap is held down and nothing has been sent.
    case down
    /// Sent, and waiting for the machine. Further presses are ignored.
    case sent
    /// The machine reported the new state. The lamp answers now, not before.
    case confirmed
    /// Nothing came back in 3 s. The cap blinks six times and stays dark.
    case noAnswer
}

/// What a button's view needs: where the cap is, and whether its lamp is lit.
public struct ButtonFace: Sendable, Equatable {
    public var capDown: Bool
    public var lamp: LampState
    public var phase: CommandPhase

    public init(capDown: Bool = false, lamp: LampState = .off, phase: CommandPhase = .idle) {
        self.capDown = capDown
        self.lamp = lamp
        self.phase = phase
    }

    public static let idle = ButtonFace()
}

/// The paint on the steel. One per console, never mixed.
public enum Finish: String, Codable, Sendable, CaseIterable {
    case greyGreen, ivory, graphite
}

/// What the desk says when a session's state begins: once, and nothing while silenced.
public enum Signal: String, CaseIterable, Sendable {
    /// A turn done: one buzz.
    case done
    /// Waiting for the operator: two quick buzzes.
    case wait
    /// Compacting: three quick buzzes.
    case compact
    /// Blocked, and the desk's own alarms, DATA STALE and BATT LOW: one long buzz.
    case block
    /// Under 5% of the context left: a beep, higher than the buzzer and nothing like it.
    case lowContext
    /// A plan usage window past 80%, or past 95%: the same beep.
    case quota
}

/// One-shot events with nothing to show, for the sound layer. Each counts up when it
/// happens; a view plays its sound when the number moves. Window changes are not here:
/// the sound layer hears those by comparing lamps.
public struct ConsoleCues: Sendable, Equatable {
    /// A time-delay relay pulled in: a guarded hold reached 2 s.
    public var relay = 0
    /// The 80 ms buzzer chirp of the power-up lamp test.
    public var chirp = 0
    /// PRINT TO LOG wrote to the text log and wants its window open.
    public var openLog = 0
    /// How many of each signal have been given, so none is lost however the desk's
    /// changes are coalesced before the sound layer hears them.
    public var signals: [Signal: Int] = [:]

    public func count(_ signal: Signal) -> Int { signals[signal] ?? 0 }

    public init() {}
}

/// Exactly the value each instrument needs, keyed by its id.
///
/// Anything missing reads as that instrument's dark value — off, unlit tubes, needle on the
/// left stop — so an entry the model forgot can never light a wrong window.
public struct ConsoleSnapshot: Sendable, Equatable {

    /// Only lamps that are not off.
    public var lamps: [InstrumentID: LampState] = [:]
    /// Exactly as long as the readout's template in `PK4.nixies`. A space is an unlit tube.
    public var nixies: [InstrumentID: String] = [:]
    /// Needle position, −0.03 (left stop) to 1.03.
    public var meters: [InstrumentID: Double] = [:]
    public var drums: [InstrumentID: Int] = [:]
    public var buttons: [InstrumentID: ButtonFace] = [:]
    public var guardsOpen: Set<InstrumentID> = []
    public var keysArmed: Set<InstrumentID> = []
    /// Slot 1 to 4.
    public var pencils: [Int: String] = [:]
    public var selector = 1
    public var mains = true
    public var buzzer = false
    /// The highest Claude Code build among running sessions, for the paper card.
    public var programBuild: String?
    public var finish: Finish = .greyGreen
    public var cues = ConsoleCues()

    public init() {}

    public func lamp(_ id: InstrumentID) -> LampState { lamps[id] ?? .off }

    public func nixie(_ id: InstrumentID) -> String {
        nixies[id] ?? NixieFormat.dark(PK4.nixies[id] ?? "")
    }

    public func meter(_ id: InstrumentID) -> Double { meters[id] ?? Needle.leftStop }

    public func drum(_ id: InstrumentID) -> Int { drums[id] ?? 0 }

    public func button(_ id: InstrumentID) -> ButtonFace { buttons[id] ?? .idle }

    public func pencil(slot: Int) -> String { pencils[slot] ?? "" }
}

/// Where a needle rests.
public enum Needle {
    /// With power off, or nothing to measure, a moving-coil needle lies on its left stop.
    /// Below zero, so it can be told from a reading of zero; the skin draws it on zero.
    public static let leftStop = -0.03
    public static let rightStop = 1.03
}

/// Everything the operator can do. Views send these and never touch the model's insides.
public enum ConsoleIntent: Sendable, Equatable {
    /// One detent clockwise (+1) or back (−1). The switch is pinned: it does not wrap.
    case selectorStep(Int)
    /// Walk to a numeral one detent at a time, so the sessions between are passed through.
    case selectorGoTo(Int)
    case press(InstrumentID)
    case release(InstrumentID)
    case `guard`(InstrumentID, open: Bool)
    case key(InstrumentID, armed: Bool)
    case mains(Bool)
    case pencil(slot: Int, text: String)
}

/// Every duration the rules depend on, from `10-interaction.md` and the component
/// guidelines.
public enum ConsoleTiming {
    public static let noAnswer: TimeInterval = 3
    public static let momentaryGlow: TimeInterval = 0.6
    /// A test shows for at least this long, however briefly its button was pressed: a
    /// click is over before anyone could see what it lit.
    public static let testMinimum: TimeInterval = 1.5
    public static let guardedGlow: TimeInterval = 1.5
    /// Six blinks at 160 ms.
    public static let noAnswerBlink: TimeInterval = 0.96
    public static let holdToFire: TimeInterval = 2
    /// The share of context left below which LOW CONTEXT lights.
    public static let lowContext = 0.05
    /// The share of a plan usage window used from which its amber lamp lights, and its red.
    public static let quotaNear = 0.8
    public static let quotaLimit = 0.95
    public static let guardFallsAfter: TimeInterval = 5
    public static let selectorDetent: TimeInterval = 0.11
    public static let powerOnLamp: TimeInterval = 0.25
    public static let strikeStagger: TimeInterval = 0.04
    public static let strikeHold: TimeInterval = 0.12
    public static let lampTest: TimeInterval = 1
    /// At most ten snapshots a second from telemetry.
    public static let coalesce: TimeInterval = 0.1
    /// At most four digit changes a second per readout.
    public static let nixieThrottle: TimeInterval = 0.25
    /// A session announced by a hook is not released by a roster that has not caught up.
    public static let hookGrace: TimeInterval = 10
    public static let saveDebounce: TimeInterval = 1
    /// A session nobody lists and nothing has heard from is forgotten after this.
    public static let forgetSession: TimeInterval = 10 * 60
}

/// Where the model gets the time. Tests move it by hand.
@MainActor
public protocol ConsoleClock: AnyObject {
    var now: Date { get }
}

@MainActor
public final class SystemClock: ConsoleClock {
    public init() {}
    public var now: Date { Date() }
}

@MainActor
public final class ManualClock: ConsoleClock {
    public var now: Date

    public init(_ now: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        self.now = now
    }

    public func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}
