import Foundation
import IOKit.pwr_mgt

/// The two ways FC1 and FC2 hold the Mac awake.
///
/// Both are *idle* assertions, which the power manager honours on battery as well as on
/// AC power, unlike `caffeinate -s`, which macOS only respects while plugged in.
public enum KeepAwakeMode: String, Codable, Sendable, CaseIterable {
    /// FC1 "Awake · display on": the Mac stays awake and the display stays lit. Holding the
    /// display awake also keeps the system awake.
    case displayOn
    /// FC2 "Awake · display off": the Mac stays awake, the display may sleep.
    case displayOff

    /// The IOKit assertion type.
    var assertionType: String {
        switch self {
        case .displayOn: return "PreventUserIdleDisplaySleep"
        case .displayOff: return "PreventUserIdleSystemSleep"
        }
    }
}

/// One process-owned IOKit power assertion, held in one of the two modes or not at all.
///
/// The assertion belongs to this process, so it disappears if the app quits or crashes:
/// the Mac can never be left stuck awake. The two modes are mutually exclusive; asking
/// for the mode already held releases it, which is what a press of FC1 or FC2 does.
@MainActor
public final class KeepAwake {

    public enum Failure: Error, Equatable {
        case assertionRefused(Int32)
    }

    /// The mode held now, or `nil`.
    public private(set) var mode: KeepAwakeMode?
    /// Told after every change, with the new mode.
    public var onChange: ((KeepAwakeMode?) -> Void)?

    private var assertionID = IOPMAssertionID(0)
    private let reason: String

    public init(reason: String = "SKALA-2000 Keep Awake") {
        self.reason = reason
    }

    /// Holds `mode` if it isn't held, releases it if it is. Switching from the other mode
    /// swaps the assertion.
    public func toggle(_ requested: KeepAwakeMode) throws {
        try set(mode == requested ? nil : requested)
    }

    /// Holds exactly `requested`, or nothing.
    public func set(_ requested: KeepAwakeMode?) throws {
        guard requested != mode else { return }
        releaseAssertion()
        if let requested {
            var newID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                requested.assertionType as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &newID)
            guard result == kIOReturnSuccess else {
                onChange?(nil)
                throw Failure.assertionRefused(result)
            }
            assertionID = newID
            mode = requested
        }
        onChange?(mode)
    }

    /// Lets go of whatever is held. Called on quit, although the kernel would anyway.
    public func releaseAll() {
        try? set(nil)
    }

    private func releaseAssertion() {
        guard mode != nil else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = IOPMAssertionID(0)
        mode = nil
    }

    /// Whether this process holds an assertion of `mode`'s type, according to the power
    /// manager itself rather than our own bookkeeping.
    public nonisolated static func isAsserted(_ mode: KeepAwakeMode) -> Bool {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
            let byProcess = unmanaged?.takeRetainedValue() as? [Int: [[String: Any]]]
        else { return false }
        let mine = byProcess[Int(getpid())] ?? []
        return mine.contains { ($0["AssertType"] as? String) == mode.assertionType }
    }
}
