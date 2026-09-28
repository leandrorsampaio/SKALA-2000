import ConsoleKit

/// What each instrument says to VoiceOver: its plate, and its value in words.
public enum DeskWords {
    public static func lamp(_ state: LampState) -> String {
        switch state {
        case .off: "dark"
        case .on: "lit"
        case .flash: "alarm, flashing"
        case .test: "lamp test"
        }
    }

    public static func digits(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? "dark" : text
    }

    public static func meter(_ value: Double) -> String {
        value < 0 ? "no reading" : "\(Int((value * 100).rounded())) percent"
    }

    /// POWER DRAWN reads watts on a scale of 0 to `PK4.powerScale`, not a share.
    public static func meter(_ value: Double, of id: InstrumentID) -> String {
        guard id == PK4.loadMeter(.power), value >= 0 else { return meter(value) }
        return "\(Int((value * PK4.powerScale).rounded())) watts"
    }

    /// Spoken when an alarm is raised.
    public static func alarm(_ id: InstrumentID, selector: Int) -> String? {
        for slot in PK4.slots {
            if id == PK4.annunciator(.wait, slot: slot) {
                return "Waiting for operator, session \(slot), alarm"
            }
            if id == PK4.annunciator(.block, slot: slot) {
                return "Blocked, session \(slot), alarm"
            }
        }
        if id == PK4.warning(.stale) { return "Data stale, session \(selector), alarm" }
        if id == PK4.batteryLow { return "Battery low, alarm" }
        return nil
    }
}
